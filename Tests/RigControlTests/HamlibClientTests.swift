import Foundation
import Testing
@testable import RigControl

func withFake(_ body: (FakeRigctld, HamlibClient) async throws -> Void) async throws {
    let fake = FakeRigctld()
    try await fake.start()
    defer { fake.stop() }
    let rig = HamlibClient(host: "127.0.0.1", port: fake.port, timeout: .milliseconds(500))
    try await body(fake, rig)
    await rig.disconnect()
}

@Test func readsAndSetsFrequencyModeAndPTT() async throws {
    try await withFake { fake, rig in
        try await rig.connect()
        #expect(try await rig.frequency() == 14_080_000)
        try await rig.setFrequency(7_045_000)
        #expect(fake.freq == 7_045_000)
        #expect(try await rig.mode() == "PKTUSB")
        try await rig.setMode("USB")
        #expect(fake.rigMode == "USB")
        try await rig.setPTT(true)
        #expect(fake.ptt)
        try await rig.setPTT(false)
        #expect(!fake.ptt)
    }
}

@Test func rejectedCommandIsTypedError() async throws {
    try await withFake { fake, rig in
        fake.mode = .rejectAll
        await #expect(throws: RigError.rejected(-1)) { try await rig.setPTT(true) }
    }
}

@Test func garbageFrequencyIsProtocolError() async throws {
    try await withFake { fake, rig in
        fake.mode = .garbageFreq
        await #expect(throws: RigError.self) { _ = try await rig.frequency() }
        fake.mode = .normal
        let f = try await rig.frequency()                     // klient zůstal použitelný
        #expect(f == 14_080_000)
    }
}

@Test func silentRigTimesOut() async throws {
    try await withFake { fake, rig in
        fake.mode = .silent
        await #expect(throws: RigError.timeout) { _ = try await rig.frequency() }
    }
}

@Test func reconnectsAfterRigctldRestart() async throws {
    try await withFake { fake, rig in
        #expect(try await rig.frequency() == 14_080_000)
        fake.dropConnections()
        try await Task.sleep(for: .milliseconds(50))
        // první pokus po výpadku může selhat jako offline, další se musí připojit znovu
        var ok = false
        for _ in 0..<3 {
            if (try? await rig.frequency()) == 14_080_000 { ok = true; break }
        }
        #expect(ok)
    }
}

@Test func connectionRefusedIsOffline() async throws {
    let rig = HamlibClient(host: "127.0.0.1", port: 1, timeout: .milliseconds(500))
    await #expect(throws: RigError.offline) { _ = try await rig.frequency() }
}

@Test func noRigIsAlwaysOffline() async throws {
    let rig = NoRig()
    await #expect(throws: RigError.offline) { _ = try await rig.frequency() }
    await #expect(throws: RigError.offline) { try await rig.setPTT(true) }
}
