import Foundation
import Testing
import DXCC
import QSOLog
import Settings
@testable import AppCore

// Contest points and score (docs/rulings.md, the section on points and score).

private let db = CountryDB.shared!
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func rec(_ call: String, _ khz: Double?, exch: String? = nil, min: Double = 1, mode: String = "RTTY") -> QSORecord {
    var r = QSORecord(call: call, timeOn: t0.addingTimeInterval(min * 60), mode: mode)
    r.frequency = khz.map { $0 * 1000 }; r.exchangeRcvd = exch
    r.cqZone = db.lookup(call)?.cqZone
    return r
}
private func calc(_ p: ContestPreset, own: String = "OK1XOE", locator: String = "") -> ScoreCalculator {
    ScoreCalculator(preset: p, ownCall: own, ownLocator: locator, countries: db)
}
private func tally(_ p: ContestPreset, _ log: [QSORecord], own: String = "OK1XOE", locator: String = "",
                   qtc: [QTCSeries] = []) -> ScoreTally {
    calc(p, own: own, locator: locator).tally(records: log, qtc: qtc, since: t0)
}
/// A small log: the same entity (OK), the same continent (DL), a different continent (W) on 20 m, a DL dupe on 20 m.
private func smallLog(_ extra: [QSORecord] = []) -> [QSORecord] {
    [rec("OK1ABC", 14080, exch: "15", min: 1), rec("DL1ABC", 14082, exch: "14", min: 2),
     rec("W1AW", 14084, exch: "05 CT", min: 3), rec("DL1ABC", 14086, exch: "14", min: 4)] + extra
}

// MARK: Rules

@Test func everyPresetHasScoreRuleAndSource() {
    for p in ContestPreset.allCases {
        let r = ScoreRule.rule(for: p)
        #expect(r.preset == p && !r.source.isEmpty && !r.pointsNote.isEmpty)
    }
}

@Test func outsideContestNoScore() {
    var c = ContestSettings.preset(.cqwwRTTY, year: 2026)
    #expect(ScoreRule.rule(for: c)?.preset == .cqwwRTTY)
    c.enabled = false
    #expect(ScoreRule.rule(for: c) == nil)
    var custom = ContestSettings(); custom.enabled = true
    #expect(ScoreRule.rule(for: custom) == nil)
}

// MARK: Points per contest

@Test func cqwwPoints() {
    let t = tally(.cqwwRTTY, smallLog([rec("DL1ABC", 7040, exch: "14", min: 5)]))
    #expect(t.band("20m") == BandScore(qsos: 4, dupes: 1, points: 1 + 2 + 3))
    #expect(t.band("40m").points == 2)
    #expect(t.points == 8 && t.qsos == 5 && t.dupes == 1)
    // zones 15, 14, 5 + OK, DL, K + CT on 20 m; zone 14 + DL on 40 m
    #expect(t.multipliers.total == 9)
    #expect(t.score == 8 * 9)
}

@Test func wpxPointsDependOnBand() {
    let low = [rec("OK1ABC", 3580, min: 5), rec("DL1ABC", 7040, min: 6), rec("W1AW", 7042, min: 7)]
    let t = tally(.cqwpxRTTY, smallLog(low))
    #expect(t.band("20m").points == 1 + 2 + 3)
    #expect(t.band("80m").points == 2)
    #expect(t.band("40m").points == 4 + 6)
    #expect(t.points == 18)
    #expect(t.multipliers.total == 3)                                   // OK1, DL1, W1 once per contest
    #expect(t.score == 54)
}

@Test func arrlRoundupOnePointPerQSO() {
    let log = [rec("W1AW", 14080, exch: "CT", min: 1), rec("VE3ABC", 14082, exch: "ON", min: 2),
               rec("DL1ABC", 14084, min: 3), rec("W1AW", 14086, exch: "CT", min: 4), rec("W1AW", 7040, exch: "CT", min: 5)]
    let t = tally(.arrlRoundup, log)
    #expect(t.points == 4 && t.dupes == 1)
    #expect(t.multipliers.total == 3)                                   // CT, ON, DL
    #expect(t.score == 12)
}

@Test func bartgScoreMultipliesContinents() {
    let t = tally(.bartgHF, smallLog([rec("W1AW", 7040, min: 5)]))
    #expect(t.points == 4)                                              // 1 point per QSO, 0 for a dupe
    // 20 m: OK, DL, K, W1; 40 m: K, W1 → 6; the continents EU, NA → 2
    #expect(t.bandMultipliers == 6 && t.continents == 2)
    #expect(t.score == 4 * 6 * 2)
}

