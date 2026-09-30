// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
package cz.ok1xoe.mmtty4mac;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Minimal JSON (RFC 8259) with no dependencies: object = Map, array = List, numbers = Long/Double. */
public final class Json {
    private Json() {}

    public static String write(Object v) {
        StringBuilder sb = new StringBuilder();
        write(v, sb);
        return sb.toString();
    }

    @SuppressWarnings("unchecked")
    private static void write(Object v, StringBuilder sb) {
        if (v == null) sb.append("null");
        else if (v instanceof String s) str(s, sb);
        else if (v instanceof Boolean || v instanceof Integer || v instanceof Long) sb.append(v);
        else if (v instanceof Number n) {
            double d = n.doubleValue();
            if (Double.isNaN(d) || Double.isInfinite(d)) throw new IllegalArgumentException("JSON: " + d);
            sb.append(d == Math.rint(d) && Math.abs(d) < 1e15 ? Long.toString((long) d) : Double.toString(d));
        } else if (v instanceof Map<?, ?> m) {
            sb.append('{');
            boolean first = true;
            for (Map.Entry<?, ?> e : m.entrySet()) {
                if (!first) sb.append(',');
                first = false;
                str(String.valueOf(e.getKey()), sb);
                sb.append(':');
                write(e.getValue(), sb);
            }
            sb.append('}');
        } else if (v instanceof Iterable<?> it) {
            sb.append('[');
            boolean first = true;
            for (Object o : it) { if (!first) sb.append(','); first = false; write(o, sb); }
            sb.append(']');
        } else if (v instanceof int[] a) {
            List<Object> l = new ArrayList<>();
            for (int x : a) l.add(x);
            write(l, sb);
        } else str(v.toString(), sb);
    }

    private static void str(String s, StringBuilder sb) {
        sb.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"' -> sb.append("\\\"");
                case '\\' -> sb.append("\\\\");
                case '\n' -> sb.append("\\n");
                case '\r' -> sb.append("\\r");
                case '\t' -> sb.append("\\t");
                default -> {
                    if (c < 0x20) sb.append(String.format("\\u%04x", (int) c)); else sb.append(c);
                }
            }
        }
        sb.append('"');
    }

    public static Object parse(String s) {
        Parser p = new Parser(s);
        Object v = p.value();
        p.ws();
        if (p.i != s.length()) throw new IllegalArgumentException("JSON: extra characters at position " + p.i);
        return v;
    }

    private static final class Parser {
        final String s;
        int i;
        Parser(String s) { this.s = s; }

        void ws() { while (i < s.length() && Character.isWhitespace(s.charAt(i))) i++; }

        IllegalArgumentException err(String m) { return new IllegalArgumentException("JSON: " + m + " at position " + i); }

        Object value() {
            ws();
            if (i >= s.length()) throw err("unexpected end of input");
            char c = s.charAt(i);
            switch (c) {
                case '{': return obj();
                case '[': return arr();
                case '"': return string();
                case 't': expect("true"); return Boolean.TRUE;
                case 'f': expect("false"); return Boolean.FALSE;
                case 'n': expect("null"); return null;
                default: return number();
            }
        }

        void expect(String w) {
            if (!s.startsWith(w, i)) throw err("expected " + w);
            i += w.length();
        }

        Map<String, Object> obj() {
            Map<String, Object> m = new LinkedHashMap<>();
            i++;
            ws();
            if (i < s.length() && s.charAt(i) == '}') { i++; return m; }
            while (true) {
                ws();
                String k = string();
                ws();
                if (i >= s.length() || s.charAt(i) != ':') throw err("expected ':'");
                i++;
                m.put(k, value());
                ws();
                if (i >= s.length()) throw err("unterminated object");
                char c = s.charAt(i++);
                if (c == '}') return m;
                if (c != ',') throw err("expected ',' or '}'");
            }
        }

        List<Object> arr() {
            List<Object> l = new ArrayList<>();
            i++;
            ws();
            if (i < s.length() && s.charAt(i) == ']') { i++; return l; }
            while (true) {
                l.add(value());
                ws();
                if (i >= s.length()) throw err("unterminated array");
                char c = s.charAt(i++);
                if (c == ']') return l;
                if (c != ',') throw err("expected ',' or ']'");
            }
        }

        String string() {
            if (i >= s.length() || s.charAt(i) != '"') throw err("expected a string");
            i++;
            StringBuilder sb = new StringBuilder();
            while (true) {
                if (i >= s.length()) throw err("unterminated string");
                char c = s.charAt(i++);
                if (c == '"') return sb.toString();
                if (c != '\\') { sb.append(c); continue; }
                if (i >= s.length()) throw err("unterminated escape");
                char e = s.charAt(i++);
                switch (e) {
                    case '"', '\\', '/' -> sb.append(e);
                    case 'b' -> sb.append('\b');
                    case 'f' -> sb.append('\f');
                    case 'n' -> sb.append('\n');
                    case 'r' -> sb.append('\r');
                    case 't' -> sb.append('\t');
                    case 'u' -> {
                        if (i + 4 > s.length()) throw err("incomplete \\u");
                        sb.append((char) Integer.parseInt(s.substring(i, i + 4), 16));
                        i += 4;
                    }
                    default -> throw err("invalid escape \\" + e);
                }
            }
        }

        Object number() {
            int st = i;
            if (i < s.length() && s.charAt(i) == '-') i++;
            while (i < s.length() && "0123456789.eE+-".indexOf(s.charAt(i)) >= 0) i++;
            String t = s.substring(st, i);
            if (t.isEmpty() || t.equals("-")) throw err("invalid value");
            if (t.contains(".") || t.contains("e") || t.contains("E")) return Double.parseDouble(t);
            try { return Long.parseLong(t); } catch (NumberFormatException ex) { return Double.parseDouble(t); }
        }
    }
}
