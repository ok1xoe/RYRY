// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Network

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]     // keys in lowercase
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

/// A minimal HTTP/1.1 server (POST with Content-Length, keep-alive) on top of Network.framework.
public final class HTTPServer: @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private let maxBody: Int
    private let maxConnections: Int
    private let headerTimeout: Duration
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "HTTPServer")
    private let lock = NSLock()
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]

    public init(host: String, port: UInt16, maxBody: Int = 1 << 20, maxConnections: Int = 64,
                headerTimeout: Duration = .seconds(10),
                handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        self.host = host; self.port = port; self.maxBody = maxBody
        self.maxConnections = maxConnections; self.headerTimeout = headerTimeout; self.handler = handler
    }

    /// Starts the server; returns the actual port (port 0 = random).
    public func start() async throws -> UInt16 {
        let l = try makeListener(host: host, port: port)
        listener = l
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        return try await startListener(l, queue: queue)
    }

    /// Stops the listener and all open connections.
    public func stop() {
        listener?.cancel(); listener = nil
        let all = lock.withLock { () -> [HTTPConnection] in defer { connections.removeAll() }; return Array(connections.values) }
        all.forEach { $0.cancel() }
    }

    private func accept(_ c: NWConnection) {
        let full = lock.withLock { connections.count >= maxConnections }
        let conn = HTTPConnection(c, maxBody: maxBody, headerTimeout: headerTimeout, queue: queue, handler: handler)
        if full { conn.rejectBusy(); return }
        let id = ObjectIdentifier(conn)
        lock.withLock { connections[id] = conn }
        conn.onClose = { [weak self] in self?.lock.withLock { _ = self?.connections.removeValue(forKey: id) } }
        conn.start()
    }
}

func makeListener(host: String, port: UInt16, ws: Bool = false) throws -> NWListener {
    let params: NWParameters = ws ? {
        let p = NWParameters.tcp
        let o = NWProtocolWebSocket.Options(); o.autoReplyPing = true
        o.maximumMessageSize = 1 << 20
        // A browser sends Origin – a web page must not control the transmitter (native clients do not send Origin).
        o.setClientRequestHandler(DispatchQueue(label: "ws-handshake")) { _, headers in
            if headers.contains(where: { $0.name.lowercased() == "origin" }) {
                return NWProtocolWebSocket.Response(status: .reject, subprotocol: nil)
            }
            return NWProtocolWebSocket.Response(status: .accept, subprotocol: nil)
        }
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

/// A single HTTP connection: incremental parser, keep-alive. All state is mutated on `queue`.
final class HTTPConnection: @unchecked Sendable {
    private let c: NWConnection
    private let maxBody: Int
    private let headerTimeout: Duration
    private let queue: DispatchQueue
    private let handler: @Sendable (HTTPRequest) async -> HTTPResponse
    private var buf = Data()
    private let remote: String
    private var sentContinue = false
    private var closed = false
    private var timer: DispatchWorkItem?
    var onClose: (@Sendable () -> Void)?

    init(_ c: NWConnection, maxBody: Int, headerTimeout: Duration, queue: DispatchQueue,
         handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) {
        self.c = c; self.maxBody = maxBody; self.headerTimeout = headerTimeout; self.queue = queue; self.handler = handler
        remote = "\(c.endpoint)"
    }

    func start() {
        c.stateUpdateHandler = { [weak self] st in
            switch st { case .failed, .cancelled: self?.finish(); default: break }
        }
        c.start(queue: queue)
        armTimer()
        receive()
    }

    /// The server is full – answer 503 and close.
    func rejectBusy() {
        c.start(queue: queue)
        let body = Data("too many connections".utf8)
        c.send(content: Data("HTTP/1.1 503 Service Unavailable\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body,
               completion: .contentProcessed { [c] _ in c.cancel() })
    }

    func cancel() { queue.async { self.c.cancel() } }

    private func finish() {
        guard !closed else { return }
        closed = true
        timer?.cancel()
        onClose?()
    }

    /// The time limit for completing a request (headers and body) and for keep-alive idling.
    private func armTimer() {
        timer?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.fail(408, "request timeout") }
        timer = w
        let c = headerTimeout.components
        let ns = Int(c.seconds) * 1_000_000_000 + Int(c.attoseconds / 1_000_000_000)
        queue.asyncAfter(deadline: .now() + .nanoseconds(ns), execute: w)
    }

    private func receive() {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            if let data { self.buf.append(data) }
            if err != nil { self.c.cancel(); return }
            self.processBuffer(eof: done)
        }
    }

    private func fail(_ status: Int, _ msg: String) {
        timer?.cancel()
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
        let http11 = reqLine[2] != "HTTP/1.0"
        var headers: [String: String] = [:]
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        // A request from a browser (a web page) must not control the transmitter.
        if headers["origin"] != nil { fail(403, "browser requests are not allowed"); return }
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
            if headers["expect"]?.lowercased() == "100-continue", !sentContinue {
                sentContinue = true
                c.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .contentProcessed { _ in })
            }
            if eof { c.cancel(); return }
            receive(); return
        }
        timer?.cancel()
        sentContinue = false
        let body = buf[bodyStart..<(bodyStart + length)]
        buf.removeSubrange(buf.startIndex..<(bodyStart + length))
        let req = HTTPRequest(method: method, path: String(reqLine[1]), headers: headers, body: Data(body), remote: remote)
        let conn = headers["connection"]?.lowercased()
        let keepAlive = http11 ? conn != "close" : conn == "keep-alive"
        let h = handler
        Task {
            let resp = await h(req)
            self.queue.async {
                self.send(resp, close: !keepAlive) {
                    guard keepAlive else { return }
                    self.queue.async { self.armTimer(); self.processBuffer(eof: false) }
                }
            }
        }
    }

    private func send(_ r: HTTPResponse, close: Bool, then: (@Sendable () -> Void)? = nil) {
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 408: "Request Timeout",
                      411: "Length Required", 413: "Payload Too Large", 431: "Request Header Fields Too Large",
                      503: "Service Unavailable"][r.status] ?? "Status"
        var h = "HTTP/1.1 \(r.status) \(reason)\r\nContent-Length: \(r.body.count)\r\nServer: RYRY\r\n"
        for (k, v) in r.headers where k.lowercased() != "content-length" { h += "\(k): \(v)\r\n" }
        if close && r.headers["Connection"] == nil { h += "Connection: close\r\n" }
        h += "\r\n"
        c.send(content: Data(h.utf8) + r.body, completion: .contentProcessed { [c] _ in
            if close { c.cancel() } else { then?() }
        })
    }
}
