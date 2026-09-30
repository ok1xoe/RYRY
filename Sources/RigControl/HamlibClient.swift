// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// hamlib `rigctld` client (the default protocol, not the extended one).
/// On a connection failure it returns `.offline`; the next call tries to connect again.
public final class HamlibClient: Rig {
    private let conn: LineConnection
    public let name: String

    public init(host: String = "127.0.0.1", port: UInt16 = 4532, timeout: Duration = .seconds(2)) {
        conn = LineConnection(host: host, port: port, timeout: timeout)
        name = "hamlib \(host):\(port)"
    }

    public func connect() async throws { try await conn.open() }
    public func disconnect() async { await conn.close() }

    public func frequency() async throws -> Double {
        let r = try await conn.request("f", responseLines: 1)
        try Self.checkRPRT(r)
        guard let s = r.first, let f = Double(s), f.isFinite, f > 0 else {
            throw RigError.protocolError("frequency '\(r.first ?? "")'")
        }
        return f
    }

    public func setFrequency(_ hz: Double) async throws {
        try Self.checkRPRT(try await conn.request("F \(Int(hz.rounded()))", responseLines: 1))
    }

    public func mode() async throws -> String {
        let r = try await conn.request("m", responseLines: 2)
        try Self.checkRPRT(r)
        guard let m = r.first, !m.isEmpty else { throw RigError.protocolError("mode") }
        return m
    }

    public func setMode(_ mode: String) async throws {
        // the mode name only (USB, PKTUSB, RTTY…) – nothing that could inject another rigctld command
        guard !mode.isEmpty, mode.count <= 16, mode.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
            throw RigError.protocolError("neplatný mód '\(mode)'")
        }
        try Self.checkRPRT(try await conn.request("M \(mode) 0", responseLines: 1))
    }

    public func setPTT(_ on: Bool) async throws {
        try Self.checkRPRT(try await conn.request("T \(on ? 1 : 0)", responseLines: 1))
    }

    /// `RPRT 0` = OK; `RPRT -n` = an error. A response carrying data has no RPRT.
    static func checkRPRT(_ lines: [String]) throws {
        guard let last = lines.last, last.hasPrefix("RPRT ") else { return }
        let code = Int(last.dropFirst(5).trimmingCharacters(in: .whitespaces)) ?? -999
        if code != 0 { throw RigError.rejected(code) }
    }
}
