import Foundation
import Testing
import AppCore
import DXCC
import Engine
import QSOLog
import RigControl
import RTTYModem
import Settings
import Spots
import TestSupport
@testable import AppUI

// Kontrola plánu 17

private let roundup = ContestSettings.preset(.arrlRoundup, year: 2027)

// MARK: 1 – ARRL RU: stát/provincie je přijatá výměna

@Test func esmRoundupStateCompletesExchange() {
    var w = QSOFields(); w.call = "W1AW"; w.exchangeRcvd = "CT"
    #expect(ESM.received(w, roundup) == .complete)
    #expect(ESM.step(mode: .run, contest: roundup, qso: w, progress: .init(call: "W1AW", exchangeSent: true),
                     transmitting: false) == .tu)
    #expect(ESM.step(mode: .sp, contest: roundup, qso: w, progress: .init(call: "W1AW", myCallSent: true),
                     transmitting: false) == .exchangeAndLog)
    var dx = QSOFields(); dx.call = "DL1ABC"; dx.serialRcvd = 12
    #expect(ESM.received(dx, roundup) == .complete)
    var none = QSOFields(); none.call = "DL1ABC"
    #expect(ESM.received(none, roundup) == .none)
    #expect(ESM.step(mode: .run, contest: roundup, qso: none, progress: .init(call: "DL1ABC", exchangeSent: true),
                     transmitting: false) == .exchange)
}

@Test @MainActor func roundupClickOnStateFillsExchange() async throws {
    let f = Fixture()
    f.configure = { $0.contest = roundup }
    await f.model.start()
    await f.model.setQSOField("call", "W1AW")
    await f.model.insertWord("CT")
    #expect(f.model.qso.exchangeRcvd == "CT")
    await f.model.insertWord("ON")                                       // provincie (i když je to i běžná zkratka)
    #expect(f.model.qso.exchangeRcvd == "ON")
    await f.model.insertWord("599015")                                   // číslo dál jde do čísla
    #expect(f.model.qso.serialRcvd == 15)
    await f.model.insertWord("XX")                                       // není stát → nic
    #expect(f.model.qso.exchangeRcvd == "ON")
    await f.model.stop()
}

// MARK: 3 + minor 5 – engine zastavený ≠ vysílání

@Test @MainActor func stoppedEngineIsNotReportedAsTransmitting() async throws {
    let dir = tempDir()
    var s = AppSettings()
    s.station.call = "OK1XOE"; s.log.directory = dir.appendingPathComponent("log").path
    s.api.fldigiPort = 0; s.api.jsonRPCPort = 0; s.rig.type = .flrig
    try? SettingsStore(directory: dir).save(s)
    let audio = FakeAudioBackend(); audio.failStart = true
    let rig = SpotFakeRig(), clock = ManualClock()
    let m = AppModel(settingsStore: SettingsStore(directory: dir), profileStore: ProfileStore(directory: dir),
                     engineFactory: { settings, _ in
                         Engine(modem: try! RTTYModem(config: settings.modemConfig()), rig: rig, audio: audio,
                                config: settings.engineConfig(), serialFactory: { _ in FakeSerialPort() }, clock: clock, autoRun: false)
                     }, spectrumFPS: 0)
    await m.start()
    try #require(m.state == .stopped)
    let r = await m.setFrequency(kHz: 14080)
    #expect(r != .rejectedTX)
    #expect(!m.messages.contains { $0.contains("Během vysílání") })
    #expect(rig.freqs.isEmpty)
    await m.stop()
}

// MARK: 5 – falešná „potřebná“ ze šumu

@MainActor private func alertFixture(watch: String = "") -> (Fixture, RecordingSink) {
    let f = Fixture()
    f.configure = { $0.alerts.newCountryAny = true; $0.alerts.watchCalls = watch }
    let sink = RecordingSink()
    f.model.alertSink = sink
    return (f, sink)
}

@Test @MainActor func rxNoiseCallDoesNotAlertNewCountry() async throws {
    let (f, _) = alertFixture()
    await f.model.start()
    f.model.appendRx("RYRY 5R8ZQ EEE TTT ", echo: false)                 // jednorázová „značka“ ve šumu
    #expect(!f.model.messages.contains { $0.contains("5R8ZQ") })
    await f.model.stop()
}

@Test @MainActor func rxRepeatedOrAfterDECallAlerts() async throws {
    let (f, _) = alertFixture()
    await f.model.start()
    f.model.appendRx("CQ TEST DE 3B8ZZ ", echo: false)                   // po DE
    #expect(f.model.messages.contains { $0.contains("3B8ZZ") })
    f.model.appendRx("VU2QQQ RYRY ", echo: false)
    #expect(!f.model.messages.contains { $0.contains("VU2QQQ") })
    f.model.appendRx("TU VU2QQQ ", echo: false)                          // podruhé do 10 min
    #expect(f.model.messages.contains { $0.contains("VU2QQQ") })
    await f.model.stop()
}

