// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import QSOLog
import Testing
@testable import Spots

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func s(_ call: String, _ kHz: Double, _ mode: String?, min: Double = 0) -> Spot {
    Spot(frequencyKHz: kHz, call: call, spotter: "OK1XOE", comment: "", time: t0.addingTimeInterval(-min * 60), mode: mode)
}

// The fixed list of bands with check boxes: the HF bands + 6 m, from a single source (`Bands`).
@Test func filterBandListIsFixedHFAnd6m() {
    #expect(SpotFilter.allBands == ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"])
    #expect(SpotFilter.allBands == Bands.hfAnd6m)
}

// The check box rows in the "Band filter" window: the whole fixed list, in order, nothing missing or repeated.
@Test func bandRowsCoverWholeBandList() {
    for perRow in 1...12 {
        let rows = SpotFilter.bandRows(perRow: perRow)
        #expect(rows.flatMap(\.self) == SpotFilter.allBands)
        #expect(rows.allSatisfy { !$0.isEmpty && $0.count <= perRow })
        #expect(rows.count == (SpotFilter.allBands.count + perRow - 1) / perRow)
    }
    #expect(SpotFilter.bandRows(perRow: 4) == [["160m", "80m", "60m", "40m"], ["30m", "20m", "17m", "15m"], ["12m", "10m", "6m"]])
    #expect(SpotFilter.bandRows(perRow: 0) == [SpotFilter.allBands])     // a nonsensical width = a single row
}

private func g(_ m: String?) -> SpotModeGroup { SpotModeGroup.group(for: m) }

// Every mode that `SpotParser` can produce (including nil) belongs to exactly one group.
@Test func modeGroupsCoverEveryParserMode() {
    var hit: [SpotModeGroup: [String]] = [:]
    for m in SpotParser.otherModes.union(["RTTY"]) { hit[g(m), default: []].append(m) }
    #expect(g(nil) == .other)                                       // an unrecognised mode
    #expect(g("") == .other)
    #expect(g("RTTY") == .rtty)
    #expect(g("rtty") == .rtty)                                     // regardless of the case
    #expect(g("CW") == .cw)
    #expect(["PSK", "PSK31", "PSK63", "PSK125"].allSatisfy { g($0) == .psk })
    #expect(["FT8", "FT4", "JT65", "JT9", "Q65", "MSK144", "WSPR", "FSK441"].allSatisfy { g($0) == .digi })
    #expect(["SSB", "USB", "LSB"].allSatisfy { g($0) == .ssb })
    #expect(["FM", "AM", "SSTV", "OLIVIA", "HELL", "MFSK"].allSatisfy { g($0) == .other })
    // no group is left empty (a check box that filters nothing makes no sense)
    #expect(Set(hit.keys) == Set(SpotModeGroup.allCases))
    #expect(hit[.other]?.isEmpty == false)                          // FM, AM… fall into "other"
}

// Checked = displayed: both the band and the mode group have to pass.
@Test func filterHidesUncheckedBandsAndModes() {
    let list = [s("A20", 14080, "RTTY"), s("B40", 7040, "RTTY"), s("C20", 14200, "SSB"), s("D20", 14040, "CW")]
    var f = SpotFilter()                                            // the default: all bands, RTTY only
    #expect(f.apply(to: list).map(\.call) == ["B40", "A20"])          // the same time → the lower frequency first
    f.bands = ["20m"]
    #expect(f.apply(to: list).map(\.call) == ["A20"])
    f.modes = [.rtty, .cw]
    #expect(Set(f.apply(to: list).map(\.call)) == ["A20", "D20"])
    f.modes = [.ssb]
    #expect(f.apply(to: list).map(\.call) == ["C20"])
}

// Every mode group has its own check box: when checked it passes exactly its own spots (including "other" with no mode).
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
        case .other: #expect(got == ["X", "M"])            // an unknown mode and a mode with no group of its own
        }
    }
    #expect(SpotFilter(modes: SpotFilter.allModes).apply(to: list).count == list.count)   // everything together
}

// The All / None buttons.
@Test func filterAllAndNone() {
    let list = [s("A", 14080, "RTTY"), s("B", 7040, "CW"), s("C", 3700, nil)]
    #expect(SpotFilter.all.apply(to: list).count == 3)
    #expect(SpotFilter(bands: [], modes: SpotFilter.allModes).apply(to: list).isEmpty)
    #expect(SpotFilter(bands: SpotFilter.allBandsSet, modes: []).apply(to: list).isEmpty)
}

