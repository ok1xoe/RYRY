// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

public enum XMLRPCCodec {
    // MARK: Encoding

    public static func encodeCall(method: String, params: [XMLRPCValue]) -> Data {
        var s = "<?xml version=\"1.0\"?>\n<methodCall><methodName>\(escape(method))</methodName><params>"
        for p in params { s += "<param>" + encode(p) + "</param>" }
        s += "</params></methodCall>\n"
        return Data(s.utf8)
    }

    public static func encodeResponse(_ value: XMLRPCValue) -> Data {
        Data(("<?xml version=\"1.0\"?>\n<methodResponse><params><param>" + encode(value)
              + "</param></params></methodResponse>\n").utf8)
    }

    public static func encodeFault(_ fault: XMLRPCFault) -> Data {
        let v = XMLRPCValue.dict(["faultCode": .int(fault.code), "faultString": .string(fault.message)])
        return Data(("<?xml version=\"1.0\"?>\n<methodResponse><fault>" + encode(v)
                     + "</fault></methodResponse>\n").utf8)
    }

    static func encode(_ v: XMLRPCValue) -> String {
        switch v {
        case .int(let i): return "<value><int>\(i)</int></value>"
        case .bool(let b): return "<value><boolean>\(b ? 1 : 0)</boolean></value>"
        case .string(let s): return "<value><string>\(escape(s))</string></value>"
        case .double(let d): return "<value><double>\(d)</double></value>"
        case .base64(let d): return "<value><base64>\(d.base64EncodedString())</base64></value>"
        case .nil_: return "<value><nil/></value>"
        case .array(let a): return "<value><array><data>" + a.map(encode).joined() + "</data></array></value>"
        case .dict(let d):
            return "<value><struct>" + d.keys.sorted().map {
                "<member><name>\(escape($0))</name>" + encode(d[$0]!) + "</member>"
            }.joined() + "</struct></value>"
        }
    }

    static func escape(_ s: String) -> String {
        var r = ""
        for c in s {
            switch c {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            default: r.append(c)
            }
        }
        return r
    }

    // MARK: Decoding

    public static func decodeCall(_ data: Data) throws -> (method: String, params: [XMLRPCValue]) {
        let root = try Node.parse(data)
        guard root.name == "methodCall", let m = root.child("methodName") else {
            throw XMLRPCCodecError.malformed("expected methodCall")
        }
        let params = try (root.child("params")?.children(named: "param") ?? []).map { p -> XMLRPCValue in
            guard let v = p.child("value") else { throw XMLRPCCodecError.malformed("param without value") }
            return try value(v)
        }
        return (m.text.trimmingCharacters(in: .whitespacesAndNewlines), params)
    }

    public static func decodeResponse(_ data: Data) throws -> XMLRPCValue {
        let root = try Node.parse(data)
        guard root.name == "methodResponse" else { throw XMLRPCCodecError.malformed("expected methodResponse") }
        if let f = root.child("fault") {
            guard let v = f.child("value"), case .dict(let d) = try value(v) else {
                throw XMLRPCCodecError.malformed("bad fault")
            }
            throw XMLRPCFault(code: d["faultCode"]?.intValue ?? 0, message: d["faultString"]?.stringValue ?? "")
        }
        guard let p = root.child("params")?.child("param")?.child("value") else {
            throw XMLRPCCodecError.malformed("response without value")
        }
        return try value(p)
    }

    static func value(_ n: Node) throws -> XMLRPCValue {
        guard let t = n.elements.first else { return .string(n.text) }   // no type = string
        let text = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch t.name {
        case "int", "i4", "i8":
            guard let i = Int(text) else { throw XMLRPCCodecError.malformed("int '\(text)'") }
            return .int(i)
        case "boolean":
            guard text == "0" || text == "1" else { throw XMLRPCCodecError.malformed("boolean '\(text)'") }
            return .bool(text == "1")
        case "double":
            guard let d = Double(text) else { throw XMLRPCCodecError.malformed("double '\(text)'") }
            return .double(d)
        case "string": return .string(t.text)
        case "base64":
            guard let d = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else {
                throw XMLRPCCodecError.malformed("base64")
            }
            return .base64(d)
        case "nil": return .nil_
        case "array":
            let vals = t.child("data")?.children(named: "value") ?? []
            return .array(try vals.map(value))
        case "struct":
            var d: [String: XMLRPCValue] = [:]
            for m in t.children(named: "member") {
                guard let name = m.child("name"), let v = m.child("value") else {
                    throw XMLRPCCodecError.malformed("member")
                }
                d[name.text] = try value(v)
            }
            return .dict(d)
        default:
            throw XMLRPCCodecError.malformed("unknown type \(t.name)")
        }
    }
}

/// A minimal DOM on top of XMLParser.
final class Node {
    let name: String
    var elements: [Node] = []
    var text = ""
    init(_ name: String) { self.name = name }

    func child(_ n: String) -> Node? { elements.first { $0.name == n } }
    func children(named n: String) -> [Node] { elements.filter { $0.name == n } }

    static func parse(_ data: Data) throws -> Node {
        let d = Delegate()
        let p = XMLParser(data: data)
        p.delegate = d
        guard p.parse(), let root = d.root else {
            throw XMLRPCCodecError.malformed(p.parserError?.localizedDescription ?? "parse error")
        }
        return root
    }

    final class Delegate: NSObject, XMLParserDelegate {
        var stack: [Node] = []
        var root: Node?
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let n = Node(name)
            stack.last?.elements.append(n)
            stack.append(n)
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let n = stack.removeLast()
            if stack.isEmpty { root = n }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }
    }
}
