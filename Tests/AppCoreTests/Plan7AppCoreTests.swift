import Foundation
import Testing
import ModemKit
import DXCC
import MacroEngine
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
    #expect(await h.app.macroContext().hisRST == "599007")
    try await h.app.setQSOField("call", "DL1ABC")
    try await h.app.setQSOField("serialRcvd", "15")
    #expect(await h.app.macroContext().myRST == "599015")
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
    #expect(await h.app.macroContext().hisRST == "59914")
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

let ctyFixture = """
Fed. Rep. of Germany:     14:  28:  EU:   51.00:   -10.00:    -1.0:  DL:
    DA,DB,DC,DD,DE,DF,DG,DH,DI,DJ,DK,DL,DM,DN,DO,DP,DQ,DR;
Japan:                    25:  45:  AS:   36.40:  -138.38:    -9.0:  JA:
    JA,JE,JF,JG,JH,JI,JJ,JK,JL,JM,JN,JO,JP,JQ,JR,JS;
"""

func makeDXCCApp() throws -> Harness {
    let h = try makeApp()
    var s = AppSettings(); s.station.call = "OK1XOE"; s.ptt.method = .cat
    let app = AppController(settings: s, engine: h.engine, log: h.app.log, profiles: nil,
                            countries: try CountryDB(text: ctyFixture))
    return Harness(app: app, engine: h.engine, audio: h.audio, clock: h.clock, rig: h.rig, dir: h.dir)
}

@Test func macroContextAndLogUseDXCC() async throws {
    let h = try makeDXCCApp()
    try await h.app.setQSOField("call", "JA1XYZ")
    #expect(await h.app.macroContext().hisUTCOffsetHours == 9)
    #expect(await h.app.country(for: "DL1ABC/P")?.name == "Fed. Rep. of Germany")
    let r = try await h.app.logQSO()
    #expect(r.country == "Japan" && r.continent == "AS" && r.cqZone == 25 && r.ituZone == 45)
    try await h.app.setQSOField("call", "ZZ9ZZ")
    #expect(await h.app.macroContext().hisUTCOffsetHours == nil)
}

@Test func sixteenMacrosRunnable() async throws {
    let h = try makeApp()
    try await h.app.start()
    #expect(await h.app.settings.macros.count == 16)
    try await h.app.runMacro(index: 13)                   // Test CQ (⇧F2)
    await #expect(throws: AppError.badMacro(16)) { try await h.app.runMacro(index: 16) }
    await h.app.rxNow()
    await h.app.stop()
}

// Review I-4: MMTTY HisRST = report, který posílám (%r %R %N), MyRST = přijatý (%s %M)
@Test func macroRSTVariablesFollowMMTTY() async throws {
    let h = try makeApp()
    try await h.app.setQSOField("call", "DL1ABC")
    try await h.app.setQSOField("rstSent", "579")
    try await h.app.setQSOField("serialSent", "7")
    try await h.app.setQSOField("rstRcvd", "559")
    try await h.app.setQSOField("serialRcvd", "15")
    let r = MacroEngine.expand("%r %R %N|%s %M", context: await h.app.macroContext())
    let t = r.outputs.compactMap { if case .text(let s) = $0 { return s } else { return nil } }.joined()
    #expect(t == "579007 579 007|559015 015")
}

// Review I-6: export jen závodních spojení (s odeslaným číslem nebo výměnou) v rozsahu
@Test func cabrilloContestOnlyAndRange() async throws {
    let h = try makeApp()
    try await h.app.setQSOField("call", "OK2AAA")
    _ = try await h.app.logQSO()                          // běžné spojení bez výměny
    try await h.app.setQSOField("call", "DL1ABC")
    try await h.app.setQSOField("serialSent", "1")
    _ = try await h.app.logQSO()
    let all = await h.app.cabrillo()
    #expect(all.contains("OK2AAA") && all.contains("DL1ABC"))
    let contest = await h.app.cabrillo(contestOnly: true)
    #expect(!contest.contains("OK2AAA") && contest.contains("DL1ABC"))
    let future = await h.app.cabrillo(from: Date().addingTimeInterval(3600))
    #expect(!future.contains("DL1ABC"))
}

// Review minor: MMTTY ignoruje kliky do spektra během TX
@Test func notchClickIgnoredDuringTx() async throws {
    let h = try makeApp(ptt: .none)
    try await h.app.start()
    try await h.app.tx()
    await run(h) { await h.engine.state == .tx }
    await h.app.notchClick(hz: 1650)
    #expect(await h.app.modemParam("notchFreq") != .int(1650))
    await h.app.rxNow()
    await h.app.stop()
}