// MARK: 8 – dávka spotů = souhrnný řádek

final class TestClock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 5000) }

@MainActor private func spotAlertModel(_ clock: TestClock) -> (AppModel, RecordingSink) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p17alert-\(UUID().uuidString)")
    let store = SettingsStore(directory: dir)
    var s = AppSettings(); s.station.call = "OK1XOE"
    s.alerts.watchCalls = (0..<11).map { "DL\($0)ABC" }.joined(separator: " ")
    try? store.save(s)
    let sink = RecordingSink()
    let m = AppModel(settingsStore: store, profileStore: ProfileStore(directory: dir), alertSink: sink, alertClock: { clock.now })
    return (m, sink)
}

@Test @MainActor func spotBatchWritesOneSummaryLine() {
    let clock = TestClock()
    let (m, sink) = spotAlertModel(clock)
    for i in 0..<10 {
        m.checkSpotNeeded(Spot(frequencyKHz: 14085, call: "DL\(i)ABC", spotter: "X", comment: "", time: clock.now, mode: "RTTY"))
    }
    #expect(m.messages.filter { $0.contains("Potřebné") }.count == 1)
    #expect(sink.sounds == 1)
    m.flushNeededSummary()                                               // po 5 s: jeden souhrnný řádek
    let lines = m.messages.filter { $0.contains("Potřebné") }
    #expect(lines.count == 2)
    #expect(lines.last?.contains("9") == true && lines.last?.contains("DL1ABC") == true)
    // po uplynutí intervalu jde další spot zase hned
    clock.now = clock.now.addingTimeInterval(10)
    m.checkSpotNeeded(Spot(frequencyKHz: 14085, call: "DL10ABC", spotter: "X", comment: "", time: clock.now, mode: "RTTY", source: .rbn))
    #expect(m.messages.filter { $0.contains("Potřebné") }.count == 3)
}

// MARK: 7 – násobiče průběžně

