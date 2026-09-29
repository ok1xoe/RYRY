import Foundation
import Testing
import QSOLog
import RigControl
import Settings
import Spots
import TestSupport
@testable import AppUI

private func bmSpot(_ call: String, _ kHz: Double, age: TimeInterval = 0) -> Spot {
    Spot(frequencyKHz: kHz, call: call, spotter: "W3LPL-#", comment: "RTTY", time: Date().addingTimeInterval(-age), mode: "RTTY", source: .rbn)
}

private func bmRecord(_ call: String, mode: String = "RTTY", at: Date = Date()) -> QSORecord {
    var r = QSORecord(call: call, timeOn: at, mode: mode)
    r.frequency = 14_080_000                              // 20m
    return r
}

@Test func bandMapFiltersToDisplayedRange() {
    let spots = [bmSpot("DL1ABC", 14080.5), bmSpot("OK2XYZ", 14082.0), bmSpot("F5AAA", 14090.0), bmSpot("G3BBB", 14079.0)]
    // LSB, dial 14082.5 kHz: audio = dial − spot → 2000, 500, (−7500 mimo), 3500
    let all = AppModel.bandMapMarkers(spots: spots, dialHz: 14_082_500, mode: "LSB", offsetHz: 0,
                                      fromHz: 0, toHz: 4000, records: [], contestSince: nil)
    #expect(Set(all.map(\.spot.call)) == ["DL1ABC", "OK2XYZ", "G3BBB"])
    let narrow = AppModel.bandMapMarkers(spots: spots, dialHz: 14_082_500, mode: "LSB", offsetHz: 0,
                                         fromHz: 1000, toHz: 3000, records: [], contestSince: nil)
    #expect(narrow.map(\.spot.call) == ["DL1ABC"])
    #expect(narrow.first?.audioHz == 2000)
}

@Test func bandMapKeepsNewest20() {
    let spots = (0..<30).map { bmSpot("DL\($0)ABC", 14080.0 + Double($0) * 0.05, age: Double($0)) }
    let m = AppModel.bandMapMarkers(spots: spots, dialHz: 14_082_500, mode: "LSB", offsetHz: 0,
                                    fromHz: 0, toHz: 4000, records: [], contestSince: nil)
    #expect(m.count == 20)
    #expect(m.first?.spot.call == "DL0ABC")
    #expect(!m.contains { $0.spot.call == "DL25ABC" })
}

@Test func bandMapStatusNewWorkedDupe() {
    let spots = [bmSpot("DL1ABC", 14080.0), bmSpot("OK2XYZ", 14081.0), bmSpot("F5AAA", 14082.0)]
    let recs = [bmRecord("DL1ABC"), bmRecord("OK2XYZ", at: Date().addingTimeInterval(-86400 * 3))]
    let since = Date().addingTimeInterval(-3600)
    func status(_ call: String, _ contest: Date?) -> BandMapMarker.Status? {
        AppModel.bandMapMarkers(spots: spots, dialHz: 14_082_500, mode: "LSB", offsetHz: 0, fromHz: 0, toHz: 4000,
                                records: recs, contestSince: contest).first { $0.spot.call == call }?.status
    }
    #expect(status("F5AAA", nil) == .new)
    #expect(status("DL1ABC", nil) == .worked)
    #expect(status("OK2XYZ", nil) == .worked)
    #expect(status("DL1ABC", since) == .dupe)          // v závodě je spojení od začátku závodu
    #expect(status("OK2XYZ", since) == .worked)        // starší než začátek závodu → jen „v logu“
    #expect(status("F5AAA", since) == .new)
}

@Test @MainActor func bandMapHiddenWithoutRigOrWhenDisabled() async throws {
    let m = spotModel(rig: NoRig())
    #expect(m.rig == nil)
    #expect(m.bandMapMarkers.isEmpty)                      // bez rigu žádné štítky
    m.rig = RigStatus(online: true, frequency: nil, mode: "LSB")
    #expect(m.bandMapMarkers.isEmpty)                      // neznámá frekvence
    m.setSpots { $0.showInWaterfall = false }
    #expect(!m.settings.spots.showInWaterfall)
    m.rig = RigStatus(online: true, frequency: 14_082_500, mode: "LSB")
    #expect(m.bandMapMarkers.isEmpty)                      // vypnuto v nastavení
}

@Test @MainActor func showInWaterfallDefaultsToTrueAndDoesNotStartNetwork() async throws {
    let m = spotModel(rig: NoRig())
    #expect(m.settings.spots.showInWaterfall)
    m.setSpots { $0.showInWaterfall = false }
    #expect(!m.spotFeed.isRunning)                         // přepnutí štítků nespouští síť
}

@Test @MainActor func clickOnMarkerTunesMarkAndFillsCall() async throws {
    let rig = SpotFakeRig()
    let m = spotModel(rig: rig)
    await m.start()
    await m.bandMapClick(BandMapMarker(spot: spot, audioHz: 1850.4, status: .new))
    #expect(m.mark == 1850.4)
    #expect(m.qso.call == "DL1ABC")
    #expect(rig.freqs.isEmpty)                             // rig se nepřelaďuje
    await m.stop()
}
