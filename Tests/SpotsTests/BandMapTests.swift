import Foundation
import Testing
@testable import Spots

@Test func usbAudioIsSpotMinusDial() {
    #expect(BandMap.audioOffset(spotHz: 14_082_125, dialHz: 14_080_000, mode: "USB", offsetHz: 0) == 2125)
    #expect(BandMap.audioOffset(spotHz: 14_082_125, dialHz: 14_080_000, mode: "PKTUSB", offsetHz: 0) == 2125)
}

@Test func lsbAudioIsDialMinusSpot() {
    #expect(BandMap.audioOffset(spotHz: 14_080_000, dialHz: 14_082_125, mode: "LSB", offsetHz: 0) == 2125)
    #expect(BandMap.audioOffset(spotHz: 14_080_000, dialHz: 14_082_125, mode: "PKTLSB", offsetHz: 0) == 2125)
}

@Test func rttyModeBehavesLikeLSB() {
    #expect(BandMap.audioOffset(spotHz: 14_080_000, dialHz: 14_081_500, mode: "RTTY", offsetHz: 0) == 1500)
    #expect(BandMap.audioOffset(spotHz: 14_080_000, dialHz: 14_081_500, mode: "RTTYR", offsetHz: 0) == 1500)
    #expect(BandMap.audioOffset(spotHz: 14_080_000, dialHz: 14_081_500, mode: "FSK", offsetHz: 0) == 1500)
}

@Test func outOfRangeOrUnknownModeIsNil() {
    #expect(BandMap.audioOffset(spotHz: 14_090_000, dialHz: 14_080_000, mode: "LSB", offsetHz: 0) == nil)
    #expect(BandMap.audioOffset(spotHz: 14_090_000, dialHz: 14_080_000, mode: "USB", offsetHz: 0) == nil)
    #expect(BandMap.audioOffset(spotHz: 14_080_000, dialHz: 14_084_500, mode: "LSB", offsetHz: 0) == nil)
    #expect(BandMap.audioOffset(spotHz: 14_080_000, dialHz: 14_080_000, mode: "CW", offsetHz: 0) == nil)
    #expect(BandMap.audioOffset(spotHz: 14_080_000, dialHz: 14_080_000, mode: nil, offsetHz: 0) == nil)
    #expect(BandMap.audioOffset(spotHz: 14_080_000, dialHz: 14_080_000, mode: "USB", offsetHz: 0) == 0)
}

@Test func offsetIsConsistentWithDoubleClick() {
    // useSpot: rig = spot + offset → značka na tónu daném posunem (LSB +2125, USB −2125)
    let spot = 14_080_000.0
    #expect(BandMap.audioOffset(spotHz: spot, dialHz: spot + 2125, mode: "LSB", offsetHz: 2125) == 2125)
    #expect(BandMap.audioOffset(spotHz: spot, dialHz: spot - 2125, mode: "USB", offsetHz: -2125) == 2125)
    #expect(BandMap.audioOffset(spotHz: spot, dialHz: spot + 1000, mode: "LSB", offsetHz: 2125) == 1000)
}

@Test func layoutPutsOverlappingLabelsInRows() {
    let rows = BandMap.layoutRows(centers: [100, 110, 105, 400], widths: [60, 60, 60, 60], totalWidth: 800)
    #expect(rows == [0, 1, 2, 0])
    #expect(BandMap.layoutRows(centers: [100, 200], widths: [60, 60], totalWidth: 800) == [0, 0])
}

@Test func layoutDropsLabelsWithoutRoom() {
    let rows = BandMap.layoutRows(centers: [100, 100, 100], widths: [60, 60, 60], totalWidth: 800, maxRows: 2)
    #expect(rows == [0, 1, nil])
}

@Test func layoutKeepsLabelsInsideWidth() {
    let rows = BandMap.layoutRows(centers: [0, 20], widths: [60, 60], totalWidth: 200)
    #expect(rows == [0, 1])
}
