// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
// The texts are compared against the Czech wording (the localization key) - the tests run in the base language.
import Foundation
import ModemKit
import Settings
import Testing
@testable import AppUI

/// Records what would be spoken instead of posting a VoiceOver announcement.
@MainActor final class RecordingAnnouncer: SpeechAnnouncing {
    var spoken: [String] = []
    var interrupting: [Bool] = []
    func announce(_ text: String, interrupts: Bool) { spoken.append(text); interrupting.append(interrupts) }
}

/// A limiter with no gaps (the integration tests check the announcement, not the rate limit).
private let openPolicy = AnnouncementLimiter.Policy(minGap: 0, repeatGap: 0, window: 60, maxPerWindow: 10_000)

// MARK: Rate limiting

@Suite struct AnnouncementLimiterTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func firstOneGoesOutAndTheSecondWaitsForTheGap() {
        var l = AnnouncementLimiter(policy: .init(minGap: 2, repeatGap: 30, window: 60, maxPerWindow: 8))
        #expect(l.allow(key: "a", now: t0) == 0)
        #expect(l.allow(key: "b", now: t0.addingTimeInterval(1)) == nil)       // too soon after the previous one
        #expect(l.allow(key: "b", now: t0.addingTimeInterval(2)) == 1)         // and it reports the one that was dropped
        #expect(l.allow(key: "c", now: t0.addingTimeInterval(4)) == 0)
    }

    @Test func theSameEventIsNotRepeated() {
        var l = AnnouncementLimiter(policy: .init(minGap: 1, repeatGap: 30, window: 60, maxPerWindow: 8))
        #expect(l.allow(key: "dupe|DL1ABC", now: t0) == 0)
        #expect(l.allow(key: "dupe|DL1ABC", now: t0.addingTimeInterval(20)) == nil)
        #expect(l.allow(key: "dupe|DL1ABC", now: t0.addingTimeInterval(31)) == 1)
    }

    /// A burst of spots after connecting to the cluster must not turn into a monologue.
    @Test func aFloodIsCutToTheCeilingOfTheWindow() {
        var l = AnnouncementLimiter(policy: .init(minGap: 0, repeatGap: 0, window: 60, maxPerWindow: 3))
        var allowed = 0
        for i in 0..<200 where l.allow(key: "spot\(i)", now: t0.addingTimeInterval(Double(i) * 0.1)) != nil { allowed += 1 }
        #expect(allowed == 3)
        #expect(l.suppressedCount == 197)
        // once the window has passed it speaks again and says how much was skipped
        #expect(l.allow(key: "later", now: t0.addingTimeInterval(80)) == 197)
        #expect(l.suppressedCount == 0)
    }

    @Test func resetForgetsTheHistory() {
        var l = AnnouncementLimiter(policy: .init(minGap: 10, repeatGap: 30, window: 60, maxPerWindow: 1))
        #expect(l.allow(key: "a", now: t0) == 0)
        #expect(l.allow(key: "a", now: t0.addingTimeInterval(1)) == nil)
        l.reset()
        #expect(l.allow(key: "a", now: t0.addingTimeInterval(1)) == 0)
    }

    @Test func memoryIsBounded() {
        var l = AnnouncementLimiter(policy: .init(minGap: 0, repeatGap: 1, window: 60, maxPerWindow: 10_000), maxKeys: 50)
        for i in 0..<5_000 { _ = l.allow(key: "k\(i)", now: t0.addingTimeInterval(Double(i))) }
        #expect(l.keyCount <= 51)
    }
}

// MARK: Spoken summaries of the drawn views

@Suite struct SpokenSummaryTests {
    @Test func tuningNamesTheValuesNotThePicture() {
        let s = SpokenSummary.tuning(mark: 2125, space: 2295, afc: true, level: 1_000, squelchOpen: true, notches: 2)
        #expect(s == "mark 2125 Hz, space 2295 Hz, shift 170 Hz, AFC zapnuto, silný signál, squelch otevřen, zářezů: 2")
        let off = SpokenSummary.tuning(mark: 1000, space: 1170, afc: false, level: 0, squelchOpen: false)
        #expect(off == "mark 1000 Hz, space 1170 Hz, shift 170 Hz, AFC vypnuto, bez signálu, squelch zavřen")
        #expect(!off.contains("zářez"))
    }

    @Test func signalStrengthIsCoarse() {
        #expect(SpokenSummary.signalWord(level: 0) == "bez signálu")
        #expect(SpokenSummary.signalWord(level: 1) == "bez signálu")
        #expect(SpokenSummary.signalWord(level: 10) == "slabý signál")
        #expect(SpokenSummary.signalWord(level: 100) == "střední signál")
        #expect(SpokenSummary.signalWord(level: 1_000) == "silný signál")
        #expect(SpokenSummary.signalWord(level: 10_000) == "velmi silný signál")
        #expect(SpokenSummary.signalFraction(level: -5) == 0)          // a nonsensical level does not break the formula
        #expect(SpokenSummary.signalFraction(level: 1e30) == 1)
    }

