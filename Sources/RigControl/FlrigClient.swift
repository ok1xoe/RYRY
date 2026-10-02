// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import XMLRPC

/// Klient flrig (XML-RPC).
public final class FlrigClient: Rig {
    private let transport: XMLRPCTransport
    public let name: String

    public init(transport: XMLRPCTransport, name: String = "flrig") {
        self.transport = transport
        self.name = name
    }

    public convenience init(host: String = "127.0.0.1", port: Int = 12345) {
        self.init(transport: HTTPXMLRPCTransport(url: URL(string: "http://\(host):\(port)/RPC2")!),
                  name: "flrig \(host):\(port)")
    }

    private func call(_ m: String, _ p: [XMLRPCValue] = []) async throws -> XMLRPCValue {
        do { return try await transport.call(m, p) }
        catch let f as XMLRPCFault { throw RigError.protocolError(f.message) }
        catch let e as XMLRPCCodecError { throw RigError.protocolError("\(e)") }
    }

    public func connect() async throws { _ = try await call("rig.get_xcvr") }
    public func disconnect() async {}

    public func frequency() async throws -> Double {
        let v = try await call("rig.get_vfo")
        guard let f = v.doubleValue, f.isFinite, f > 0 else { throw RigError.protocolError("frequency \(v)") }
        return f
    }

    public func setFrequency(_ hz: Double) async throws { _ = try await call("rig.set_frequency", [.double(hz)]) }

    public func mode() async throws -> String {
        let v = try await call("rig.get_mode")
        guard let m = v.stringValue, !m.isEmpty else { throw RigError.protocolError("mode \(v)") }
        return m
    }

    public func setMode(_ mode: String) async throws { _ = try await call("rig.set_mode", [.string(mode)]) }
    public func setPTT(_ on: Bool) async throws { _ = try await call("rig.set_ptt", [.int(on ? 1 : 0)]) }
}
