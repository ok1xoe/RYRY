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

// Řádky zaškrtávátek v okně „Filtr pásem“: celý pevný seznam, v pořadí, nic nevypadne ani se neopakuje.
@Test func bandRowsCoverWholeBandList() {
    for perRow in 1...12 {
        let rows = SpotFilter.bandRows(perRow: perRow)
        #expect(rows.flatMap(\.self) == SpotFilter.allBands)
        #expect(rows.allSatisfy { !$0.isEmpty && $0.count <= perRow })
        #expect(rows.count == (SpotFilter.allBands.count + perRow - 1) / perRow)
    }
    #expect(SpotFilter.bandRows(perRow: 4) == [["160m", "80m", "60m", "40m"], ["30m", "20m", "17m", "15m"], ["12m", "10m", "6m"]])
    #expect(SpotFilter.bandRows(perRow: 0) == [SpotFilter.allBands])     // nesmyslná šířka = jeden řádek
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

// Spot mimo pevný seznam pásem (630 m, VHF a výš, neznámé pásmo) patří pod zaškrtávátko „ostatní“:
// zaškrtnuté ho zobrazí (výchozí stav), odškrtnuté schová – „Nic“ tedy vyprázdní tabulku úplně.
@Test func otherBandsCheckboxCoversSpotsOutsideBandList() {
    let vhf = s("OK1VHF", 144_300, "SSB")                            // 2m – mimo pevný seznam
    let lf = s("OK1LF", 475, "RTTY")                                 // 630m – pod krátkými vlnami
    let unknown = s("OK1UNK", 5000, "RTTY")                          // mimo všechna pásma → band == nil
    #expect(vhf.band == "2m" && lf.band == "630m" && unknown.band == nil)
    let list = [vhf, lf, unknown, s("A20", 14080, "RTTY")]
    #expect(SpotFilter().otherBands)                                                     // výchozí: zaškrtnuto
    #expect(SpotFilter.all.apply(to: list).count == 4)                                   // „Vše“ pustí i „ostatní“
    #expect(SpotFilter(bands: [], modes: SpotFilter.allModes, otherBands: false).apply(to: list).isEmpty)  // „Nic“
    let onlyOther = SpotFilter(bands: [], modes: SpotFilter.allModes, otherBands: true)
    #expect(Set(onlyOther.apply(to: list).map(\.call)) == ["OK1VHF", "OK1LF", "OK1UNK"])
    #expect(SpotFilter(bands: [], modes: [.rtty], otherBands: true).apply(to: list).map(\.call) == ["OK1LF", "OK1UNK"])  // mód platí
    #expect(SpotFilter(bands: SpotFilter.allBandsSet, modes: SpotFilter.allModes, otherBands: false)
        .apply(to: list).map(\.call) == ["A20"])                                          // odškrtnuté „ostatní“ schová
}

// Každý spot padne právě pod jedno zaškrtávátko pásem (jako skupiny módů): pásmo z pevného seznamu, jinak „ostatní“.
@Test func bandCheckboxesCoverEverySpot() {
    // kmitočty (kHz) všech pásem tabulky `Bands` + kmitočty mimo všechna pásma
    let kHz: [Double] = [137.5, 475, 1840, 3580, 5357, 7040, 10140, 14080, 18100, 21080, 24920, 28080,
                         50300, 70200, 144_300, 223_500, 432_100, 5000, 1000, 500_000]
    var outside: Set<String?> = []
    for f in kHz {
        let x = s("TEST", f, "RTTY")
        let inList = x.band.map(SpotFilter.allBandsSet.contains) ?? false
        if !inList { outside.insert(x.band) }
        #expect(SpotFilter.all.matchesBand(x))                                           // „Vše“ pustí každý spot
        #expect(!SpotFilter(bands: [], modes: SpotFilter.allModes, otherBands: false).matchesBand(x))  // „Nic“ žádný
        // právě jedno zaškrtávátko: vlastní pásmo, nebo „ostatní“ – a to druhé spot nepustí
        #expect(SpotFilter(bands: inList ? [x.band!] : [], modes: SpotFilter.allModes, otherBands: !inList).matchesBand(x))
        #expect(!SpotFilter(bands: inList ? [] : SpotFilter.allBandsSet, modes: SpotFilter.allModes, otherBands: inList).matchesBand(x))
    }
    #expect(outside == ["2190m", "630m", "4m", "2m", "1.25m", "70cm", nil])               // co pokrývá „ostatní“
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
