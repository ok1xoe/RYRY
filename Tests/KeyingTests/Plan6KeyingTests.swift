import Foundation
import Testing
import RigControl
import TestSupport
@testable import Keying

/// forceOff zkusí vypnout PTT i přes CAT, když je rig k dispozici (i když PTT metoda je RTS).
@Test func forceOffAlsoTriesCATWhenRigAvailable() async throws {
    let rig = RecordingRig()
    let ptt = PTTController(method: .rts, port: FakeSerialPort(), rig: rig)
    try await ptt.prepare()
    await ptt.forceOff()
    #expect(rig.ptt.last == false)
}

/// forceOff s rigem, který nikdy neodpoví, skončí do ~2 s.
@Test func forceOffWithHangingRigReturns() async throws {
    final class HangRig: Rig, @unchecked Sendable {
        var name: String { "hang" }
        func connect() async throws {}
        func disconnect() async {}
        func frequency() async throws -> Double { 0 }
        func setFrequency(_ hz: Double) async throws {}
        func mode() async throws -> String { "" }
        func setMode(_ mode: String) async throws {}
        func setPTT(_ on: Bool) async throws { try? await Task.sleep(for: .seconds(30)) }   // ignoruje zrušení
    }
    let ptt = PTTController(method: .cat, port: nil, rig: HangRig())
    let t0 = Date()
    await ptt.forceOff()
    #expect(Date().timeIntervalSince(t0) < 3)
}
