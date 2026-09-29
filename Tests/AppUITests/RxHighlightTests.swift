import Foundation
import Testing
import AppCore
import Engine
import QSOLog
import RigControl
import Settings
import Spots
import TestSupport
@testable import AppUI

private func rec(_ call: String, band: String? = "20m", mode: String = "RTTY", at t: Date = Date()) -> QSORecord {
    var r = QSORecord(call: call, timeOn: t, mode: mode)
    r.frequency = ["20m": 14_085_000.0, "40m": 7_045_000.0][band ?? ""]; return r
}
/// Země podle prvních dvou písmen značky (jen pro test): DL → Germany, OK → Czech Republic, W1 → USA.
private func country(_ call: String) -> CountryRef? {
    if call.hasPrefix("DL") { return CountryRef(key: "DL", name: "Germany") }
    if call.hasPrefix("OK") { return CountryRef(key: "OK", name: "Czech Republic") }
    if call.hasPrefix("W") { return CountryRef(key: "K", name: "USA") }
    return nil
}

@Suite struct CallHighlightTests {
    let now = Date()
    func index(_ rs: [QSORecord], since: Date? = nil) -> LogIndex { LogIndex(records: rs, contestSince: since, country: country) }

    @Test func ownCallIsRedAndBaseCallMatches() {
        let i = index([])
        #expect(CallHighlight.style(word: "OK1XOE", myBase: "OK1XOE", band: "20m", mode: "RTTY", contest: false, index: i) == .own)
        #expect(CallHighlight.style(word: "OK1XOE/P", myBase: "OK1XOE", band: "20m", mode: "RTTY", contest: false, index: i) == .own)
        #expect(CallHighlight.style(word: "ok1xoe,", myBase: "OK1XOE", band: nil, mode: "RTTY", contest: false, index: i) == .own)
    }
    @Test func newWorkedDupe() {
        let i = index([rec("DL1ABC", at: now)], since: now.addingTimeInterval(-60))
        // nová
        #expect(CallHighlight.style(word: "OK2XYZ", myBase: "OK1XOE", band: "20m", mode: "RTTY", contest: true, index: i) == .new)
        // v logu, bez závodu → modře
        #expect(CallHighlight.style(word: "DL1ABC", myBase: "OK1XOE", band: "20m", mode: "RTTY", contest: false, index: LogIndex(records: [rec("DL1ABC")], contestSince: nil, country: country)) == .worked)
        // v závodě stejné pásmo a mód → dupe
        #expect(CallHighlight.style(word: "DL1ABC", myBase: "OK1XOE", band: "20m", mode: "RTTY", contest: true, index: i) == .dupe)
        // jiné pásmo → není dupe, ale v logu
        #expect(CallHighlight.style(word: "DL1ABC", myBase: "OK1XOE", band: "40m", mode: "RTTY", contest: true, index: i) == .worked)
        // neznámé pásmo → jen značka a mód
        #expect(CallHighlight.style(word: "DL1ABC/P", myBase: "OK1XOE", band: nil, mode: "RTTY", contest: true, index: i) == .dupe)
    }
    @Test func dupeMatchesDupeCheck() {
        let recs = [rec("DL1ABC", at: now), rec("W1AW", band: nil, at: now), rec("OK2ZZ", at: now.addingTimeInterval(-3600))]
        let since = now.addingTimeInterval(-60)
        let i = index(recs, since: since)
        for (call, band) in [("DL1ABC", "20m"), ("DL1ABC", "40m"), ("DL1ABC", nil), ("W1AW", "20m"), ("W1AW", nil), ("OK2ZZ", "20m")] as [(String, String?)] {
            #expect(i.isDupe(call: call, band: band, mode: "RTTY") == DupeCheck.isDupe(call: call, band: band, mode: "RTTY", records: recs, since: since),
                    "\(call) \(band ?? "-")")
        }
        #expect(!i.isDupe(call: "DL1ABC", band: "20m", mode: "CW"))
    }
    @Test func nonCallWordsAreNotStyled() {
        let i = index([])
        for w in ["CQ", "DE", "599", "THE", "NAME", "K", "PSE"] {
            #expect(CallHighlight.style(word: w, myBase: "OK1XOE", band: nil, mode: "RTTY", contest: false, index: i) == nil, "\(w)")
        }
    }
    @Test func indexAddsIncrementally() {
        var i = index([])
        #expect(!i.worked("DL1ABC"))
        i.add(rec("DL1ABC/P"), contestSince: nil, country: country)
        #expect(i.worked("DL1ABC"))
        #expect(i.countryWorked("DL", band: "20m"))
        #expect(!i.countryWorked("DL", band: "40m"))
        #expect(i.countryWorked("DL", band: nil))
    }
    @Test func wordRangesAndRestyleStart() {
        let t = "CQ CQ DE OK1X" as NSString
        let r = CallHighlight.wordRanges(in: t, range: NSRange(location: 0, length: t.length)).map { t.substring(with: $0) }
        #expect(r == ["CQ", "CQ", "DE", "OK1X"])
        // nové písmeno se přidalo za neúplné slovo → přestylovat od jeho začátku
        #expect(CallHighlight.restyleStart(in: t, appendedAt: 12) == 9)
        // přidání začalo za mezerou → od místa přidání
        #expect(CallHighlight.restyleStart(in: "CQ CQ " as NSString, appendedAt: 6) == 6)
        #expect(CallHighlight.restyleStart(in: "" as NSString, appendedAt: 0) == 0)
    }
}

