import Foundation
import Testing
import AudioIO
import Engine
import Keying
import ModemKit
import QSOLog
import RigControl
import RTTYModem
import RTTYSignalKit
import Settings
import TestSupport
@testable import AppCore

final class FakeRig2: Rig, @unchecked Sendable {
    var freq = 14_083_000.0
    var name: String { "fake" }
    func connect() async throws {}
    func disconnect() async {}
    func frequency() async throws -> Double { freq }
    func setFrequency(_ hz: Double) async throws { freq = hz }
    func mode() async throws -> String { "USB" }
    func setMode(_ mode: String) async throws {}
    func setPTT(_ on: Bool) async throws {}
}

struct Harness {
    let app: AppController
    let engine: Engine
    let audio: FakeAudioBackend
    let clock: ManualClock
    let rig: FakeRig2
    let dir: URL
}

func makeApp(ptt: PTTMethod = .cat) throws -> Harness {
    var s = AppSettings()
    s.station.call = "OK1XOE"
    s.ptt.method = ptt
    let audio = FakeAudioBackend(), clock = ManualClock(), rig = FakeRig2()
    let engine = Engine(modem: try RTTYModem(), rig: rig, audio: audio, config: s.engineConfig(),
                        serialFactory: { _ in FakeSerialPort() }, clock: clock, autoRun: false)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("app-\(UUID())")
    let log = try QSOLogStore(directory: dir)
    let app = AppController(settings: s, engine: engine, log: log, profiles: ProfileStore(directory: dir))
    return Harness(app: app, engine: engine, audio: audio, clock: clock, rig: rig, dir: dir)
}

func run(_ h: Harness, until: () async -> Bool) async {
    for _ in 0..<2000 {
        if await until() { return }
        h.clock.advance(ms: 50)
        await h.engine.pump()
    }
}

@Test func macroUsesStationCall() async throws {
    let h = try makeApp()
    try await h.app.start()
    try await h.app.runMacro(index: 0)              // CQ
    await run(h) { await h.engine.state == .rx && h.audio.writeCalls > 0 }
    let m = try RTTYModem(); let ev = m.events
    (h.audio.tx + [Float](repeating: 0, count: 4000)).withUnsafeBufferPointer { m.processRx($0) }
    m.finishEvents()
    var t = ""; for await e in ev { if case .rxText(let c, false) = e { t.append(c) } }
    #expect(t.contains("CQ CQ CQ DE OK1XOE OK1XOE OK1XOE PSE K"))
    await h.app.stop()
}

@Test func logQSOUsesFieldsAndRigFrequency() async throws {
    let h = try makeApp()
    try await h.app.start()
    await h.engine.pollRig()
    try await h.app.setQSOField("call", "dl1abc")
    try await h.app.setQSOField("name", "HANS")
    try await h.app.setQSOField("rstRcvd", "579")
    let events = h.app.events()
    let r = try await h.app.logQSO()
    #expect(r.call == "DL1ABC" && r.name == "HANS" && r.rstRcvd == "579")
    #expect(r.frequency == 14_083_000 && r.mode == "RTTY" && r.stationCallsign == "OK1XOE")
    await #expect(throws: AppError.self) { try await h.app.setQSOField("nope", "x") }
    await h.app.stop()
    var logged = false
    for await e in events { if case .qsoLogged = e { logged = true } }
    #expect(logged)
}

@Test func macroLogMarkerLogsQSO() async throws {
    let h = try makeApp()
    try await h.app.start()
    try await h.app.setQSOField("call", "W1AW")
    try await h.app.runMacro(index: 4)              // TU … %l
    await run(h) { await h.engine.state == .rx && h.audio.writeCalls > 0 }
    try await Task.sleep(for: .milliseconds(100))
    let all = await h.app.log?.records ?? []
    #expect(all.map(\.call) == ["W1AW"])
    await h.app.stop()
}

@Test func rxTextHistoryCollectsReceivedText() async throws {
    let h = try makeApp(ptt: .none)
    try await h.app.start()
    h.audio.feedRx(RTTYSignalGenerator().generate(text: "HELLO WORLD"))
    await run(h) { h.audio.rxRemaining == 0 }
    try await Task.sleep(for: .milliseconds(100))
    #expect(h.app.rxText.range(start: 0, length: 1000).contains("HELLO WORLD"))
    var cur = 0
    #expect(h.app.rxText.takeNew(cursor: &cur).contains("HELLO"))
    #expect(h.app.rxText.takeNew(cursor: &cur).isEmpty)
    await h.app.stop()
}

@Test func textHistoryTrimsButKeepsAbsoluteIndices() {
    let t = TextHistory(limit: 10)
    t.append("0123456789"); t.append("ABCDE")
    #expect(t.totalLength == 15)
    #expect(t.range(start: 10, length: 5) == "ABCDE")
    #expect(t.range(start: 0, length: 5) == "")          // truncated
    #expect(t.range(start: 5, length: 10) == "56789ABCDE")
}

@Test func modemParamsAndProfiles() async throws {
    let h = try makeApp()
    try await h.app.start()
    try await h.app.setModemParam("baud", .double(75))
    #expect(await h.app.modemParam("baud") == .double(75))
    await #expect(throws: (any Error).self) { try await h.app.setModemParam("baud", .double(9999)) }
    try await h.app.saveProfile(2, name: "75 Bd")
    try await h.app.setModemParam("baud", .double(45.45))
    try await h.app.loadProfile(2)
    #expect(await h.app.modemParam("baud") == .double(75))
    await h.app.stop()
}

/// A macro with repeat (the CQ loop) keeps repeating until stopMacroRepeat stops it.
@Test func macroRepeatRunsUntilStopped() async throws {
    let h = try makeApp()
    var macros = AppSettings.defaultMacros
    macros[0] = Macro(name: "CQ", text: "CQ DE %m K\\", repeatSeconds: 0.3)
    await h.app.setMacros(macros)
    try await h.app.start()
    try await h.app.runMacro(index: 0)
    var transmissions = 0, wasTx = false
    let end = Date().addingTimeInterval(4)
    while Date() < end && transmissions < 3 {
        h.clock.advance(ms: 50)
        await h.engine.pump()
        let tx = await h.engine.state != .rx
        if tx && !wasTx { transmissions += 1 }
        wasTx = tx
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(transmissions >= 3)
    await h.app.stopMacroRepeat()
    await h.app.rxNow()
    for _ in 0..<40 { h.clock.advance(ms: 50); await h.engine.pump(); try await Task.sleep(for: .milliseconds(20)) }
    #expect(await h.engine.state == .rx)
    await h.app.stop()
}
