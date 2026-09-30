// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
package cz.ok1xoe.mmtty4mac;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.WebSocket;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.BiConsumer;

/**
 * Client for the JSON-RPC 2.0 API of mmtty4mac (ws://127.0.0.1:7363/v1) – JDK 21 only, no dependencies.
 *
 * <pre>{@code
 * try (var c = Mmtty4macClient.connect()) {
 *     c.onNotification((method, params) -> {
 *         if (method.equals("rx.char")) System.out.print(params.get("char"));
 *     });
 *     c.subscribe("rx.char", "qso.logged");
 *     c.setQsoField("call", "DL1ABC");
 *     c.runMacro(0);                      // F1
 * }
 * }</pre>
 *
 * All calls block with a timeout (5 s by default); an API error → {@link RpcException}.
 * Notifications are delivered from the WebSocket thread – the listener must not block (forward them to the UI thread).
 */
public final class Mmtty4macClient implements AutoCloseable {

    /** Error returned by the API (code per docs/api.md: -32001 TX rejected, -32002 rig, -32602 parameters…). */
    public static final class RpcException extends IOException {
        public final int code;
        public RpcException(int code, String message) { super(message + " (" + code + ")"); this.code = code; }
    }

    public static final URI DEFAULT_URI = URI.create("ws://127.0.0.1:7363/v1");

    private final WebSocket ws;
    private final AtomicLong nextId = new AtomicLong(1);
    private final Map<Long, CompletableFuture<Object>> pending = new ConcurrentHashMap<>();
    private final List<BiConsumer<String, Map<String, Object>>> listeners = new CopyOnWriteArrayList<>();
    private final CompletableFuture<Void> closed = new CompletableFuture<>();
    private volatile Duration timeout = Duration.ofSeconds(5);

    private Mmtty4macClient(WebSocket ws) { this.ws = ws; }

    public static Mmtty4macClient connect() throws IOException { return connect(DEFAULT_URI); }

    /** Connects (without an Origin header – the server rejects requests from a browser). */
    public static Mmtty4macClient connect(URI uri) throws IOException {
        Holder h = new Holder();
        try {
            WebSocket ws = HttpClient.newHttpClient().newWebSocketBuilder()
                    .connectTimeout(Duration.ofSeconds(5))
                    .buildAsync(uri, h)
                    .get(10, TimeUnit.SECONDS);
            Mmtty4macClient c = new Mmtty4macClient(ws);
            h.client = c;
            return c;
        } catch (Exception e) {
            throw new IOException("mmtty4mac: nelze se připojit k " + uri + ": " + e.getMessage(), e);
        }
    }

    public void setTimeout(Duration d) { this.timeout = d; }

    /** Notification listener (rx.char, engine.state, qso.logged, …); see {@link #subscribe}. */
    public void onNotification(BiConsumer<String, Map<String, Object>> l) { listeners.add(l); }

    /** Completes when the server closes the connection (or it drops). */
    public CompletableFuture<Void> closedFuture() { return closed; }

    // ---- generic call ----

    public Object call(String method) throws IOException { return call(method, Map.of()); }

    public Object call(String method, Map<String, ?> params) throws IOException {
        long id = nextId.getAndIncrement();
        CompletableFuture<Object> f = new CompletableFuture<>();
        pending.put(id, f);
        Map<String, Object> req = new LinkedHashMap<>();
        req.put("jsonrpc", "2.0");
        req.put("id", id);
        req.put("method", method);
        req.put("params", params);
        try {
            ws.sendText(Json.write(req), true).get(timeout.toMillis(), TimeUnit.MILLISECONDS);
            return f.get(timeout.toMillis(), TimeUnit.MILLISECONDS);
        } catch (java.util.concurrent.ExecutionException e) {
            if (e.getCause() instanceof RpcException r) throw r;
            throw new IOException(method + ": " + e.getCause(), e.getCause());
        } catch (java.util.concurrent.TimeoutException e) {
            throw new IOException(method + ": vypršel časový limit");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IOException(method + ": přerušeno");
        } finally {
            pending.remove(id);
        }
    }

    // ---- convenience methods (docs/api.md) ----

