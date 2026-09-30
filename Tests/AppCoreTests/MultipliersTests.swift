import Foundation
import Testing
import DXCC
import QSOLog
import Settings
@testable import AppCore

private let db = CountryDB.shared!
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func rec(_ call: String, _ khz: Double?, exch: String? = nil, min: Double = 1) -> QSORecord {
    var r = QSORecord(call: call, timeOn: t0.addingTimeInterval(min * 60))
    r.frequency = khz.map { $0 * 1000 }; r.exchangeRcvd = exch
    r.cqZone = db.lookup(call)?.cqZone
    return r
}
private func calc(_ p: ContestPreset, own: String? = nil) -> MultiplierCalculator {
    MultiplierCalculator(rule: .rule(for: p, ownCountry: own), countries: db)
}
private func values(_ t: MultiplierTally, _ k: MultiplierKind, _ band: String? = nil) -> [String] {
    t.worked(k, band: band).sorted()
}

// MARK: WPX prefix

@Test(arguments: [
    ("N8BJQ", "N8"), ("W8ABC", "W8"), ("WD8ABC", "WD8"), ("HG1S", "HG1"), ("HG19ABC", "HG19"), ("KC2XYZ", "KC2"),
    ("OE2ABC", "OE2"), ("OE25ABC", "OE25"), ("LY1000A", "LY1000"), ("PA/N8BJQ", "PA0"), ("XEFTJW", "XE0"),
    ("OK1XOE/P", "OK1"), ("OK1XOE/M", "OK1"), ("DL1ABC/MM", "DL1"), ("OK1XOE/QRP", "OK1"), ("OK1XOE/AM", "OK1"),
    ("W1ABC/A", "W1"), ("JA1ABC/J", "JA1"), ("KH6/W1ABC", "KH6"), ("W1ABC/KH6", "KH6"), ("DL/OK1ABC", "DL0"),
    ("OK1ABC/DL", "DL0"), ("DL/OK1ABC/P", "DL0"), ("4U1ITU", "4U1"), ("3D2AG", "3D2"), ("9A1A", "9A1"),
    ("2E0ABC", "2E0"), ("E73A", "E73"), ("VE3/W1A", "VE3"), ("W1A/VE3", "VE3"), ("M/DL1ABC", "M0"),
    ("VP2E/K1ABC", "VP2"), ("ok1xoe", "OK1"), (" S57DX ", "S57"), ("W1ABC/3", "W3"), ("OK1ABC/9/P", "OK9"),
    ("YB0ABC1", "YB0"), ("F/OK1ABC", "F0"), ("GB70ABC", "GB70"), ("TM2023X", "TM2023"),
])
func wpxPrefix(call: String, prefix: String) {
    #expect(WPX.prefix(call) == prefix)
}

@Test func wpxPrefixInvalid() {
    #expect(WPX.prefix("") == nil)
    #expect(WPX.prefix("/") == nil)
    #expect(WPX.prefix("??") == nil)
}

// MARK: Rules

@Test func everyPresetHasRuleAndSource() {
    for p in ContestPreset.allCases {
        let r = MultiplierRule.rule(for: p)
        #expect(r.preset == p && !r.source.isEmpty && !r.note.isEmpty)
        #expect(r.hasMultipliers == (p != .makrothen))
    }
}

@Test func outsideContestNoRule() {
    var c = ContestSettings.preset(.cqwwRTTY, year: 2026)
    #expect(MultiplierRule.rule(for: c, ownCountry: "OK")?.preset == .cqwwRTTY)
    c.enabled = false
    #expect(MultiplierRule.rule(for: c, ownCountry: "OK") == nil)
    var custom = ContestSettings(); custom.enabled = true; custom.name = "MUJ-ZAVOD"
    #expect(MultiplierRule.rule(for: custom, ownCountry: "OK") == nil)
}

// MARK: Computation for the individual contests

