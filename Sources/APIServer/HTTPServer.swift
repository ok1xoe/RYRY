// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Network

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]     // klíče malými písmeny
    public let body: Data
    public let remote: String
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data
    public init(status: Int, headers: [String: String], body: Data) { self.status = status; self.headers = headers; self.body = body }
}

public enum APIServerError: Error, Equatable, Sendable { case bind(String) }

/// Minimální HTTP/1.1 server (POST s Content-Length, keep-alive) nad Network.framework.
public final class HTTPServer: @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private let maxBody: Int
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "HTTPServer")

    public init(host: String, port: UInt16, maxBody: Int = 1 << 20,
                handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        self.host = host; self.port = port; self.maxBody = maxBody; self.handler = handler
    }

    /// Spustí server; vrací skutečný port (port 0 = náhodný).
    public func start() async throws -> UInt16 {
        let l = try makeListener(host: host, port: port)
        listener = l
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        let port = try await startListener(l, queue: queue)
        return port
    }

    public func stop() { listener?.cancel(); listener = nil }

    private func accept(_ c: NWConnection) {
        let conn = HTTPConnection(c, maxBody: maxBody, handler: handler)
        conn.start(queue: queue)
    }
}

func makeListener(host: String, port: UInt16, ws: Bool = false) throws -> NWListener {
    let params: NWParameters = ws ? {
        let p = NWParameters.tcp
        let o = NWProtocolWebSocket.Options(); o.autoReplyPing = true
        p.defaultProtocolStack.applicationProtocols.insert(o, at: 0)
        return p
    }() : .tcp
    params.allowLocalEndpointReuse = false
    params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? .any)
    do { return try NWListener(using: params) } catch { throw APIServerError.bind("\(host):\(port): \(error)") }
}

final class OnceBox: @unchecked Sendable {
    private let lock = NSLock(); private var done = false
    func first() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}

func startListener(_ l: NWListener, queue: DispatchQueue) async throws -> UInt16 {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
        let once = OnceBox()
        l.stateUpdateHandler = { st in
            switch st {
            case .ready: if once.first() { cont.resume(returning: l.port?.rawValue ?? 0) }
            case .failed(let e), .waiting(let e):
                if once.first() { l.cancel(); cont.resume(throwing: APIServerError.bind("\(e)")) }
            case .cancelled: if once.first() { cont.resume(throwing: APIServerError.bind("cancelled")) }
            default: break
            }
        }
        l.start(queue: queue)
    }
}

/// Jedno HTTP spojení: inkrementální parser, keep-alive.
final class HTTPConnection: @unchecked Sendable {
    private let c: NWConnection
    private let maxBody: Int
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    private var buf = Data()
    private let remote: String

    init(_ c: NWConnection, maxBody: Int, handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        self.c = c; self.maxBody = maxBody; self.handler = handler
        remote = "\(c.endpoint)"
    }

    func start(queue: DispatchQueue) {
        c.start(queue: queue)
        receive()
    }

    private func receive() {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, done, err in
            if let data { buf.append(data) }
            if err != nil { c.cancel(); return }
            processBuffer(eof: done)
        }
    }

    private func fail(_ status: Int, _ msg: String) {
        send(HTTPResponse(status: status, headers: ["Connection": "close"], body: Data(msg.utf8)), close: true)
    }

    private func processBuffer(eof: Bool) {
        guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else {
            if buf.count > 16384 { fail(431, "headers too large"); return }
            if eof { c.cancel(); return }
            receive(); return
        }
        let head = String(decoding: buf[buf.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let reqLine = lines.removeFirst().split(separator: " ")
        guard reqLine.count >= 3, reqLine[2].hasPrefix("HTTP/1.") else { fail(400, "bad request"); return }
        var headers: [String: String] = [:]
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let method = String(reqLine[0])
        var length = 0
        if let cl = headers["content-length"] {
            guard let n = Int(cl), n >= 0 else { fail(400, "bad length"); return }
            length = n
        } else if method == "POST" || method == "PUT" {
            fail(411, "length required"); return
        }
        if length > maxBody { fail(413, "payload too large"); return }
        let bodyStart = headerEnd.upperBound
        guard buf.count - (bodyStart - buf.startIndex) >= length else {
            if eof { c.cancel(); return }
            receive(); return
        }
        let body = buf[bodyStart..<(bodyStart + length)]
        buf.removeSubrange(buf.startIndex..<(bodyStart + length))
        let req = HTTPRequest(method: method, path: String(reqLine[1]), headers: headers, body: Data(body), remote: remote)
        let keepAlive = headers["connection"]?.lowercased() != "close"
        let h = handler
        Task { [self] in
            let resp = await h(req)
            self.send(resp, close: !keepAlive) {
                if keepAlive { self.processBuffer(eof: false) }
            }
        }
    }

    private func send(_ r: HTTPResponse, close: Bool, then: (@Sendable () -> Void)? = nil) {
        let reason = [200: "OK", 400: "Bad Request", 404: "Not Found", 411: "Length Required",
                      413: "Payload Too Large", 431: "Request Header Fields Too Large"][r.status] ?? "Status"
        var h = "HTTP/1.1 \(r.status) \(reason)\r\nContent-Length: \(r.body.count)\r\nServer: mmtty4mac\r\n"
        for (k, v) in r.headers where k.lowercased() != "content-length" { h += "\(k): \(v)\r\n" }
        if close && r.headers["Connection"] == nil { h += "Connection: close\r\n" }
        h += "\r\n"
        c.send(content: Data(h.utf8) + r.body, completion: .contentProcessed { [c] _ in
            if close { c.cancel() } else { then?() }
        })
    }
}