    @SuppressWarnings("unchecked")
    public Map<String, Object> status() throws IOException { return (Map<String, Object>) call("engine.status"); }
    public void subscribe(String... events) throws IOException { call("events.subscribe", Map.of("events", List.of(events))); }
    public void tx() throws IOException { call("engine.tx"); }
    /** RX once the queue has been sent. */
    public void rx() throws IOException { call("engine.rx"); }
    /** RX immediately (aborts the transmission). */
    public void rxNow() throws IOException { call("engine.rxNow"); }
    public void send(String text) throws IOException { call("tx.send", Map.of("text", text)); }
    public void clearTx() throws IOException { call("tx.clear"); }
    public void runMacro(int index) throws IOException { call("macro.run", Map.of("index", index)); }
    public void runMessage(int index) throws IOException { call("msg.run", Map.of("index", index)); }
    public void setQsoField(String name, String value) throws IOException { call("qso.setField", Map.of("name", name, "value", value)); }
    @SuppressWarnings("unchecked")
    public Map<String, Object> getQso() throws IOException { return (Map<String, Object>) call("qso.getCurrent"); }
    @SuppressWarnings("unchecked")
    public Map<String, Object> logQso() throws IOException { return (Map<String, Object>) call("qso.log"); }
    public void clearQso() throws IOException { call("qso.clear"); }
    public void setFrequency(double hz) throws IOException { call("rig.setFreq", Map.of("hz", hz)); }
    public void setMark(double hz) throws IOException { call("modem.setParams", Map.of("params", Map.of("mark", hz))); }
    @SuppressWarnings("unchecked")
    public Map<String, Object> getParams() throws IOException { return (Map<String, Object>) call("modem.getParams"); }
    @SuppressWarnings("unchecked")
    public Map<String, Object> dxcc(String call) throws IOException { return (Map<String, Object>) call("dxcc.lookup", Map.of("call", call)); }
    public String cabrillo() throws IOException {
        @SuppressWarnings("unchecked") Map<String, Object> r = (Map<String, Object>) call("log.exportCabrillo", Map.of("contestOnly", true));
        return (String) r.get("text");
    }

    @Override public void close() {
        try { ws.sendClose(WebSocket.NORMAL_CLOSURE, "bye").get(2, TimeUnit.SECONDS); } catch (Exception ignored) {}
        ws.abort();
        fail(new IOException("spojení zavřeno"));
    }

    // ---- receive ----

    private void fail(Throwable t) {
        for (CompletableFuture<Object> f : pending.values()) f.completeExceptionally(t);
        pending.clear();
        closed.complete(null);
    }

    @SuppressWarnings("unchecked")
    private void handle(String text) {
        Object o;
        try { o = Json.parse(text); } catch (IllegalArgumentException e) { return; }
        if (!(o instanceof Map)) return;
        Map<String, Object> m = (Map<String, Object>) o;
        Object id = m.get("id");
        if (id instanceof Number n) {
            CompletableFuture<Object> f = pending.get(n.longValue());
            if (f == null) return;
            if (m.get("error") instanceof Map<?, ?> err) {
                Object code = err.get("code");
                f.completeExceptionally(new RpcException(code instanceof Number c ? c.intValue() : -1, String.valueOf(err.get("message"))));
            } else {
                f.complete(m.get("result"));
            }
        } else if (m.get("method") instanceof String method) {
            Map<String, Object> params = m.get("params") instanceof Map ? (Map<String, Object>) m.get("params") : Map.of();
            for (BiConsumer<String, Map<String, Object>> l : listeners) {
                try { l.accept(method, params); } catch (RuntimeException ignored) {}
            }
        }
    }

    /** WebSocket.Listener; messages may arrive in parts. */
    private static final class Holder implements WebSocket.Listener {
        volatile Mmtty4macClient client;
        private final StringBuilder buf = new StringBuilder();
        private final List<String> early = new ArrayList<>();

        @Override public CompletionStage<?> onText(WebSocket w, CharSequence data, boolean last) {
            buf.append(data);
            if (last) {
                String s = buf.toString();
                buf.setLength(0);
                Mmtty4macClient c = client;
                if (c != null) {
                    synchronized (early) { for (String e : early) c.handle(e); early.clear(); }
                    c.handle(s);
                } else synchronized (early) { early.add(s); }
            }
            w.request(1);
            return null;
        }

        @Override public CompletionStage<?> onClose(WebSocket w, int code, String reason) {
            Mmtty4macClient c = client;
            if (c != null) c.fail(new IOException("server zavřel spojení: " + code + " " + reason));
            return null;
        }

        @Override public void onError(WebSocket w, Throwable error) {
            Mmtty4macClient c = client;
            if (c != null) c.fail(error);
        }
    }
}