@Test func arrlRoundupOncePerContestWithoutUSVE() {
    let c = calc(.arrlRoundup)
    let log = [rec("W1AW", 14080, exch: "CT"), rec("K2ABC", 7040, exch: "NY"), rec("W1XYZ", 7040, exch: "CT"),
               rec("VE3ABC", 14080, exch: "ON"), rec("VO1AA", 7040, exch: "NF"), rec("DL1ABC", 14080, exch: "001"),
               rec("DL2XYZ", 7040, exch: "005"), rec("KH6ABC", 14080, exch: "HI"), rec("KL7ABC", 14080, exch: "AK")]
    let t = c.tally(records: log, since: t0)
    #expect(values(t, .dxcc) == ["DL", "KH6", "KL"])             // without K and VE (Alaska = KL in cty.dat)
    #expect(values(t, .usState) == ["CT", "NY"])                   // not HI/AK
    #expect(values(t, .veProvince) == ["NL", "ON"])
    #expect(t.total == 7 && t.bands.isEmpty)
    #expect(t.missing(.usState, band: nil)?.count == 47)
    #expect(t.newHits(c.hits(call: "DL5ZZ", exchange: "7"), band: "20m").isEmpty)
    #expect(t.newHits(c.hits(call: "W6ABC", exchange: "CA"), band: "20m").hits == [MultiplierHit(.usState, "CA")])
}

@Test func wpxOncePerContest() {
    let c = calc(.cqwpxRTTY)
    let t = c.tally(records: [rec("OK1XOE", 14080), rec("OK1ABC", 7040), rec("OK2ABC", 7040), rec("PA/N8BJQ", 21080)], since: t0)
    #expect(values(t, .wpxPrefix) == ["OK1", "OK2", "PA0"])
    #expect(t.total == 3)
    #expect(t.newHits(c.hits(call: "OK1ZZZ", exchange: nil), band: "80m").isEmpty)
    #expect(t.newHits(c.hits(call: "OK3ZZZ", exchange: nil), band: "80m").text == "OK3")
}

@Test func bartgPerBandAreasAndContinentsOnce() {
    let c = calc(.bartgHF)
    let log = [rec("W1AW", 14080), rec("K1ABC", 7040), rec("W6XYZ", 14080), rec("JA7ABC", 14080), rec("DL1ABC", 14080),
               rec("DL1ABC", 7040), rec("VK2ABC", 21080)]
    let t = c.tally(records: log, since: t0)
    #expect(values(t, .dxcc, "20m") == ["DL", "JA", "K"])
    #expect(values(t, .dxcc, "40m") == ["DL", "K"])
    #expect(values(t, .callArea, "20m") == ["JA7", "W1", "W6"])
    #expect(values(t, .callArea, "40m") == ["W1"])
    #expect(values(t, .continent) == ["AS", "EU", "NA", "OC"])
    #expect(t.count(band: "20m") == 6 && t.count(band: "40m") == 3 && t.count(band: "15m") == 2)
    #expect(t.total == 6 + 3 + 2 + 4)
    #expect(t.bands == ["40m", "20m", "15m"])
    #expect(t.missing(.continent, band: nil) == ["AF", "SA"])
    let n = t.newHits(c.hits(call: "W1XYZ", exchange: nil), band: "15m")
    #expect(n.hits == [MultiplierHit(.dxcc, "K"), MultiplierHit(.callArea, "W1")] && n.band == "15m")
}

@Test func sartgCountsCountryAndArea() {
    let c = calc(.sartgRTTY)
    let t = c.tally(records: [rec("VE3ABC", 14080), rec("VE7ABC", 14080), rec("OH1ABC", 14080)], since: t0)
    #expect(values(t, .dxcc, "20m") == ["OH", "VE"])
    #expect(values(t, .callArea, "20m") == ["VE3", "VE7"])
}

@Test func cqwwZonesCountriesAndQTHPerBand() {
    let c = calc(.cqwwRTTY)
    let log = [rec("W1AW", 14080, exch: "05 CT"), rec("K6ABC", 14080, exch: "03 CA"), rec("VE3ABC", 7040, exch: "4 ON"),
               rec("IT9ABC", 14080, exch: "15"), rec("I1ABC", 14080, exch: "15"), rec("KH6ABC", 14080, exch: "31 HI"),
               rec("W1AW", 7040, exch: "05 CT")]
    let t = c.tally(records: log, since: t0)
    #expect(values(t, .cqZone, "20m") == ["15", "3", "31", "5"])
    #expect(values(t, .dxcc, "20m") == ["I", "IT9", "K", "KH6"])      // WAE list: Sicily counts separately; the USA is an entity
    #expect(values(t, .usState, "20m") == ["CA", "CT"])                 // HI only as an entity
    #expect(values(t, .veProvince, "40m") == ["ON"])
    #expect(values(t, .usState, "40m") == ["CT"])
    #expect(t.missing(.cqZone, band: "20m")?.count == 36)
    let n = t.newHits(c.hits(call: "DL1ABC", exchange: "14"), band: "20m")
    #expect(n.hits == [MultiplierHit(.cqZone, "14"), MultiplierHit(.dxcc, "DL")])
    #expect(n.text == "20m: Z14, DL")
    // zone without an exchange, from DXCC
    #expect(c.hits(call: "DL1ABC", exchange: nil).contains(MultiplierHit(.cqZone, "14")))
}