@Test func sartgPoints() {
    let t = tally(.sartgRTTY, smallLog())
    #expect(t.points == 5 + 10 + 15)
    #expect(t.score == 30 * t.multipliers.total)
}

@Test func jartsPoints() {
    let t = tally(.jartsRTTY, smallLog())
    #expect(t.points == 2 + 2 + 3)
    #expect(t.score == 7 * t.multipliers.total)
}

@Test func okdxPointsForOKAndOthers() {
    let low = [rec("DL1ABC", 3580, min: 5), rec("W1AW", 3582, min: 6)]
    let ok = tally(.okDXRTTY, smallLog(low))
    #expect(ok.band("20m").points == 1 + 1 + 2)
    #expect(ok.band("80m").points == 3 + 6)
    #expect(ok.score == 13 * ok.multipliers.total)
    let dl = tally(.okDXRTTY, [rec("OK1ABC", 14080, min: 1), rec("OK1ABC", 7040, min: 2), rec("W1AW", 7042, min: 3)], own: "DL1ABC")
    #expect(dl.points == 1 + 3 + 6)
    // 20 m: OK + station OK1ABC; 40 m: OK + OK1ABC + K
    #expect(dl.multipliers.total == 5 && dl.score == 50)
}

@Test func waeScoreCountsQTC() {
    let log = [rec("W1AW", 14080, min: 1), rec("JA1ABC", 14082, min: 2), rec("W1AW", 14084, min: 3), rec("W1AW", 3580, min: 4)]
    let lines = (1...5).map { QTCLine(time: "0001", call: "K\($0)ABC", serial: $0) }
    let qtc = [QTCSeries(direction: .sent, number: 1, counterpart: "W1AW", time: t0.addingTimeInterval(600), frequency: 14_085_000, lines: lines),
               QTCSeries(direction: .received, number: 1, counterpart: "OK1X", time: t0.addingTimeInterval(-600), lines: lines)]  // before the contest
    let t = tally(.waeRTTY, log, qtc: qtc)
    #expect(t.points == 3 && t.dupes == 1 && t.qtc == 5)
    #expect(t.band("20m").qtc == 5)
    // 20 m: W1, JA1 × 2; 80 m: W1 × 4 → 8
    #expect(t.multipliers.weightedTotal == 8)
    #expect(t.score == (3 + 5) * 8)
}

@Test func makrothenDistancePoints() {
    // JO70 (centre 15° E, 50.5° N) – JO60 (13° E, 50.5° N): 141 km
    let km = ScoreCalculator.makrothenKm("JO70", "JO60")
    #expect(km == 141)
    let log = [rec("DL1ABC", 14080, exch: "JO60", min: 1), rec("DL2ABC", 3580, exch: "JO60", min: 2),
               rec("DL3ABC", 7040, exch: "JO60", min: 3), rec("OK1ABC", 3582, exch: "JO70", min: 4),
               rec("OK2ABC", 3584, exch: "", min: 5)]
    let t = tally(.makrothen, log, locator: "JO70FC")
    #expect(t.band("20m").points == 141)
    #expect(t.band("80m").points == 282 + 100 + 0)                      // the same square is 100 without weighting, 0 without a locator
    #expect(t.band("40m").points == 211)                                // 141 × 1.5 = 211.5 → 211
    #expect(t.score == t.points && t.points == 141 + 382 + 211)
}

// MARK: Incrementally = in full

@Test(arguments: ContestPreset.allCases)
func incrementalEqualsFull(_ p: ContestPreset) {
    let log = smallLog([rec("W1AW", 7040, exch: "05 CT", min: 5), rec("JA1ABC", 21080, exch: "25", min: 6),
                        rec("VE3ABC", 28080, exch: "04 ON", min: 7), rec("OK1ABC", 3580, exch: "15", min: 8),
                        rec("OLD1", 14080, min: -10)])
    let c = calc(p, locator: "JO70")
    let full = c.tally(records: log, qtc: [], since: t0)
    var inc = c.tally(records: [], qtc: [], since: t0)
    for r in log { c.add(r, to: &inc) }
    #expect(inc == full)
    #expect(full.qsos == 8)                                             // a QSO before the contest start does not count
}

@Test func formulaText() {
    let t = tally(.cqwpxRTTY, smallLog())
    #expect(t.formulaText.contains("6") && t.formulaText.contains("18"))
    #expect(ScoreTally.format(5535) == "5\u{00A0}535")
    #expect(ScoreTally.format(12) == "12")
    #expect(ScoreTally.format(1_234_567) == "1\u{00A0}234\u{00A0}567")
}
