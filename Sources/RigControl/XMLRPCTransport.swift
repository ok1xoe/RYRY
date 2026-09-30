// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import XMLRPC

public protocol XMLRPCTransport: Sendable {
    func call(_ method: String, _ params: [XMLRPCValue]) async throws -> XMLRPCValue
}

/// XML-RPC over HTTP POST (flrig: http://host:12345/RPC2).
/// The URLSession is shut down when the transport goes away (otherwise it would linger after every restart).
final class SessionBox: @unchecked Sendable {
    let session: URLSession
    init(_ s: URLSession) { session = s }
    deinit { session.finishTasksAndInvalidate() }
}

public struct HTTPXMLRPCTransport: XMLRPCTransport {
    let url: URL
    private let box: SessionBox
    var session: URLSession { box.session }

    public init(url: URL, timeout: TimeInterval = 2) {
        self.url = url
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        box = SessionBox(URLSession(configuration: cfg))
    }

    public func call(_ method: String, _ params: [XMLRPCValue]) async throws -> XMLRPCValue {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        req.httpBody = XMLRPCCodec.encodeCall(method: method, params: params)
        let data: Data
        do {
            (data, _) = try await session.data(for: req)
        } catch let e as URLError where e.code == .timedOut {
            throw RigError.timeout
        } catch {
            throw RigError.offline
        }
        return try XMLRPCCodec.decodeResponse(data)
    }
}