@Test @MainActor func loggedQSOAddsMultipliersIncrementally() async throws {
    let f = Fixture()
    f.configure = { s in
        s.contest = ContestSettings.preset(.cqwwRTTY, year: 2026)
        s.contest.start = Date().addingTimeInterval(-3600)
    }
    await f.model.start()
    try #require(f.model.multipliers != nil)
    let before = f.model.multiplierFullRecomputes
    for (call, x) in [("DL1ABC", "14"), ("W1AW", "5 CT"), ("JA1XYZ", "25")] {
        await f.model.setQSOField("call", call)
        await f.model.setQSOField("freq", "14085")
        await f.model.setQSOField("exchangeRcvd", x)
        await f.model.logQSO()
        for _ in 0..<100 where !f.model.logRecords.contains(where: { $0.call == call }) { await f.settle() }
    }
    #expect(f.model.logRecords.count == 3)
    #expect(f.model.multiplierFullRecomputes == before)                   // žádný úplný přepočet
    let calc = MultiplierCalculator(rule: try #require(f.model.multiplierRule), countries: CountryDB.shared)
    let full = calc.tally(records: f.model.logRecords, since: f.model.settings.contest.effectiveStart)
    #expect(f.model.multipliers == full)
    #expect(full.total > 0)
    await f.model.stop()
}

// MARK: 4 – stav spotů v band mapě přes index logu

@Test func spotStatusFastWithLargeLog() {
    let now = Date()
    let recs = (0..<10_000).map { i -> QSORecord in
        var r = QSORecord(call: "K\(i)AB", timeOn: now.addingTimeInterval(-Double(i)), mode: "RTTY")
        r.frequency = 14_080_000; return r
    }
    let spots = (0..<50).map { i in
        Spot(frequencyKHz: 14080 + Double(i) * 0.1, call: i % 2 == 0 ? "K\(i * 100)AB" : "DL\(i)NEW", spotter: "X", comment: "",
             time: now, mode: "RTTY")
    }
    let since = now.addingTimeInterval(-86400)
    let index = LogIndex(records: recs, contestSince: since, country: { _ in nil })   // v AppModel udržovaný průběžně
    let t0 = Date()
    let st = spots.map { AppModel.spotStatus($0, index: index, contest: true) }
    let ms = Date().timeIntervalSince(t0) * 1000
    #expect(st.filter { $0 == .dupe }.count == 25)
    #expect(st.filter { $0 == .new }.count == 25)
    #expect(ms < 50, "\(ms) ms")
    // stejný výsledek jako úplná kontrola duplicit
    for (s, got) in zip(spots, st) {
        let dupe = DupeCheck.isDupe(call: s.call, band: s.band, mode: s.mode ?? "RTTY", records: recs, since: since)
        #expect((got == .dupe) == dupe)
    }
}

@Test @MainActor func bandMapStatusFollowsModelLogIndex() async throws {
    let f = Fixture()
    f.configure = { $0.contest.enabled = true; $0.contest.start = Date().addingTimeInterval(-3600) }
    await f.model.start()
    let s = Spot(frequencyKHz: 14085, call: "DL1ABC", spotter: "X", comment: "", time: Date(), mode: "RTTY")
    #expect(f.model.spotStatus(s) == .new)
    await f.model.setQSOField("call", "DL1ABC")
    await f.model.setQSOField("freq", "14085")
    await f.model.logQSO()
    for _ in 0..<100 where f.model.logRecords.isEmpty { await f.settle() }
    #expect(f.model.spotStatus(s) == .dupe)
    #expect(f.model.spotLogIndex.status(of: s) == .workedOnBand)
    await f.model.stop()
}

// MARK: 1 – klik na stát v RU (čistá funkce)

@Test func contestUpdateRoundupStates() {
    var q = QSOFields(); q.call = "W1AW"
    func f(_ w: String, _ ru: Bool = true) -> [String] {
        WordClassifier.contestUpdate(w, format: .serial, serialMode: true, roundup: ru, current: q).map { "\($0.0)=\($0.1)" }
    }
    #expect(f("CT") == ["exchangeRcvd=CT"])
    #expect(f("ct,") == ["exchangeRcvd=CT"])
    #expect(f("DC") == ["exchangeRcvd=DC"])
    #expect(f("OK") == ["exchangeRcvd=OK"])                               // Oklahoma, i když je to stop slovo
    #expect(f("QC") == ["exchangeRcvd=QC"] && f("PEI") == ["exchangeRcvd=PE"])
    #expect(f("599015") == ["serialRcvd=15"])
    #expect(f("HI").isEmpty && f("AK").isEmpty && f("XX").isEmpty)       // KH6/KL7 nejsou státy RU (země DXCC)
    #expect(f("CT", false).isEmpty)                                       // mimo RU se text nebere
}

// MARK: 10 – zoom trackpadem po krocích

@Test func scrollZoomAccumulatesTrackpadSteps() {
    var a = ScrollZoomAccumulator()
    // trackpad: 1 krok na 20 bodů
    #expect(a.feed(deltaY: 5, precise: true, momentum: false) == 0)
    #expect(a.feed(deltaY: 10, precise: true, momentum: false) == 0)
    #expect(a.feed(deltaY: 10, precise: true, momentum: false) == 1)
    #expect(a.feed(deltaY: 45, precise: true, momentum: false) == 2)
    // setrvačnost se ignoruje
    #expect(a.feed(deltaY: 200, precise: true, momentum: true) == 0)
    // změna směru začíná znovu
    #expect(a.feed(deltaY: -15, precise: true, momentum: false) == 0)
    #expect(a.feed(deltaY: -30, precise: true, momentum: false) == -2)
    a.reset()
    #expect(a.accumulated == 0)
    // kolečko myši: krok za událost
    #expect(a.feed(deltaY: 1, precise: false, momentum: false) == 1)
    #expect(a.feed(deltaY: -3, precise: false, momentum: false) == -1)
    #expect(a.feed(deltaY: .nan, precise: true, momentum: false) == 0)
    #expect(a.feed(deltaY: 0, precise: false, momentum: false) == 0)
}

// MARK: 5 – pomocné struktury

@Test func rxCallSightingsWindowAndBound() {
    var s = RxCallSightings(maxKeys: 5)
    let t0 = Date(timeIntervalSince1970: 1000)
    #expect(s.record("DL1ABC", now: t0) == 1)
    #expect(s.record("DL1ABC", now: t0.addingTimeInterval(599)) == 2)
    #expect(s.record("DL1ABC", now: t0.addingTimeInterval(1300)) == 1)     // mimo 10 min
    for i in 0..<50 { _ = s.record("K\(i)AB", now: t0.addingTimeInterval(1300)) }
    #expect(s.count <= 5)
}

@Test func superCheckExactContains() {
    let scp = SuperCheck(calls: ["DL1ABC", "OK1XOE", "W1AW", "3B8ZZ"])
    #expect(scp.contains("DL1ABC") && scp.contains("ok1xoe") && scp.contains("3B8ZZ") && scp.contains("W1AW"))
    #expect(!scp.contains("DL1AB") && !scp.contains("DL1ABCD") && !scp.contains("") && !scp.contains("A"))
    #expect(!SuperCheck(calls: []).contains("W1AW"))
}

@Test @MainActor func rxWatchedCallAlertsImmediatelyAndSCPConfirms() async throws {
    let (f, _) = alertFixture(watch: "5R8QQ")
    try "5H3XY\n".write(to: f.dir.appendingPathComponent("MASTER.SCP"), atomically: true, encoding: .utf8)
    await f.model.start()
    f.model.appendRx("RYRY 5R8QQ RYRY ", echo: false)                   // hlídaná: hned
    #expect(f.model.messages.contains { $0.contains("5R8QQ") })
    f.model.appendRx("RYRY 5H3XY RYRY ", echo: false)                   // zná ji Super Check Partial
    #expect(f.model.messages.contains { $0.contains("5H3XY") })
    await f.model.stop()
}
