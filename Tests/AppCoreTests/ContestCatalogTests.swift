import Foundation
import Testing
import DXCC
import QSOLog
import Settings
@testable import AppCore

// The contest catalogue: dates, scoring and multipliers of the contests added from contestcalendar.com
// (docs/rulings.md, "Contest catalogue").

private let db = CountryDB.shared!
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)          // 2027-01-15

private func rec(_ call: String, _ khz: Double, exch: String? = nil, sent: String? = nil, min: Double = 1) -> QSORecord {
    var r = QSORecord(call: call, timeOn: t0.addingTimeInterval(min * 60), mode: "RTTY")
    r.frequency = khz * 1000; r.exchangeRcvd = exch; r.exchangeSent = sent
    return r
}
private func tally(_ p: ContestPreset, _ log: [QSORecord], own: String = "OK1XOE") -> ScoreTally {
    ScoreCalculator(preset: p, ownCall: own, ownLocator: "", countries: db).tally(records: log, qtc: [], since: t0)
}
private func start(_ p: ContestPreset, _ y: Int) -> [String] {
    let f = ISO8601DateFormatter()
    return p.starts(year: y).map { f.string(from: $0) }
}

// MARK: Dates

@Test func catalogueDates() {
    #expect(start(.urcDX, 2026) == ["2026-10-02T00:00:00Z"])
    #expect(start(.russianDigi, 2026) == ["2026-10-03T12:00:00Z"])
    #expect(start(.russianRTTY, 2026) == ["2026-09-05T12:00:00Z"])
    #expect(start(.naSprintRTTY, 2026) == ["2026-03-15T00:00:00Z", "2026-09-20T00:00:00Z"])
    #expect(start(.naSprintRTTY, 2027).first == "2027-03-14T00:00:00Z")
    #expect(start(.naqpRTTY, 2026) == ["2026-02-28T18:00:00Z", "2026-07-18T18:00:00Z"])
    #expect(start(.rookieRoundup, 2026) == ["2026-08-16T18:00:00Z"])
    #expect(start(.darcSprint, 2026).last == "2026-10-13T18:00:00Z")
    #expect(start(.darcSprint, 2026).count == 4)
    #expect(start(.spDX, 2026) == ["2026-04-25T12:00:00Z"])
    #expect(start(.voltaRTTY, 2027) == ["2027-05-08T12:00:00Z"])
    #expect(start(.ybDX, 2027) == ["2027-03-13T00:00:00Z"])
    #expect(start(.bartgSprint, 2027) == ["2027-01-23T12:00:00Z"])
    #expect(start(.proDigi, 2027) == ["2027-01-16T12:00:00Z"])
    #expect(start(.mexicoRTTY, 2027) == ["2027-02-06T12:00:00Z"])
    #expect(start(.eaRTTY, 2027) == ["2027-04-03T12:00:00Z"])
    #expect(start(.igryWW, 2027) == ["2027-04-10T12:00:00Z"])
    #expect(start(.trcDigi, 2026) == ["2026-12-12T06:00:00Z"])
    #expect(start(.sartgNewYear, 2027) == ["2027-01-01T08:00:00Z"])
    #expect(start(.wrt, 2026).contains("2026-10-02T01:45:00Z"))
    #expect(start(.wrt, 2026).count == 52)
}

// The nearest date: a running contest (URC today) stays selected, a finished one moves on
@Test func upcomingPicksRunningOrNext() {
    let f = ISO8601DateFormatter()
    let now = f.date(from: "2026-10-02T14:00:00Z")!
    #expect(ContestSettings.upcoming(.urcDX, now: now).start == f.date(from: "2026-10-02T00:00:00Z"))
    #expect(ContestSettings.upcoming(.russianDigi, now: now).start == f.date(from: "2026-10-03T12:00:00Z"))
    #expect(ContestSettings.upcoming(.russianRTTY, now: now).start == f.date(from: "2027-09-04T12:00:00Z"))
    #expect(ContestSettings.upcoming(.darcSprint, now: now).start == f.date(from: "2026-10-13T18:00:00Z"))
    #expect(ContestSettings.upcoming(.wrt, now: now).start == f.date(from: "2026-10-09T01:45:00Z"))
    #expect(ContestSettings.upcoming(.urcDX, now: now, exchange: "BHE").exchange == "BHE")
}

