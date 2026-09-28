import Foundation
import Testing
import AudioIO
import Keying
import RigControl
import RTTYModem
import TestSupport
@testable import Engine

/// Rig, jehož PTT příkaz trvá 100 ms (odhalí souběh příkazů během await).
final class SlowRig: Rig, @unchecked Sendable {
    private let lock = NSLock()
    private var _ptt: [Bool] = []
    var ptt: [Bool] { lock.withLock { _ptt } }
    var name: String { "slow" }
    func connect() async throws {}
    func disconnect() async {}
    func frequency() async throws -> Double { 14e6 }
    func setFrequency(_ hz: Double) async throws {}
    func mode() async throws -> String { "USB" }
    func setMode(_ mode: String) async throws {}
    func setPTT(_ on: Bool) async throws {
        try await Task.sleep(for: .milliseconds(100))
        lock.withLock { _ptt.append(on) }
    }
}

func slowEngine() throws -> (Engine, SlowRig) {
    let rig = SlowRig()
    var cfg = EngineConfig(); cfg.ptt = .cat
    let e = Engine(modem: try RTTYModem(), rig: rig, audio: FakeAudioBackend(), config: cfg,
                   serialFactory: { _ in FakeSerialPort() }, clock: ManualClock(), autoRun: false)
    return (e, rig)
}

@Test func stopDuringTxStartLeavesPTTOff() async throws {
    let (e, rig) = try slowEngine()
    try await e.start()
    let t = Task { try? await e.tx() }
    try await Task.sleep(for: .milliseconds(30))
    await e.stop()
    await t.value
    try await Task.sleep(for: .milliseconds(250))
    #expect(await e.state == .stopped)
    #expect(rig.ptt.last == false, "PTT log \(rig.ptt)")
}

@Test func rxNowDuringTxStartAborts() async throws {
    let (e, rig) = try slowEngine()
    try await e.start()
    let t = Task { try? await e.tx() }
    try await Task.sleep(for: .milliseconds(30))
    await e.rxNow()
    await t.value
    try await Task.sleep(for: .milliseconds(250))
    #expect(await e.state == .rx)
    #expect(rig.ptt.last == false, "PTT log \(rig.ptt)")
    await e.stop()
}

@Test func concurrentTxKeysOnlyOnce() async throws {
    let (e, rig) = try slowEngine()
    try await e.start()
    async let a: Void? = try? e.tx()
    async let b: Void? = try? e.tx()
    _ = await (a, b)
    #expect(rig.ptt.filter { $0 }.count == 1, "PTT log \(rig.ptt)")
    await e.stop()
}

@Test func startAfterStopIsRejected() async throws {
    let (e, _) = try slowEngine()
    try await e.start()
    await e.stop()
    await #expect(throws: EngineError.notRunning) { try await e.start() }
}
