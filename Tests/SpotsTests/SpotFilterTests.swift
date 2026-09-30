// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import QSOLog
import Testing
@testable import Spots

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func s(_ call: String, _ kHz: Double, _ mode: String?, min: Double = 0) -> Spot {
    Spot(frequencyKHz: kHz, call: call, spotter: "OK1XOE", comment: "", time: t0.addingTimeInterval(-min * 60), mode: mode)
}

// Pevný seznam pásem se zaškrtávátky: krátké vlny + 6 m, jediný zdroj (`Bands`).
@Test func filterBandListIsFixedHFAnd6m() {
    #expect(SpotFilter.allBands == ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"])
    #expect(SpotFilter.allBands == Bands.hfAnd6m)
}

private func g(_ m: String?) -> SpotModeGroup { SpotModeGroup.group(for: m) }

// Každý mód, který `SpotParser` umí vyrobit (včetně nil), patří do přesně jedné skupiny.
@Test func modeGroupsCoverEveryParserMode() {
    var hit: [SpotModeGroup: [String]] = [:]
    for m in SpotParser.otherModes.union(["RTTY"]) { hit[g(m), default: []].append(m) }
    #expect(g(nil) == .other)                                       // nerozpoznaný mód
    #expect(g("") == .other)
    #expect(g("RTTY") == .rtty)
    #expect(g("rtty") == .rtty)                                     // nezávisle na velikosti písmen
    #expect(g("CW") == .cw)
    #expect(["PSK", "PSK31", "PSK63", "PSK125"].allSatisfy { g($0) == .psk })
    #expect(["FT8", "FT4", "JT65", "JT9", "Q65", "MSK144", "WSPR", "FSK441"].allSatisfy { g($0) == .digi })
    #expect(["SSB", "USB", "LSB"].allSatisfy { g($0) == .ssb })
    #expect(["FM", "AM", "SSTV", "OLIVIA", "HELL", "MFSK"].allSatisfy { g($0) == .other })
    // žádná skupina nezůstane prázdná (zaškrtávátko, které nic nefiltruje, nemá smysl)
    #expect(Set(hit.keys) == Set(SpotModeGroup.allCases))
    #expect(hit[.other]?.isEmpty == false)                          // FM, AM… spadnou do „ostatní“
}

// Zaškrtnuté = zobrazené: pásmo i skupina módu musí projít.
@Test func filterHidesUncheckedBandsAndModes() {
    let list = [s("A20", 14080, "RTTY"), s("B40", 7040, "RTTY"), s("C20", 14200, "SSB"), s("D20", 14040, "CW")]
    var f = SpotFilter()                                            // výchozí: všechna pásma, jen RTTY
    #expect(f.apply(to: list).map(\.call) == ["B40", "A20"])          // stejný čas → nižší kmitočet dřív
    f.bands = ["20m"]
    #expect(f.apply(to: list).map(\.call) == ["A20"])
    f.modes = [.rtty, .cw]
    #expect(Set(f.apply(to: list).map(\.call)) == ["A20", "D20"])
    f.modes = [.ssb]
    #expect(f.apply(to: list).map(\.call) == ["C20"])
}

// Každá skupina módů má vlastní zaškrtávátko: zaškrtnutá pustí právě svoje spoty (i „ostatní“ bez módu).
@Test func eachModeGroupFiltersItsOwnSpots() {
    let list = [s("R", 14080, "RTTY"), s("C", 14030, "CW"), s("P", 14071, "PSK31"),
                s("F", 14074, "FT8"), s("S", 14200, "SSB"), s("X", 14001, nil), s("M", 14230, "SSTV")]
    for g in SpotModeGroup.allCases {
        let got = Set(SpotFilter(modes: [g]).apply(to: list).map(\.call))
        switch g {
        case .rtty: #expect(got == ["R"])
        case .cw: #expect(got == ["C"])
        case .psk: #expect(got == ["P"])
        case .digi: #expect(got == ["F"])
        case .ssb: #expect(got == ["S"])
        case .other: #expect(got == ["X", "M"])            // neznámý mód i mód bez vlastní skupiny
        }
    }
    #expect(SpotFilter(modes: SpotFilter.allModes).apply(to: list).count == list.count)   // dohromady všechno
}

// Tlačítka Vše / Nic.
@Test func filterAllAndNone() {
    let list = [s("A", 14080, "RTTY"), s("B", 7040, "CW"), s("C", 3700, nil)]
    #expect(SpotFilter.all.apply(to: list).count == 3)
    #expect(SpotFilter(bands: [], modes: SpotFilter.allModes).apply(to: list).isEmpty)
    #expect(SpotFilter(bands: SpotFilter.allBandsSet, modes: []).apply(to: list).isEmpty)
}

// Spot mimo seznam pásem (VHF, neznámé pásmo) nemá zaškrtávátko, proto ho filtr pásem nikdy neschová.
@Test func filterKeepsSpotsOutsideBandList() {
    let vhf = s("OK1VHF", 144_300, "SSB")                            // 2m – bez zaškrtávátka
    let unknown = s("OK1UNK", 5000, "RTTY")                          // mimo všechna pásma → band == nil
    #expect(vhf.band == "2m" && unknown.band == nil)
    let f = SpotFilter(bands: [], modes: SpotFilter.allModes)
    #expect(Set(f.apply(to: [vhf, unknown]).map(\.call)) == ["OK1VHF", "OK1UNK"])
    #expect(SpotFilter(bands: [], modes: [.rtty]).apply(to: [vhf, unknown]).map(\.call) == ["OK1UNK"])  // mód platí
}

// Řazení: nejnovější první, při stejném čase nižší kmitočet dřív.
@Test func filterSortsNewestFirst() {
    let list = [s("OLD", 14080, "RTTY", min: 10), s("NEW2", 14090, "RTTY"), s("NEW1", 14070, "RTTY")]
    #expect(SpotFilter.all.apply(to: list).map(\.call) == ["NEW1", "NEW2", "OLD"])
}

// Seznam spotů používá tentýž filtr.
@Test func spotBookVisibleUsesFilter() {
    var b = SpotBook()
    for x in [s("A", 14080, "RTTY"), s("B", 7040, "CW")] { b.add(x, now: t0, maxAge: 1800) }
    #expect(b.visible(SpotFilter()).map(\.call) == ["A"])
    #expect(b.count == 2)                                            // uloženo je všechno
    #expect(Set(b.visible(SpotFilter.all).map(\.call)) == ["A", "B"])
    #expect(Set(b.visibleModes(SpotFilter(bands: [], modes: [.rtty, .cw])).map(\.call)) == ["A", "B"])
}

// Band mapa: pásmo si vybírá okno (nebo rig), proto se z filtru uplatní jen skupiny módů.
@Test func bandMapFilterIgnoresBandCheckboxes() {
    let list = [s("A", 14080, "RTTY"), s("B", 14090, "CW"), s("C", 7040, "RTTY")]
    let f = SpotFilter(bands: [], modes: [.rtty])                    // uživatel odškrtl všechna pásma
    #expect(BandMapFilter.spots(list, band: "20m", filter: f, maxAgeMinutes: 30, now: t0).map(\.call) == ["A"])
    let f2 = SpotFilter(bands: ["40m"], modes: SpotFilter.allModes)
    #expect(Set(BandMapFilter.spots(list, band: "20m", filter: f2, maxAgeMinutes: 30, now: t0).map(\.call)) == ["A", "B"])
}
