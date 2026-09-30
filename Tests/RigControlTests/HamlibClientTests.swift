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
        let f = try await rig.frequency()                     // the client is still usable
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
        // the first attempt after an outage may fail as offline, the next one must reconnect
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

/// Review (critical): concurrent requests (a frequency poll + PTT) must not scramble the response stream.
@Test func concurrentRequestsStayInSync() async throws {
    try await withFake { fake, rig in
        fake.replyDelayMs = 5
        var errors = 0, wrong = 0
        for _ in 0..<30 {
            async let f = rig.frequency()
            async let p: Void = rig.setPTT(true)
            async let m = rig.mode()
            do {
                let (fv, _, mv) = try await (f, p, m)
                if fv != 14_080_000 || mv != "PKTUSB" { wrong += 1 }
            } catch { errors += 1 }
        }
        #expect(errors == 0 && wrong == 0, "errors \(errors) wrong \(wrong)")
    }
}
