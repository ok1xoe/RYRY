// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
package cz.ok1xoe.mmtty4mac;

import java.net.URI;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;

/** Test klienta: bez argumentu jen JSON, s URI i proti běžícímu mmtty4mac (rtty-tool live / aplikace). */
public final class SelfTest {
    static int failures = 0;
    static void check(boolean ok, String what) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what);
        if (!ok) failures++;
    }

    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        System.out.println("JSON:");
        Object o = Json.parse("{\"a\":[1,2.5,\"x\\n\\u00e9\",true,null],\"b\":{}}");
        Map<String, Object> m = (Map<String, Object>) o;
        check(((List<Object>) m.get("a")).get(0).equals(1L), "celé číslo → Long");
        check(((List<Object>) m.get("a")).get(1).equals(2.5), "desetinné → Double");
        check(((List<Object>) m.get("a")).get(2).equals("x\né"), "escape a \\u");
        check(Json.write(Map.of("t", "a\"b\r\n")).equals("{\"t\":\"a\\\"b\\r\\n\"}"), "zápis řetězce");
        check(Json.write(14083000.0).equals("14083000"), "celé double bez .0");
        boolean threw = false;
        try { Json.parse("{\"a\":}"); } catch (IllegalArgumentException e) { threw = true; }
        check(threw, "neplatný JSON → výjimka");

        if (args.length > 0) {
            System.out.println("Server " + args[0] + ":");
            try (Mmtty4macClient c = Mmtty4macClient.connect(URI.create(args[0]))) {
                List<String> events = new CopyOnWriteArrayList<>();
                c.onNotification((method, p) -> events.add(method));
                Map<String, Object> st = c.status();
                check(st.get("state") != null && st.get("mode") != null, "engine.status");
                c.subscribe("*");
                c.setQsoField("call", "DL1ABC");
                check("DL1ABC".equals(c.getQso().get("call")), "qso.setField / getCurrent");
                Map<String, Object> dx = c.dxcc("OK/DL1ABC");
                check(dx != null && "Czech Republic".equals(dx.get("name")), "dxcc.lookup");
                c.setMark(2100);
                check(((Number) c.getParams().get("mark")).doubleValue() == 2100, "modem.setParams mark");
                c.setMark(2125);
                try { c.call("no.such.method"); check(false, "neznámá metoda"); }
                catch (Mmtty4macClient.RpcException e) { check(e.code == -32601, "neznámá metoda → -32601"); }
                try { c.runMacro(99); check(false, "špatné makro"); }
                catch (Mmtty4macClient.RpcException e) { check(e.code == -32602, "špatné makro → -32602"); }
                c.clearQso();
                Thread.sleep(300);
                check(events.contains("qso.changed"), "notifikace qso.changed");
            }
        }
        System.out.println(failures == 0 ? "VŠE OK" : failures + " CHYB");
        System.exit(failures == 0 ? 0 : 1);
    }
}