@Test func everyPresetHasRulesOverview() {
    for p in ContestPreset.allCases {
        let r = ContestCatalog.rules(p, ownCountry: "OK")
        #expect(!r.dates.isEmpty && !r.exchange.isEmpty && !r.points.isEmpty && !r.multipliers.isEmpty, "\(p)")
        #expect(URL(string: r.source) != nil, "\(p)")
        #expect(ContestPreset.matching(ContestSettings.preset(p, year: 2027)) == p, "\(p)")
    }
}

@Test func defaultExchange() {
    var st = Station(); st.call = "OK1XOE"; st.name = "Tomas Kaplan"
    #expect(ContestCatalog.defaultExchange(.urcDX, station: st, countries: db) == "BHE")
    st.call = "OK2ABC"
    #expect(ContestCatalog.defaultExchange(.urcDX, station: st, countries: db) == "MOR")
    #expect(ContestCatalog.defaultExchange(.wrt, station: st, countries: db) == "TOMAS OK")
    #expect(ContestCatalog.defaultExchange(.naqpRTTY, station: st, countries: db) == "TOMAS")
    #expect(ContestCatalog.defaultExchange(.naSprintRTTY, station: st, countries: db) == "TOMAS DX")
    st.call = "W1AW"; st.qth = "Newington, CT"
    #expect(ContestCatalog.defaultExchange(.naqpRTTY, station: st, countries: db) == "TOMAS CT")
    #expect(ContestCatalog.defaultExchange(.cqwpxRTTY, station: st, countries: db) == "")
}

// MARK: Scoring and multipliers

@Test func urcScoring() {
    let log = [rec("OK2ABC", 14080, exch: "599 MOR", sent: "BHE"), rec("OK1ABC", 14081, exch: "599 BHE", sent: "BHE"),
               rec("W1AW", 14082, exch: "599 CNT", sent: "BHE"), rec("W1AW", 3580, exch: "599 CNT", sent: "BHE"),
               rec("DL1ABC", 1838, exch: "599 BVR", sent: "BHE"), rec("DL1ABC", 28080, exch: "599 BVR", sent: "BHE"),
               rec("G4ABC/MM", 14083, exch: "599 MMS", sent: "BHE")]
    let t = tally(.urcDX, log)
    #expect(t.points == 2 + 1 + 4 + 6 + 5 + 3 + 3)
    #expect(t.multipliers.total == 6)                        // 20 m: MOR BHE CNT; 80: CNT; 160: BVR; 10: BVR
    #expect(t.score == 24 * 6)
}

@Test func russianRTTYScoring() {
    let log = [rec("UA3ABC", 14080, exch: "MA"), rec("DL1ABC", 14081, exch: "001"), rec("OK1ABC", 14082, exch: "002"),
               rec("W1AW", 7040, exch: "003")]
    let t = tally(.russianRTTY, log)
    #expect(t.points == 10 + 3 + 2 + 5)
    #expect(t.multipliers.total == 5)                        // 20 m: MA, UA, DL, OK; 40 m: K
    #expect(t.score == 100)
}

@Test func russianDigiScoringAndModes() {
    let log = [rec("UA3ABC", 7040, exch: "MA"), rec("W1AW/QRP", 14080, exch: "001")]
    let t = tally(.russianDigi, log)
    #expect(t.points == 3 * 2 + 5)
    #expect(t.multipliers.total == 3)
    #expect(DupeCheck.perMode(preset: .russianDigi))
}

@Test func voltaScoring() {
    let log = [rec("DL1ABC", 14080, exch: "14"), rec("W1AW", 3580, exch: "05"), rec("OK1ABC", 14081, exch: "15"),
               rec("W1AW", 14082, exch: "05")]
    let t = tally(.voltaRTTY, log)
    #expect(t.points == 3 + 40 + 0 + 20)                     // zone 15 × 14 = 3; 15 × 5 = 20, 80 m other continent × 2
    #expect(t.multipliers.total == 3)                        // 20 m: DL, W1; 80 m: W1 (own OK no mult)
    #expect(t.score == 4 * 63 * 3)
}