@Suite struct NeededCheckTests {
    func index(_ rs: [QSORecord]) -> LogIndex { LogIndex(records: rs, contestSince: nil, country: country) }
    func settings(watch: String = "", band: Bool = false, any: Bool = false) -> AlertSettings {
        var s = AlertSettings(); s.watchCalls = watch; s.newCountryBand = band; s.newCountryAny = any; return s
    }
    let de = CountryRef(key: "DL", name: "Germany")

    @Test func newCountryOnBandVsAny() {
        let i = index([rec("DL1ABC", band: "20m")])
        // Německo na 20m už je; na 40m ne
        #expect(NeededCheck.check(call: "DL2XYZ", band: "20m", country: de, settings: settings(band: true, any: true), index: i).isEmpty)
        #expect(NeededCheck.check(call: "DL2XYZ", band: "40m", country: de, settings: settings(band: true, any: true), index: i)
            == [.newCountryBand(country: "Germany", band: "40m")])
        #expect(NeededCheck.check(call: "DL2XYZ", band: "40m", country: de, settings: settings(band: false, any: true), index: i).isEmpty)
        // země vůbec nová
        let us = CountryRef(key: "K", name: "USA")
        #expect(NeededCheck.check(call: "W1AW", band: "20m", country: us, settings: settings(band: true, any: true), index: i)
            == [.newCountry(country: "USA")])
        #expect(NeededCheck.check(call: "W1AW", band: "20m", country: us, settings: settings(band: true, any: false), index: i)
            == [.newCountryBand(country: "USA", band: "20m")])
    }
    @Test func unknownBandOrCountry() {
        let i = index([])
        #expect(NeededCheck.check(call: "DL2XYZ", band: nil, country: de, settings: settings(band: true), index: i).isEmpty)
        #expect(NeededCheck.check(call: "DL2XYZ", band: "20m", country: nil, settings: settings(band: true, any: true), index: i).isEmpty)
    }
    @Test func watchedCallByBaseCall() {
        let i = index([rec("DL1ABC")])
        let s = settings(watch: "dl1abc\nvk9xx, P5/DL2XX")
        #expect(NeededCheck.check(call: "DL1ABC/P", band: "20m", country: de, settings: s, index: i) == [.watched])
        #expect(NeededCheck.check(call: "VK9XX", band: nil, country: nil, settings: s, index: i) == [.watched])
        #expect(NeededCheck.check(call: "DL9ZZZ", band: "20m", country: de, settings: s, index: i).isEmpty)
    }
    @Test func watchParsing() {
        #expect(AlertSettings.parseWatch(" ok1abc \n\nDL1ABC/P;w1aw ,").sorted() == ["DL1ABC", "OK1ABC", "W1AW"])
    }
}

@Suite struct AlertThrottleTests {
    @Test func limitsRepeatsPerKey() {
        var t = AlertThrottle()
        let t0 = Date(timeIntervalSince1970: 1000)
        let r1 = t.allow("my", now: t0, interval: 20)
        let r2 = t.allow("my", now: t0.addingTimeInterval(19), interval: 20)
        let r3 = t.allow("other", now: t0.addingTimeInterval(1), interval: 20)
        let r4 = t.allow("my", now: t0.addingTimeInterval(20), interval: 20)
        let r5 = t.allow("my", now: t0.addingTimeInterval(30), interval: 20)
        #expect(r1 && !r2 && r3 && r4 && !r5)
    }
    @Test func doesNotGrowUnbounded() {
        var t = AlertThrottle(maxKeys: 10)
        for i in 0..<100 { _ = t.allow("k\(i)", now: Date(timeIntervalSince1970: Double(i)), interval: 5) }
        #expect(t.count <= 10)
    }
}

