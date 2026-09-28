import Foundation
import Testing
import XMLRPC
@testable import RigControl

final class StubTransport: XMLRPCTransport, @unchecked Sendable {
    var calls: [(String, [XMLRPCValue])] = []
    var responses: [String: Result<XMLRPCValue, Error>] = [:]
    func call(_ method: String, _ params: [XMLRPCValue]) async throws -> XMLRPCValue {
        calls.append((method, params))
        guard let r = responses[method] else { return .nil_ }
        return try r.get()
    }
}

@Test func mapsMethodsAndTypes() async throws {
    let t = StubTransport()
    t.responses["rig.get_vfo"] = .success(.string("14080000"))
    t.responses["rig.get_mode"] = .success(.string("USB-D"))
    t.responses["rig.get_xcvr"] = .success(.string("IC-7300"))
    let rig = FlrigClient(transport: t)
    try await rig.connect()
    #expect(try await rig.frequency() == 14_080_000)
    try await rig.setFrequency(7_045_000)
    #expect(try await rig.mode() == "USB-D")
    try await rig.setMode("LSB")
    try await rig.setPTT(true)
    #expect(t.calls.map(\.0) == ["rig.get_xcvr", "rig.get_vfo", "rig.set_frequency", "rig.get_mode",
                                 "rig.set_mode", "rig.set_ptt"])
    #expect(t.calls[2].1 == [.double(7_045_000)])
    #expect(t.calls[4].1 == [.string("LSB")])
    #expect(t.calls[5].1 == [.int(1)])
}

@Test func flrigFaultBecomesProtocolError() async throws {
    let t = StubTransport()
    t.responses["rig.get_vfo"] = .failure(XMLRPCFault(code: 1, message: "no rig"))
    let rig = FlrigClient(transport: t)
    await #expect(throws: RigError.protocolError("no rig")) { _ = try await rig.frequency() }
}

@Test func flrigGarbageFrequencyIsProtocolError() async throws {
    let t = StubTransport()
    t.responses["rig.get_vfo"] = .success(.string("abc"))
    let rig = FlrigClient(transport: t)
    await #expect(throws: RigError.self) { _ = try await rig.frequency() }
}

@Test func unreachableFlrigIsOffline() async throws {
    let rig = FlrigClient(host: "127.0.0.1", port: 1)
    await #expect(throws: RigError.offline) { _ = try await rig.frequency() }
}