    @Test func scopeWithoutDataSaysSo() {
        #expect(SpokenSummary.scope(source: "Det.", scope: nil, sourceIndex: 1, frozen: false, width: 2048, offset: 0)
            == "scope, zdroj Det., čekám na data")
        let empty = DemodScope(marks: [[], []], spaces: [[], []], bit: [1, 0], sync: [0, 0])
        #expect(SpokenSummary.scope(source: "LPF", scope: empty, sourceIndex: 1, frozen: false, width: 64, offset: 0)
            == "scope, zdroj LPF, tento zdroj se neplní")
        // an index outside the sources (a change of decoder) does not crash
        #expect(SpokenSummary.scope(source: "ATC", scope: empty, sourceIndex: 9, frozen: false, width: 64, offset: 0)
            == "scope, zdroj ATC, čekám na data")
    }

    @Test func scopeDescribesLevelsAndSync() {
        let mk = [Float](repeating: 1, count: 8), sp = [Float](repeating: 0.5, count: 8)
        let d = DemodScope(marks: [mk], spaces: [sp], bit: [1, 1, 1, 1, 0, 0, 0, 0], sync: [-1, 0, 0, 0, -1, 0, 0, 0])
        let s = SpokenSummary.scope(source: "Filtr", scope: d, sourceIndex: 0, frozen: true, width: 8, offset: 0)
        #expect(s == "scope, zdroj Filtr, zobrazeno 8 z 8 vzorků, mark 100 procent, space 50 procent, "
                + "bit v mark 50 procent času, startbitů: 2, zmrazeno")
        // the shifted window (offset 1) shows the end of the batch - there the bit is 0 the whole time
        let end = SpokenSummary.scope(source: "Filtr", scope: d, sourceIndex: 0, frozen: false, width: 4, offset: 1)
        #expect(end.contains("zobrazeno 4 z 8 vzorků") && end.contains("bit v mark 0 procent času"))
        #expect(!end.contains("zmrazeno"))
    }

    @Test func aSpotLabelSaysCallFrequencyAgeAndStatus() {
        #expect(SpokenSummary.spot(call: "DL1ABC", kHz: 14_085.52, ageMinutes: 3, status: "nová stanice")
            == "DL1ABC, 14085.5 kHz, před 3 min, nová stanice")
        // a record from the log has no age
        #expect(SpokenSummary.spot(call: "OK1XOE/P", kHz: 7_040, ageMinutes: nil, status: "odpracováno")
            == "OK1XOE lomeno P, 7040.0 kHz, odpracováno")
    }
}

// MARK: Reading the received text

@Suite struct RxLineReaderTests {
    @Test func linesSkipEmptyOnesAndNoise() {
        let t = "CQ CQ DE DL1ABC\r\n   \r\nOK1XOE DE DL1ABC K\r\n"
        #expect(RxLineReader.lines(t) == ["CQ CQ DE DL1ABC", "OK1XOE DE DL1ABC K"])
        #expect(RxLineReader.lines("") == [])
        #expect(RxLineReader.lines("\r\n \r\n") == [])
    }

    @Test func stepsBackFromTheLastLine() {
        let lines = RxLineReader.recentLines("a\nb\nc\n")
        #expect(RxLineReader.line(lines, back: 0) == "c")
        #expect(RxLineReader.line(lines, back: 2) == "a")
        #expect(RxLineReader.line(lines, back: 3) == nil)
        #expect(RxLineReader.line(lines, back: -1) == nil)
        #expect(RxLineReader.line([], back: 0) == nil)
    }

    @Test func aLineWithoutACRIsShortenedToItsEnd() {
        let long = String(repeating: "X", count: 500) + "OK1XOE"
        let spoken = RxLineReader.line(RxLineReader.recentLines(long), back: 0)
        #expect(spoken?.count == RxLineReader.maxSpoken)
        #expect(spoken?.hasSuffix("OK1XOE") == true)
    }

    @Test func theSnapshotKeepsOnlyTheLastLines() {
        let text = (0..<200).map { "line \($0)" }.joined(separator: "\n")
        let lines = RxLineReader.recentLines(text)
        #expect(lines.count == RxLineReader.maxLines)
        #expect(RxLineReader.line(lines, back: 0) == "line 199")
    }
}

// MARK: The model: commands and announcements

