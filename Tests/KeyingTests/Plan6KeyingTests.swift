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
    // při PTT přes RTS se CAT odesílá asynchronně (bez čekání) – počkat, až dorazí
    for _ in 0..<50 where rig.ptt.last != false { try await Task.sleep(for: .milliseconds(10)) }
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
    #expect(Date().timeIntervalSince(t0) < 5)          // limit 2 s + rezerva na zatížený stroj
}

/// Při PTT přes RTS se na nedostupný CAT nečeká (jen se odešle).
@Test func forceOffWithRTSDoesNotWaitForCAT() async throws {
    final class SlowRig: Rig, @unchecked Sendable {
        var name: String { "slow" }
        func connect() async throws {}
        func disconnect() async {}
        func frequency() async throws -> Double { 0 }
        func setFrequency(_ hz: Double) async throws {}
        func mode() async throws -> String { "" }
        func setMode(_ mode: String) async throws {}
        func setPTT(_ on: Bool) async throws { try? await Task.sleep(for: .seconds(5)) }
    }
    let port = FakeSerialPort()
    let ptt = PTTController(method: .rts, port: port, rig: SlowRig())
    try await ptt.prepare()
    let t0 = Date()
    await ptt.forceOff()
    #expect(Date().timeIntervalSince(t0) < 0.5)
    #expect(port.events.contains(.rts(false)))
}

// Review (odloženo): při PTT přes RTS/DTR se pojistné CAT „RX“ pošle jen otevřenému rigu a počká se na něj
@Test func forceOffWithRTSOnlyTouchesActiveRig() async throws {
    final class IdleRig: Rig, @unchecked Sendable {
        var idle: Bool; var ptt: [Bool] = []
        init(idle: Bool) { self.idle = idle }
        var name: String { "idle" }
        var isIdle: Bool { idle }
        func connect() async throws {}
        func disconnect() async {}
        func frequency() async throws -> Double { 14e6 }
        func setFrequency(_ hz: Double) async throws {}
        func mode() async throws -> String { "USB" }
        func setMode(_ mode: String) async throws {}
        func setPTT(_ on: Bool) async throws { ptt.append(on) }
    }
    let idle = IdleRig(idle: true)
    await PTTController(method: .rts, port: FakeSerialPort(), rig: idle).forceOff()
    #expect(idle.ptt.isEmpty)                         // neotvírat port / nespouštět rigctld jen kvůli RX
    let active = IdleRig(idle: false)
    await PTTController(method: .rts, port: FakeSerialPort(), rig: active).forceOff()
    #expect(active.ptt == [false])                    // doběhlo před návratem (ne až po odpojení rigu)
}
