import Testing
@testable import RigControl

@Test func hamlibRejectsInvalidMode() async throws {
    try await withFake { fake, rig in
        await #expect(throws: RigError.self) { try await rig.setMode("USB\nT 1") }
        await #expect(throws: RigError.self) { try await rig.setMode("") }
        #expect(!fake.ptt)
    }
}