@Test func spDXScoring() {
    let log = [rec("SP5ABC", 14080, exch: "WA"), rec("UA3ABC", 14081, exch: "001"), rec("W1AW", 14082, exch: "002"),
               rec("OK1ABC", 7040, exch: "003")]
    let t = tally(.spDX, log)
    #expect(t.points == 5 + 0 + 10 + 2)
    #expect(t.bandMultipliers == 4 && t.continents == 2)    // 20 m: SP, WA, K; 40 m: OK × EU, NA
    #expect(t.score == 17 * 4 * 2)
    #expect(t.onceTableCount == 0)
}

@Test func naqpScoring() {
    let log = [rec("W1AW", 14080, exch: "BOB CT"), rec("DL1ABC", 14081, exch: "HANS"), rec("KH6ABC", 14082, exch: "JOE HI"),
               rec("XE1ABC", 14083, exch: "JUAN XE")]
    let t = tally(.naqpRTTY, log)
    #expect(t.points == 3)
    #expect(t.multipliers.total == 3)                        // CT, HI, XE
}

@Test func memberBonuses() {
    let trc = tally(.trcDigi, [rec("DL1ABC", 14080, exch: "001TRC", sent: "001"), rec("W1AW", 14081, exch: "002", sent: "002")])
    #expect(trc.points == 12 && trc.multipliers.total == 3)  // DL + K + member country DL
    let mem = tally(.trcDigi, [rec("DL1ABC", 14080, exch: "TRC", sent: "001 TRC")])
    #expect(mem.points == 1)
    let pro = tally(.proDigi, [rec("OK1ABC", 14080, exch: "M", sent: "001"), rec("DL1ABC", 14081, exch: "", sent: "002")])
    #expect(pro.points == 3 + 2 && pro.multipliers.total == 1)   // own-country prefixes do not count
}

@Test func otherNewContests() {
    let xe = tally(.mexicoRTTY, [rec("XE1ABC", 14080, exch: "JAL"), rec("DL1ABC", 14081, exch: "001")])
    #expect(xe.points == 7 && xe.multipliers.total == 3)
    let rr = tally(.rookieRoundup, [rec("W1AW", 14080, exch: "BOB 25 CT"), rec("K1ABC", 14081, exch: "JIM 99 MA")])
    #expect(rr.points == 3 && rr.multipliers.total == 2)
    let darc = tally(.darcSprint, [rec("DL1ABC", 3580, exch: "B01"), rec("OK1ABC", 3581, exch: "005")])
    #expect(darc.points == 2 && darc.multipliers.total == 3)
    let wrt = tally(.wrt, [rec("W1AW", 14080), rec("W1AW", 7040), rec("DL1ABC", 14081)])
    #expect(wrt.score == 3 * 2)
    let ig = tally(.igryWW, [rec("DL1ABC", 14080, exch: "599 1987"), rec("W1AW", 14081, exch: "1987"), rec("W1AW", 7040, exch: "2001")])
    #expect(ig.score == 3 * 2)
    let ea = tally(.eaRTTY, [rec("EA5ABC", 14080, exch: "MU"), rec("W1AW", 14081, exch: "002")])
    #expect(ea.points == 4 && ea.multipliers.total == 4)
    let yb = tally(.ybDX, [rec("YB1ABC", 14080), rec("DL1ABC", 14081)])
    #expect(yb.points == 12 && yb.multipliers.total == 3)
    let ny = tally(.sartgNewYear, [rec("SM3ABC", 3580), rec("DL1ABC", 3581), rec("OK1ABC", 7040)])
    #expect(ny.score == 9)
    let sprint = tally(.bartgSprint, [rec("DL1ABC", 14080), rec("W1AW", 14081), rec("W1AW", 7040)])
    #expect(sprint.bandMultipliers == 3 && sprint.continents == 2 && sprint.score == 18)
}

@Test func urcTerritoryFromCall() {
    #expect(ContestCatalog.urcTerritory("OK1XOE") == "BHE")
    #expect(ContestCatalog.urcTerritory("OM3ABC") == "SLA")
    #expect(ContestCatalog.urcTerritory("DL1ABC") == nil)     // 17 German territories – fill in by hand
}
