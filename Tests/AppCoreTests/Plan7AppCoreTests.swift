import Foundation
import Testing
import ModemKit
import Engine
import QSOLog
import RTTYModem
import Settings
import TestSupport
@testable import AppCore

@Test func notchClickSetsNotchAndBroadcastsParams() async throws {
    let h = try makeApp()
    let events = h.app.events()
    await h.app.notchClick(hz: 1650)
    #expect(await h.app.modemParam("notchFreq") == .int(1650))
    #expect(await h.app.modemParam("lms") == .bool(true))
    for await e in events {
        if case .paramsChanged(let p) = e { #expect(p["notchFreq"] == .int(1650)); break }
    }
}

func makeContestApp(exchange: String = "", next: Int = 7) throws -> Harness {
    var s = AppSettings()
    s.station.call = "OK1XOE"; s.ptt.method = .cat
    s.contest.enabled = true; s.contest.nextSerial = next; s.contest.exchange = exchange; s.contest.name = "TEST"
    let audio = FakeAudioBackend(), clock = ManualClock(), rig = FakeRig2()
    let engine = Engine(modem: try RTTYModem(), rig: rig, audio: audio, config: s.engineConfig(),
                        serialFactory: { _ in FakeSerialPort() }, clock: clock, autoRun: false)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("app-\(UUID())")
    let app = AppController(settings: s, engine: engine, log: try QSOLogStore(directory: dir), profiles: nil)
    return Harness(app: app, engine: engine, audio: audio, clock: clock, rig: rig, dir: dir)
}

@Test func contestSerialAssignedAndIncrementedOnLog() async throws {
    let h = try makeContestApp()
    await h.app.clearQSO()
    #expect(await h.app.qso.serialSent == 7)
    #expect(await h.app.macroContext().rstSent == "599007")
    try await h.app.setQSOField("call", "DL1ABC")
    try await h.app.setQSOField("serialRcvd", "15")
    #expect(await h.app.macroContext().rstRcvd == "599015")
    let events = h.app.events()
    let r = try await h.app.logQSO()
    #expect(r.serialSent == 7 && r.serialRcvd == 15)
    #expect(await h.app.settings.contest.nextSerial == 8)
    let after = await h.app.qso
    #expect(after.call == "" && after.serialSent == 8)                       // v závodě se QSO po zalogování vyčistí
    var saw = false
    for await e in events { if case .contestSerial(let n) = e { saw = n == 8; break } }
    #expect(saw)
}

@Test func contestExchangeModeUsesExchangeText() async throws {
    let h = try makeContestApp(exchange: "14")
    await h.app.clearQSO()
    let q = await h.app.qso
    #expect(q.serialSent == nil && q.exchangeSent == "14")
    #expect(await h.app.macroContext().rstSent == "59914")
    try await h.app.setQSOField("call", "DL1ABC")
    _ = try await h.app.logQSO()
    #expect(await h.app.settings.contest.nextSerial == 7)                  // bez čísel se nemění
}

@Test func nonContestLogKeepsQSOAndSerial() async throws {
    let h = try makeApp()
    try await h.app.setQSOField("call", "DL1ABC")
    _ = try await h.app.logQSO()
    #expect(await h.app.qso.call == "DL1ABC")
    #expect(await h.app.qso.serialSent == nil)
}
