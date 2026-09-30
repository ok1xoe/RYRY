import Foundation
import Testing
import RigControl
import TestSupport
@testable import Keying

/// forceOff also tries to turn PTT off over CAT when a rig is available (even when the PTT method is RTS).
@Test func forceOffAlsoTriesCATWhenRigAvailable() async throws {
    let rig = RecordingRig()
    let ptt = PTTController(method: .rts, port: FakeSerialPort(), rig: rig)
    try await ptt.prepare()
    await ptt.forceOff()
    // with PTT over RTS the CAT command is sent asynchronously (without waiting) – wait for it to arrive
    for _ in 0..<50 where rig.ptt.last != false { try await Task.sleep(for: .milliseconds(10)) }
    #expect(rig.ptt.last == false)
}

/// forceOff with a rig that never answers finishes within ~2 s.
@Test func forceOffWithHangingRigReturns() async throws {
    final class HangRig: Rig, @unchecked Sendable {
        var name: String { "hang" }
        func connect() async throws {}
        func disconnect() async {}
        func frequency() async throws -> Double { 0 }
        func setFrequency(_ hz: Double) async throws {}
        func mode() async throws -> String { "" }
        func setMode(_ mode: String) async throws {}
        func setPTT(_ on: Bool) async throws { try? await Task.sleep(for: .seconds(30)) }   // ignores cancellation
    }
    let ptt = PTTController(method: .cat, port: nil, rig: HangRig())
    let t0 = Date()
    await ptt.forceOff()
    #expect(Date().timeIntervalSince(t0) < 5)          // the 2 s limit plus a margin for a loaded machine
}

/// With PTT over RTS an unreachable CAT is not waited for (the command is only sent).
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

// Review (deferred): with PTT over RTS/DTR the safety CAT "RX" is sent only to an open rig, and it is waited for
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
    #expect(idle.ptt.isEmpty)                         // do not open the port / start rigctld just for RX
    let active = IdleRig(idle: false)
    await PTTController(method: .rts, port: FakeSerialPort(), rig: active).forceOff()
    for _ in 0..<50 where active.ptt.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(active.ptt == [false])                    // in the background, without waiting
}
