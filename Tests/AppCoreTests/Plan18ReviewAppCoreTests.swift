import Foundation
import Testing
import DXCC
import QSOLog
import Settings
@testable import AppCore

// Review plan18: duplicity podle pravidel závodu, okno závodu ve skóre, BARTG tabulka, %k, vlastní země.

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

// MARK: Duplicity

// Všechny předvolby (jen RTTY): stejná stanice jednou na pásmu bez ohledu na mód a etapu (ověřeno v pravidlech).
@Test(arguments: ContestPreset.allCases)
func presetDupeIsOncePerBandRegardlessOfMode(_ p: ContestPreset) {
    let log = [rec("W1AW", 14080, exch: "05 CT JO70", min: 1), rec("W1AW", 14081, exch: "05 CT JO70", min: 2, mode: "PSK"),
               rec("W1AW", 14082, exch: "05 CT JO70", min: 9 * 60)]                        // jiná etapa (SARTG, Makrothen)
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

// MARK: Okno závodu

@Test func scoreWindowIsFrozenAndHasEnd() {
    let c = calc(.okDXRTTY)                                                  // OK DX: 24 h
    var contest = ContestSettings.preset(.okDXRTTY, year: 2026)
    contest.start = t0
    #expect(contest.end == t0.addingTimeInterval(24 * 3600))
    let log = [rec("DL1ABC", 14080, min: 1), rec("W1AW", 14080, min: 25 * 60)]            // druhé po konci
    let full = c.tally(records: log, qtc: [], since: t0, until: contest.end)
    #expect(full.qsos == 1 && full.since == t0 && full.until == contest.end)
    var inc = c.tally(records: [], qtc: [], since: t0, until: contest.end)
    for r in log { c.add(r, to: &inc) }
    #expect(inc == full)                                                     // přírůstek používá stejné okno
    // bez začátku: okno se zafixuje při výpočtu (neposouvá se s časem)
    var none = ContestSettings(); none.enabled = true
    #expect(none.end == nil)
}

@Test func presetDurations() {
    let h: [ContestPreset: Double] = [.arrlRoundup: 30, .cqwpxRTTY: 48, .bartgHF: 48, .sartgRTTY: 40, .cqwwRTTY: 48,
                                      .makrothen: 40, .jartsRTTY: 48, .waeRTTY: 48, .okDXRTTY: 24]
    for p in ContestPreset.allCases { #expect(p.durationHours == h[p], "\(p)") }
    var c = ContestSettings.preset(.sartgRTTY, year: 2026)
    c.format = .zone                                                          // už to není předvolba → konec neznámý
    #expect(c.end == nil)
}

// MARK: BARTG tabulka, Makrothen počet spojení v násobičích, vlastní země

@Test func bartgTableTotalExcludesContinents() {
    let log = [rec("DL1ABC", 14080, min: 1), rec("W1AW", 14082, min: 2), rec("W1AW", 7040, min: 3)]
    let t = calc(.bartgHF).tally(records: log, qtc: [], since: t0)
    // 20 m: DL, K, W1; 40 m: K, W1 → 5; kontinenty EU, NA ve vzorci zvlášť
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
    #expect(!calc(.makrothen, own: "").tally(records: [], qtc: [], since: t0).ownCountryUnknown)   // Makrothen zemi nepotřebuje
    #expect(calc(.makrothen, locator: "").tally(records: [], qtc: [], since: t0).ownLocatorMissing)
    #expect(!calc(.cqwwRTTY, locator: "").tally(records: [], qtc: [], since: t0).ownLocatorMissing)
}

// MARK: %k = kmitočet spotu (RF), ne kmitočet rigu

@Test func clusterSpotKHzUndoesSpotOffset() {
    // useSpot ladí rig na spot + posun → %k = rig − posun
    #expect(AppController.clusterSpotKHz(rigHz: 14_082_125, manualHz: nil, offsetHz: 2125) == 14080)
    #expect(AppController.clusterSpotKHz(rigHz: 14_080_000, manualHz: 7_040_000, offsetHz: 0) == 14080)
    // posun mimo rozsah se ořízne jako v useSpot
    #expect(AppController.clusterSpotKHz(rigHz: 14_090_000, manualHz: nil, offsetHz: 50_000) == 14080)
    // ruční frekvence je už RF (bez rigu se zapisuje frekvence spotu) – posun se neodečítá
    #expect(AppController.clusterSpotKHz(rigHz: nil, manualHz: 7_040_000, offsetHz: 2125) == 7040)
    #expect(AppController.clusterSpotKHz(rigHz: nil, manualHz: nil, offsetHz: 0) == nil)
    #expect(AppController.clusterSpotKHz(rigHz: 1000, manualHz: nil, offsetHz: 2125) == nil)             // ≤ 0
}