@Test func makrothenHasNoMultipliers() {
    let c = calc(.makrothen)
    let t = c.tally(records: [rec("DL1ABC", 14080, exch: "JO62")], since: t0)
    #expect(t.total == 0 && c.hits(call: "DL1ABC", exchange: nil).isEmpty)
    #expect(t.newHits(c.hits(call: "OK1ABC", exchange: nil), band: "20m").isEmpty)
}

@Test func jartsAreasInsteadOfJAWVEVK() {
    let c = calc(.jartsRTTY)
    let log = [rec("JA1ABC", 14080), rec("JR4XYZ", 14080), rec("7M4ABC", 14080), rec("W1AW", 14080), rec("JA/OK1ABC", 14080),
               rec("DL1ABC", 14080), rec("JD1ABC", 14080)]
    let t = c.tally(records: log, since: t0)
    #expect(values(t, .dxcc, "20m").contains("DL") && values(t, .dxcc, "20m").count == 2)   // DL + JD1
    #expect(!values(t, .dxcc, "20m").contains("JA") && !values(t, .dxcc, "20m").contains("K"))
    #expect(values(t, .callArea, "20m") == ["JA0", "JA1", "JA4", "W1"])
}

@Test func waeCountsAllWithAreasAndBandWeights() {
    let c = calc(.waeRTTY)
    let log = [rec("W1AW", 3580), rec("K1ABC", 3580), rec("W6ABC", 3580), rec("DL1ABC", 3580), rec("OK1ABC", 7040),
               rec("IT9ABC", 7040), rec("VE1ABC", 14080), rec("VO1ABC", 14080), rec("ZL2ABC", 14080), rec("ZL6ABC", 14080),
               rec("RA9ABC", 14080), rec("UA0ABC", 14080), rec("JA1ABC", 21080)]
    let t = c.tally(records: log, since: t0)
    #expect(values(t, .waeCountry, "80m") == ["DL", "W1", "W6"])        // everyone counts both EU and non-EU (RTTY §12)
    #expect(values(t, .waeCountry, "40m") == ["IT9", "OK"])
    #expect(values(t, .waeCountry, "20m") == ["RA0", "RA9", "VE1", "ZL2", "ZL6"])
    #expect(values(t, .waeCountry, "15m") == ["JA1"])
    #expect(t.total == 3 + 2 + 5 + 1)
    #expect(t.weightedTotal == 3 * 4 + 2 * 3 + 5 * 2 + 1 * 2)
}

@Test func okDXDependsOnOwnCountry() {
    let log = [rec("OK1ABC", 14080, exch: "15"), rec("OK2XYZ", 14080, exch: "15"), rec("DL1ABC", 14080, exch: "14"),
               rec("OK1ABC", 7040, exch: "15")]
    let dx = calc(.okDXRTTY, own: "DL").tally(records: log, since: t0)
    #expect(values(dx, .dxcc, "20m") == ["DL", "OK"])
    #expect(values(dx, .okStation, "20m") == ["OK1ABC", "OK2XYZ"])
    #expect(values(dx, .okStation, "40m") == ["OK1ABC"])
    #expect(dx.total == 4 + 2)
    let ok = calc(.okDXRTTY, own: "OK").tally(records: log, since: t0)
    #expect(ok.rule.component(.okStation) == nil)
    #expect(values(ok, .dxcc, "20m") == ["DL", "OK"] && ok.total == 3)
}

@Test func onlyRecordsSinceContestStart() {
    let c = calc(.cqwpxRTTY)
    let old = rec("OK5ABC", 14080, min: -10)
    let t = c.tally(records: [old, rec("OK1ABC", 14080)], since: t0)
    #expect(values(t, .wpxPrefix) == ["OK1"])
}

@Test func perBandNewMultNeedsBand() {
    let c = calc(.cqwwRTTY)
    let t = c.tally(records: [rec("DL1ABC", 14080, exch: "14")], since: t0)
    #expect(t.newHits(c.hits(call: "DL2ABC", exchange: "14"), band: "20m").isEmpty)
    #expect(t.newHits(c.hits(call: "DL2ABC", exchange: "14"), band: "40m").hits.count == 2)
    #expect(t.newHits(c.hits(call: "DL2ABC", exchange: "14"), band: nil).isEmpty)   // unknown band
}
