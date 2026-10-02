import Foundation
import Testing
import DXCC
import QSOLog
import Settings
@testable import AppCore

// Review plan18: dupes per the contest rules, the contest window in the score, the BARTG table, %k, own entity.

private let db = CountryDB.shared!
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func rec(_ call: String, _ khz: Double?, exch: String? = nil, min: Double = 1, mode: String = "RTTY") -> QSORecord {
    var r = QSORecord(call: call, timeOn: t0.addingTimeInterval(min * 60), mode: mode)
    r.frequency = khz.map { $0 * 1000 }; r.exchangeRcvd = exch
    r.cqZone = db.lookup(call)?.cqZone
    return r
}
private func calc(_ p: ContestPreset, own: String = "OK1XOE", locator: String = "JO70") -> ScoreCalculator {
    ScoreCalculator(preset: p, ownCall: own, ownLocator: locator, countries: db)
}

// MARK: Dupes

// RTTY-only presets: the same station once per band regardless of mode and leg (verified against the rules).
@Test(arguments: ContestPreset.allCases.filter { $0 != .russianDigi && $0 != .proDigi })
func presetDupeIsOncePerBandRegardlessOfMode(_ p: ContestPreset) {
    let log = [rec("W1AW", 14080, exch: "05 CT JO70", min: 1), rec("W1AW", 14081, exch: "05 CT JO70", min: 2, mode: "PSK"),
               rec("W1AW", 14082, exch: "05 CT JO70", min: 9 * 60)]                        // a different leg (SARTG, Makrothen)
    let t = calc(p).tally(records: log, qtc: [], since: t0)
    #expect(t.band("20m").dupes == 2, "\(p)")
    #expect(!DupeCheck.perMode(preset: p))
}

@Test func customContestDupeKeepsMode() {
    #expect(DupeCheck.perMode(preset: nil))
    let log = [rec("W1AW", 14080)]
    #expect(!DupeCheck.isDupe(call: "W1AW", band: "20m", mode: "PSK", records: log, since: t0, perMode: true))
    #expect(DupeCheck.isDupe(call: "W1AW", band: "20m", mode: "PSK", records: log, since: t0, perMode: false))
    #expect(DupeCheck.isDupe(call: "W1AW/P", band: nil, mode: "PSK", records: log, since: t0, perMode: false))
    #expect(DupeCheck.key(call: "W1AW/P", band: "20m", mode: "rtty", perMode: true) == DupeCheck.key(call: "W1AW", band: "20m", mode: "RTTY", perMode: true))
    #expect(DupeCheck.key(call: "W1AW", band: "20m", mode: "PSK", perMode: false) == DupeCheck.key(call: "W1AW", band: "20m", mode: "RTTY", perMode: false))
}

// MARK: Contest window

@Test func scoreWindowIsFrozenAndHasEnd() {
    let c = calc(.okDXRTTY)                                                  // OK DX: 24 h
    var contest = ContestSettings.preset(.okDXRTTY, year: 2026)
    contest.start = t0
    #expect(contest.end == t0.addingTimeInterval(24 * 3600))
    let log = [rec("DL1ABC", 14080, min: 1), rec("W1AW", 14080, min: 25 * 60)]            // the second one after the end
    let full = c.tally(records: log, qtc: [], since: t0, until: contest.end)
    #expect(full.qsos == 1 && full.since == t0 && full.until == contest.end)
    var inc = c.tally(records: [], qtc: [], since: t0, until: contest.end)
    for r in log { c.add(r, to: &inc) }
    #expect(inc == full)                                                     // the increment uses the same window
    // without a start: the window is fixed when the score is computed (it does not move with time)
    var none = ContestSettings(); none.enabled = true
    #expect(none.end == nil)
}