// A spot outside the fixed list of bands (630 m, VHF and up, an unknown band) belongs to the "other" check box:
// checked it is displayed (the default state), unchecked it is hidden – so "None" empties the table completely.
@Test func otherBandsCheckboxCoversSpotsOutsideBandList() {
    let vhf = s("OK1VHF", 144_300, "SSB")                            // 2m – outside the fixed list
    let lf = s("OK1LF", 475, "RTTY")                                 // 630m – below the HF bands
    let unknown = s("OK1UNK", 5000, "RTTY")                          // outside every band → band == nil
    #expect(vhf.band == "2m" && lf.band == "630m" && unknown.band == nil)
    let list = [vhf, lf, unknown, s("A20", 14080, "RTTY")]
    #expect(SpotFilter().otherBands)                                                     // the default: checked
    #expect(SpotFilter.all.apply(to: list).count == 4)                                   // "All" passes "other" as well
    #expect(SpotFilter(bands: [], modes: SpotFilter.allModes, otherBands: false).apply(to: list).isEmpty)  // "None"
    let onlyOther = SpotFilter(bands: [], modes: SpotFilter.allModes, otherBands: true)
    #expect(Set(onlyOther.apply(to: list).map(\.call)) == ["OK1VHF", "OK1LF", "OK1UNK"])
    #expect(SpotFilter(bands: [], modes: [.rtty], otherBands: true).apply(to: list).map(\.call) == ["OK1LF", "OK1UNK"])  // the mode applies
    #expect(SpotFilter(bands: SpotFilter.allBandsSet, modes: SpotFilter.allModes, otherBands: false)
        .apply(to: list).map(\.call) == ["A20"])                                          // unchecking "other" hides it
}

// Every spot falls under exactly one band check box (just like the mode groups): a band from the fixed list, otherwise "other".
@Test func bandCheckboxesCoverEverySpot() {
    // the frequencies (kHz) of every band in the `Bands` table + frequencies outside every band
    let kHz: [Double] = [137.5, 475, 1840, 3580, 5357, 7040, 10140, 14080, 18100, 21080, 24920, 28080,
                         50300, 70200, 144_300, 223_500, 432_100, 5000, 1000, 500_000]
    var outside: Set<String?> = []
    for f in kHz {
        let x = s("TEST", f, "RTTY")
        let inList = x.band.map(SpotFilter.allBandsSet.contains) ?? false
        if !inList { outside.insert(x.band) }
        #expect(SpotFilter.all.matchesBand(x))                                           // "All" passes every spot
        #expect(!SpotFilter(bands: [], modes: SpotFilter.allModes, otherBands: false).matchesBand(x))  // "None" passes none
        // exactly one check box: either its own band or "other" – and the other one does not pass the spot
        #expect(SpotFilter(bands: inList ? [x.band!] : [], modes: SpotFilter.allModes, otherBands: !inList).matchesBand(x))
        #expect(!SpotFilter(bands: inList ? [] : SpotFilter.allBandsSet, modes: SpotFilter.allModes, otherBands: inList).matchesBand(x))
    }
    #expect(outside == ["2190m", "630m", "4m", "2m", "1.25m", "70cm", nil])               // what "other" covers
}

// Sorting: the newest first, and for the same time the lower frequency first.
@Test func filterSortsNewestFirst() {
    let list = [s("OLD", 14080, "RTTY", min: 10), s("NEW2", 14090, "RTTY"), s("NEW1", 14070, "RTTY")]
    #expect(SpotFilter.all.apply(to: list).map(\.call) == ["NEW1", "NEW2", "OLD"])
}

// The spot list uses the very same filter.
@Test func spotBookVisibleUsesFilter() {
    var b = SpotBook()
    for x in [s("A", 14080, "RTTY"), s("B", 7040, "CW")] { b.add(x, now: t0, maxAge: 1800) }
    #expect(b.visible(SpotFilter()).map(\.call) == ["A"])
    #expect(b.count == 2)                                            // everything is stored
    #expect(Set(b.visible(SpotFilter.all).map(\.call)) == ["A", "B"])
    #expect(Set(b.visibleModes(SpotFilter(bands: [], modes: [.rtty, .cw])).map(\.call)) == ["A", "B"])
}

// The band map: the band is chosen by the window (or the rig), so only the mode groups from the filter apply.
@Test func bandMapFilterIgnoresBandCheckboxes() {
    let list = [s("A", 14080, "RTTY"), s("B", 14090, "CW"), s("C", 7040, "RTTY")]
    let f = SpotFilter(bands: [], modes: [.rtty])                    // the user unchecked all the bands
    #expect(BandMapFilter.spots(list, band: "20m", filter: f, maxAgeMinutes: 30, now: t0).map(\.call) == ["A"])
    let f2 = SpotFilter(bands: ["40m"], modes: SpotFilter.allModes)
    #expect(Set(BandMapFilter.spots(list, band: "20m", filter: f2, maxAgeMinutes: 30, now: t0).map(\.call)) == ["A", "B"])
}