@Suite struct RxWordScannerTests {
    @Test func ownCallSplitAcrossChunksIsFoundOnce() {
        var sc = RxWordScanner()
        var found: [String] = []
        for ch in "CQ DE OK1XOE K\r\n" { found += sc.feed(String(ch), echo: false) }
        #expect(found == ["CQ", "DE", "OK1XOE", "K"])
    }
    @Test func incompleteWordWaitsAndEchoBreaksWord() {
        var sc = RxWordScanner()
        let a = sc.feed("OK1X", echo: false), b = sc.feed("OE", echo: false), c = sc.feed(" ", echo: false)
        #expect(a.isEmpty && b.isEmpty && c == ["OK1XOE"])
        // echo vlastního vysílání se nesnímá a ukončuje slovo
        let d = sc.feed("DL1", echo: false), e = sc.feed("OK1XOE OK1XOE ", echo: true), f = sc.feed(" ", echo: false)
        #expect(d.isEmpty && e.isEmpty && f.isEmpty)
    }
    @Test func pendingWordIsBounded() {
        var sc = RxWordScanner()
        _ = sc.feed(String(repeating: "X", count: 500), echo: false)
        #expect(sc.pendingCount <= RxWordScanner.maxWord)
    }
}

/// Zvuk a oznámení zaznamenané místo skutečných.
@MainActor final class RecordingSink: AlertSink {
    var sounds = 0
    var notes: [(String, String)] = []
    var authRequests = 0
    func playSound() { sounds += 1 }
    func notify(title: String, body: String) { notes.append((title, body)) }
    func requestNotificationAuthorization() { authRequests += 1 }
}

@MainActor @Suite struct RxAlertModelTests {
    func model(_ change: (inout AppSettings) -> Void = { _ in }) -> (AppModel, RecordingSink) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rxalert-\(UUID().uuidString)")
        let store = SettingsStore(directory: dir)
        var s = AppSettings(); s.station.call = "OK1XOE"; change(&s)
        try? store.save(s)
        let sink = RecordingSink()
        let m = AppModel(settingsStore: store, profileStore: ProfileStore(directory: dir), alertSink: sink, alertClock: { Date(timeIntervalSince1970: 5000) })
        return (m, sink)
    }
    @Test func ownCallAlertsOncePer20sAndIgnoresEcho() {
        let (m, sink) = model()
        for ch in "OK1XOE DE DL1ABC " { m.appendRx(String(ch), echo: false) }
        #expect(sink.sounds == 1)
        m.appendRx("OK1XOE ", echo: false)          // stejný okamžik hodin → omezeno
        #expect(sink.sounds == 1)
        m.appendRx("OK1XOE OK1XOE ", echo: true)    // echo vůbec ne
        #expect(sink.sounds == 1)
        #expect(sink.notes.isEmpty)                 // oznámení je ve výchozím stavu vypnuté
    }
    @Test func ownCallSoundCanBeDisabledAndNotificationEnabled() {
        let (m, sink) = model { $0.alerts.myCallSound = false; $0.alerts.myCallNotification = true }
        m.appendRx("OK1XOE/P ", echo: false)
        #expect(sink.sounds == 0)
        #expect(sink.notes.count == 1)
    }
    @Test func neededSpotAlertsOncePerSpot() {
        let (m, sink) = model { $0.alerts.watchCalls = "DL1ABC" }
        let spot = Spot(frequencyKHz: 14085, call: "DL1ABC", spotter: "X", comment: "", time: Date(timeIntervalSince1970: 5000), mode: "RTTY")
        m.checkSpotNeeded(spot)
        m.checkSpotNeeded(spot)
        #expect(sink.sounds == 1)
        #expect(m.messages.contains { $0.contains("DL1ABC") })
        let other = Spot(frequencyKHz: 14085, call: "DL9ZZZ", spotter: "X", comment: "", time: Date(timeIntervalSince1970: 5000), mode: "RTTY")
        m.checkSpotNeeded(other)
        #expect(sink.sounds == 1)
        #expect(m.neededReasons(for: spot) == [.watched])
        #expect(m.neededReasons(for: other).isEmpty)
    }
    @Test func neededCallInRxText() {
        let (m, sink) = model { $0.alerts.watchCalls = "DL1ABC" }
        for ch in "CQ CQ DE DL1ABC/P DL1ABC K " { m.appendRx(String(ch), echo: false) }
        #expect(sink.sounds == 1)
    }
}