@Test func presetDurations() {
    let h: [ContestPreset: Double] = [.arrlRoundup: 30, .cqwpxRTTY: 48, .bartgHF: 48, .sartgRTTY: 40, .cqwwRTTY: 48,
                                      .makrothen: 40, .jartsRTTY: 48, .waeRTTY: 48, .okDXRTTY: 24,
                                      .sartgNewYear: 3, .proDigi: 24, .bartgSprint: 24, .mexicoRTTY: 36, .naqpRTTY: 12,
                                      .naSprintRTTY: 4, .ybDX: 24, .eaRTTY: 24, .igryWW: 30, .bartgSprint75: 4, .spDX: 24,
                                      .voltaRTTY: 24, .rookieRoundup: 6, .russianRTTY: 24, .urcDX: 24, .russianDigi: 24,
                                      .darcSprint: 1.5, .trcDigi: 36, .wrt: 0.5]
    for p in ContestPreset.allCases { #expect(p.durationHours == h[p], "\(p)") }
    var c = ContestSettings.preset(.sartgRTTY, year: 2026)
    c.format = .zone                                                          // no longer a preset → the end is unknown
    #expect(c.end == nil)
}

// MARK: The BARTG table, the Makrothen QSO count in multipliers, own entity

@Test func bartgTableTotalExcludesContinents() {
    let log = [rec("DL1ABC", 14080, min: 1), rec("W1AW", 14082, min: 2), rec("W1AW", 7040, min: 3)]
    let t = calc(.bartgHF).tally(records: log, qtc: [], since: t0)
    // 20 m: DL, K, W1; 40 m: K, W1 → 5; the continents EU, NA counted separately in the formula
    #expect(t.tableMultiplierTotal == 5 && t.continents == 2)
    #expect(!t.showsOnceMultiplierRow)
    let cq = calc(.cqwwRTTY).tally(records: log, qtc: [], since: t0)
    #expect(cq.tableMultiplierTotal == cq.multipliers.total)
    let arrl = calc(.arrlRoundup).tally(records: log, qtc: [], since: t0)
    #expect(arrl.showsOnceMultiplierRow)
}

@Test func makrothenMultiplierTallyCountsNoQSOs() {
    let log = [rec("DL1ABC", 14080, exch: "JO60", min: 1)]
    let t = calc(.makrothen).tally(records: log, qtc: [], since: t0)
    let m = MultiplierCalculator(rule: .rule(for: .makrothen), countries: db).tally(records: log, since: t0)
    #expect(t.multipliers.qsoCount == m.qsoCount && m.qsoCount == 0)
}

@Test func unknownOwnCountryOrLocatorIsFlagged() {
    #expect(!calc(.cqwwRTTY).tally(records: [], qtc: [], since: t0).ownCountryUnknown)
    #expect(calc(.cqwwRTTY, own: "").tally(records: [], qtc: [], since: t0).ownCountryUnknown)
    let noDB = ScoreCalculator(preset: .cqwwRTTY, ownCall: "OK1XOE", ownLocator: "", countries: nil)
    #expect(noDB.tally(records: [], qtc: [], since: t0).ownCountryUnknown)
    #expect(!calc(.makrothen, own: "").tally(records: [], qtc: [], since: t0).ownCountryUnknown)   // Makrothen does not need the entity
    #expect(calc(.makrothen, locator: "").tally(records: [], qtc: [], since: t0).ownLocatorMissing)
    #expect(!calc(.cqwwRTTY, locator: "").tally(records: [], qtc: [], since: t0).ownLocatorMissing)
}

// MARK: %k = the spot frequency (RF), not the rig frequency

@Test func clusterSpotKHzUndoesSpotOffset() {
    // useSpot tunes the rig to the spot + the offset → %k = rig − offset
    #expect(AppController.clusterSpotKHz(rigHz: 14_082_125, manualHz: nil, offsetHz: 2125) == 14080)
    #expect(AppController.clusterSpotKHz(rigHz: 14_080_000, manualHz: 7_040_000, offsetHz: 0) == 14080)
    // an offset outside the range is clamped, as in useSpot
    #expect(AppController.clusterSpotKHz(rigHz: 14_090_000, manualHz: nil, offsetHz: 50_000) == 14080)
    // the manual frequency is already RF (with no rig the spot frequency is logged) – the offset is not subtracted
    #expect(AppController.clusterSpotKHz(rigHz: nil, manualHz: 7_040_000, offsetHz: 2125) == 7040)
    #expect(AppController.clusterSpotKHz(rigHz: nil, manualHz: nil, offsetHz: 0) == nil)
    #expect(AppController.clusterSpotKHz(rigHz: 1000, manualHz: nil, offsetHz: 2125) == nil)             // ≤ 0
}