@Test @MainActor func readLastLineCommandSpeaksTheNewestLineAndStepsBack() async throws {
    let f = Fixture()
    let rec = RecordingAnnouncer()
    f.model.announcer = rec
    f.model.speakLastRxLine()
    #expect(rec.spoken == ["Příjem je prázdný."])
    f.model.speakPreviousRxLine()                   // an empty receive window: "previous" does not claim a line exists
    #expect(rec.spoken == ["Příjem je prázdný.", "Příjem je prázdný."])
    // deliberately without my own call - that would add an automatic announcement to the recording
    f.model.appendRx("CQ DE DL1ABC\r\n", echo: false)
    f.model.appendRx("G3XYZ DE DL1ABC K\r\n", echo: false)
    f.model.speakLastRxLine()
    #expect(rec.spoken.last == "G3XYZ DE DL1ABC K")
    f.model.speakPreviousRxLine()
    #expect(rec.spoken.last == "CQ DE DL1ABC")
    f.model.speakPreviousRxLine()
    #expect(rec.spoken.last == "Dřívější řádek už není.")
    // text arriving in the meantime must not shift the snapshot
    f.model.appendRx("noise\r\n", echo: false)
    f.model.speakPreviousRxLine()
    #expect(rec.spoken.last == "Dřívější řádek už není.")
    f.model.speakLastRxLine()
    #expect(rec.spoken.last == "noise")
    // an explicit request interrupts what is being read (and is not rate-limited)
    #expect(rec.interrupting.allSatisfy { $0 })
    f.model.clearRx()
    f.model.speakLastRxLine()
    #expect(rec.spoken.last == "Příjem je prázdný.")
}

@Test @MainActor func tuningIsReadOnDemand() async throws {
    let f = Fixture()
    let rec = RecordingAnnouncer()
    f.model.announcer = rec
    f.model.speakTuning()
    #expect(rec.spoken.count == 1)
    #expect(rec.spoken[0] == f.model.tuningSummary)
    #expect(rec.spoken[0].contains("mark 2125 Hz") && rec.spoken[0].contains("shift 170 Hz"))
}

@Test @MainActor func myCallInReceiveIsAnnouncedOnceAndCanBeTurnedOff() async throws {
    let f = Fixture()
    let rec = RecordingAnnouncer()
    f.model.announcer = rec
    f.model.appendRx("CQ OK1XOE DE DL1ABC ", echo: false)
    #expect(rec.spoken == ["Volá vás OK1XOE"])
    // a repeat inside the gap is not spoken again (the same event)
    f.model.appendRx("OK1XOE OK1XOE ", echo: false)
    #expect(rec.spoken.count == 1)
    // the switch in Settings turns the speech off
    f.model.setSpeakAlerts(false)
    f.model.announcementLimiter.reset()
    f.model.appendRx("OK1XOE ", echo: false)
    #expect(rec.spoken.count == 1)
    #expect(!f.model.settings.alerts.speakAlerts)
    f.model.setSpeakAlerts(true)
    f.model.announcementLimiter.reset()
    f.model.appendRx("OK1XOE ", echo: false)
    #expect(rec.spoken.count == 2)
}

@Test @MainActor func announcementsAreRateLimitedAndReportWhatWasSkipped() async throws {
    let f = Fixture()
    let rec = RecordingAnnouncer()
    f.model.announcer = rec
    f.model.announcementLimiter.policy = .init(minGap: 60, repeatGap: 60, window: 60, maxPerWindow: 8)
    f.model.announce("první", key: "a")
    for i in 0..<20 { f.model.announce("dropped \(i)", key: "k\(i)") }
    #expect(rec.spoken == ["první"])
    f.model.announcementLimiter.policy = openPolicy
    f.model.announce("další", key: "b")
    #expect(rec.spoken.last == "další (20 hlášení přeskočeno)")
    #expect(rec.interrupting.last == false)                    // a background event does not interrupt
    #expect(f.model.lastAnnouncement == rec.spoken.last)
}

// A dupe and a new multiplier are announced on a change, not on every keystroke in the Call field.
@Test @MainActor func dupeAndNewMultiplierAreAnnounced() async throws {
    let f = Fixture()
    f.configure = { $0.contest = ContestSettings.preset(.cqwwRTTY, year: 2026); $0.contest.start = Date().addingTimeInterval(-3600) }
    let rec = RecordingAnnouncer()
    f.model.announcer = rec
    f.model.announcementLimiter.policy = openPolicy
    await f.model.start()
    await f.model.setQSOField("freq", "14080")
    await f.model.setQSOField("call", "DL1ABC")
    await f.settle()
    #expect(rec.spoken.contains { $0.hasPrefix("Nový násobič: ") && $0.contains("DL") })
    let afterMult = rec.spoken.count
    await f.model.setQSOField("exchangeRcvd", "14")
    await f.model.logQSO()
    await f.settle()
    await f.model.setQSOField("call", "DL1ABC")
    for _ in 0..<300 where !f.model.isDupe { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(f.model.isDupe)
    #expect(rec.spoken.contains("Duplicita: DL1ABC"))
    #expect(rec.spoken.count > afterMult)
    // the same callsign again does not announce a second time
    let n = rec.spoken.count
    f.model.announceQSOState()
    #expect(rec.spoken.count == n)
    await f.model.stop()
}
