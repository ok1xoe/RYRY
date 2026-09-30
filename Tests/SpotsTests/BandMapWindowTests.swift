import Foundation
import Testing
import QSOLog
@testable import Spots

private func sp(_ call: String, _ kHz: Double, age: TimeInterval = 0, now: Date, mode: String? = "RTTY") -> Spot {
    Spot(frequencyKHz: kHz, call: call, spotter: "X", comment: "", time: now.addingTimeInterval(-age), mode: mode)
}

@Test func rttyBandPlanTable() {
    #expect(RTTYBandPlan.segment(for: "20m")?.lowKHz == 14070)
    #expect(RTTYBandPlan.segment(for: "20m")?.highKHz == 14100)
    #expect(RTTYBandPlan.segment(for: "40m")?.lowKHz == 7030)
    #expect(RTTYBandPlan.segment(for: "40m")?.highKHz == 7060)
    #expect(RTTYBandPlan.segment(for: "6m") == nil)
    #expect(RTTYBandPlan.segment(for: nil) == nil)
    // shodné se segmenty parseru spotů
    for s in RTTYBandPlan.segments { #expect(SpotParser.rttySegments.contains(s.lowKHz...s.highKHz), "\(s.band)") }
    #expect(RTTYBandPlan.bands.first == "80m")
    for s in RTTYBandPlan.segments { #expect(s.lowKHz < s.highKHz) }
}

@Test func bandSelectionPrefersChoiceThenRigThenManual() {
    #expect(RTTYBandPlan.selectBand(choice: "40m", rigHz: 14_080_000, manualHz: 21_080_000) == "40m")
    #expect(RTTYBandPlan.selectBand(choice: nil, rigHz: 14_080_000, manualHz: 21_080_000) == "20m")
    #expect(RTTYBandPlan.selectBand(choice: nil, rigHz: nil, manualHz: 21_080_000) == "15m")
    #expect(RTTYBandPlan.selectBand(choice: nil, rigHz: nil, manualHz: nil) == nil)
    // rig na pásmu bez RTTY tabulky (6 m) → přeskočí na ruční frekvenci
    #expect(RTTYBandPlan.selectBand(choice: nil, rigHz: 50_100_000, manualHz: 7_040_000) == "40m")
    // neznámá volba se ignoruje
    #expect(RTTYBandPlan.selectBand(choice: "6m", rigHz: 14_080_000, manualHz: nil) == "20m")
}

@Test func bandSelectionFallsBackToSpotsThenDefault() {
    // bez rigu a bez ruční frekvence: pásmo s nejvíce spoty, aby mapa nezůstala prázdná
    #expect(RTTYBandPlan.selectBand(choice: nil, rigHz: nil, manualHz: nil, spotBands: ["15m", "40m"]) == "15m")
    // pásmo bez RTTY segmentu se přeskočí
    #expect(RTTYBandPlan.selectBand(choice: nil, rigHz: nil, manualHz: nil, spotBands: ["6m", "40m"]) == "40m")
    // žádné spoty → výchozí pásmo
    #expect(RTTYBandPlan.selectBand(choice: nil, rigHz: nil, manualHz: nil, spotBands: []) == RTTYBandPlan.defaultBand)
    #expect(RTTYBandPlan.segment(for: RTTYBandPlan.defaultBand) != nil)
    // rig a ruční frekvence mají přednost před spoty
    #expect(RTTYBandPlan.selectBand(choice: nil, rigHz: 7_040_000, manualHz: nil, spotBands: ["15m"]) == "40m")
    #expect(RTTYBandPlan.selectBand(choice: "10m", rigHz: nil, manualHz: nil, spotBands: ["15m"]) == "10m")
}

@Test func scaleResetsToWholeSegment() {
    var s = BandScale(segment: RTTYBandPlan.segment(for: "20m")!)
    s.zoom(by: 0.2, around: 14_075)
    #expect(s.span < 20)
    s.reset()
    #expect(s.visibleLow == 14_070 && s.visibleHigh == 14_100)
}

@Test func scalePansAndClampsToSegment() {
    var s = BandScale(segment: RTTYBandPlan.segment(for: "20m")!)
    s.zoom(by: 0.5, around: 14_085)                       // rozsah 15 kHz kolem středu
    let span = s.span
    s.pan(by: 3)
    #expect(abs(s.span - span) < 1e-9 && s.visibleLow > 14_070)
    s.pan(by: 1_000)                                      // nad horní okraj → ořízne se
    #expect(s.visibleHigh == 14_100 && abs(s.span - span) < 1e-9)
    s.pan(by: -1_000)
    #expect(s.visibleLow == 14_070 && abs(s.span - span) < 1e-9)
}

@Test func scaleConvertsFrequencyAndY() {
    let s = BandScale(segment: RTTYBandPlan.segment(for: "20m")!)
    #expect(s.visibleLow == 14070 && s.visibleHigh == 14100)
    #expect(s.y(forKHz: 14100, height: 300) == 0)          // vysoká frekvence nahoře
    #expect(s.y(forKHz: 14070, height: 300) == 300)
    #expect(abs(s.y(forKHz: 14085, height: 300) - 150) < 1e-9)
    #expect(abs(s.kHz(forY: 75, height: 300) - 14092.5) < 1e-9)
    let f = 14081.3
    #expect(abs(s.kHz(forY: s.y(forKHz: f, height: 480), height: 480) - f) < 1e-9)
    #expect(s.contains(kHz: 14070) && !s.contains(kHz: 14100.1))
}

@Test func scaleZoomAndCenter() {
    var s = BandScale(segment: RTTYBandPlan.segment(for: "20m")!)
    s.zoom(by: 0.5, around: 14080)
    #expect(abs((s.visibleHigh - s.visibleLow) - 15) < 1e-9)
    #expect(s.visibleLow <= 14080 && s.visibleHigh >= 14080)
    s.zoom(by: 0.5, around: 14071)                          // u okraje: nevyjede z pásma
    #expect(s.visibleLow >= 14070)
    s.center(on: 14099)
    #expect(s.visibleHigh <= 14100 && s.visibleLow >= 14070)
    for _ in 0..<20 { s.zoom(by: 0.5, around: 14090) }
    #expect(abs((s.visibleHigh - s.visibleLow) - BandScale.minSpanKHz) < 1e-9)
    for _ in 0..<20 { s.zoom(by: 2, around: 14090) }
    #expect(s.visibleLow == 14070 && s.visibleHigh == 14100)
    s.zoom(by: 0.25, around: nil); s.center(on: 14085)
    #expect(abs((s.visibleLow + s.visibleHigh) / 2 - 14085) < 1e-9)
}

@Test func spreadKeepsMinimumGap() {
    let out = BandMapLayout.spread([100, 102, 103, 300], minGap: 14, height: 400)
    #expect(out.count == 4)
    for i in 1..<3 { #expect(out[i] - out[i - 1] >= 14 - 1e-9) }
    #expect(out[3] == 300)
    #expect(out[0] <= 100 + 1e-9)                            // skupina se rozjede kolem původní polohy
    // pořadí vstupu se zachová (výstup po indexech)
    let o2 = BandMapLayout.spread([200, 50], minGap: 14, height: 400)
    #expect(o2 == [200, 50])
    #expect(BandMapLayout.spread([], minGap: 14, height: 100).isEmpty)
}

@Test func spreadStaysInsideHeight() {
    let out = BandMapLayout.spread([1, 2, 3, 398, 399, 400], minGap: 14, height: 400)
    #expect(out.min()! >= 0 && out.max()! <= 400)
    let sorted = out.sorted()
    for i in 1..<sorted.count { #expect(sorted[i] - sorted[i - 1] >= 14 - 1e-9) }
    // příliš mnoho položek: mezera se zmenší, ale zůstane v rozsahu
    let many = BandMapLayout.spread(Array(repeating: 50, count: 40), minGap: 14, height: 100)
    #expect(many.min()! >= 0 && many.max()! <= 100)
    let sm = many.sorted(); for i in 1..<sm.count { #expect(sm[i] >= sm[i - 1]) }
}

@Test func spotFilterByBandAndAge() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let spots = [sp("A1", 14080, age: 60, now: now), sp("B2", 14085, age: 40 * 60, now: now),
                 sp("C3", 7040, now: now), sp("D4", 14090, age: 10 * 60, now: now, mode: "CW")]
    let r = BandMapFilter.spots(spots, band: "20m", rttyOnly: true, maxAgeMinutes: 30, now: now)
    #expect(r.map(\.call) == ["A1"])
    let r2 = BandMapFilter.spots(spots, band: "20m", rttyOnly: false, maxAgeMinutes: 60, now: now)
    #expect(Set(r2.map(\.call)) == ["A1", "B2", "D4"])
    #expect(BandMapFilter.spots(spots, band: "40m", rttyOnly: true, maxAgeMinutes: 30, now: now).map(\.call) == ["C3"])
    #expect(BandMapFilter.ageMinutes(of: spots[0], now: now) == 1)
    #expect(BandMapFilter.ageMinutes(of: sp("Z", 1, age: -30, now: now), now: now) == 0)   // hodiny do budoucnosti
}

@Test func loggedFilterByBandAndAge() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func rec(_ c: String, _ hz: Double?, age: TimeInterval) -> QSORecord {
        var r = QSORecord(call: c, timeOn: now.addingTimeInterval(-age)); r.frequency = hz; return r
    }
    let recs = [rec("OK1A", 14_081_000, age: 5 * 60), rec("OK2B", 14_082_000, age: 90 * 60),
                rec("OK3C", 7_040_000, age: 60), rec("OK4D", nil, age: 60)]
    #expect(BandMapFilter.logged(recs, band: "20m", minutes: 60, now: now).map(\.call) == ["OK1A"])
    #expect(BandMapFilter.logged(recs, band: "20m", minutes: 120, now: now).count == 2)
    #expect(BandMapFilter.logged(recs, band: "20m", minutes: 0, now: now).isEmpty)
}
