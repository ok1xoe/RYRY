// Copyright 2026 OK1XOE (RYRY), LGPL v3
package cz.ok1xoe.ryry;

import java.net.URI;
import java.util.Map;

/**
 * Example of connecting a logger to RYRY.
 *
 * <ul>
 *   <li>Prints the received text (rx.char).</li>
 *   <li>Reacts to a logged QSO (qso.logged).</li>
 *   <li>Passes the callsign to the QSO window and shows the DXCC entity.</li>
 * </ul>
 *
 * <pre>
 *   javac -d out $(find src -name '*.java')
 *   java -cp out cz.ok1xoe.ryry.Example [ws://127.0.0.1:7363/v1] [DL1ABC]
 * </pre>
 */
public final class Example {
    public static void main(String[] args) throws Exception {
        URI uri = args.length > 0 ? URI.create(args[0]) : RyryClient.DEFAULT_URI;
        String call = args.length > 1 ? args[1] : "DL1ABC";
        try (RyryClient c = RyryClient.connect(uri)) {
            c.onNotification((method, p) -> {
                switch (method) {
                    case "rx.char" -> { if (!Boolean.TRUE.equals(p.get("echo"))) System.out.print(p.get("char")); }
                    case "qso.logged" -> System.out.println("\n[logger] logged: " + p.get("call") + " " + p.get("band"));
                    case "engine.state" -> System.out.println("\n[state] " + p.get("state"));
                    default -> { }
                }
            });
            c.subscribe("rx.char", "qso.logged", "engine.state");
            Map<String, Object> st = c.status();
            System.out.println("RYRY: " + st.get("mode") + ", state " + st.get("state"));
            c.setQsoField("call", call);
            Map<String, Object> dx = c.dxcc(call);
            System.out.println(call + " → " + (dx == null ? "unknown entity" : dx.get("name") + " (" + dx.get("continent") + ", CQ " + dx.get("cqZone") + ")"));
            System.out.println("Listening to the receive side for 30 s… (Ctrl-C quits)");
            c.closedFuture().get(30, java.util.concurrent.TimeUnit.SECONDS);
        } catch (java.util.concurrent.TimeoutException done) {
            System.out.println("\nend of the example");
        }
    }
}
