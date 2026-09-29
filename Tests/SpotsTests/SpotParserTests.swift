import Foundation
import Testing
import QSOLog
@testable import Spots

/// 2026-03-14 12:10 UTC
let refNow = Date(timeIntervalSince1970: 1_773_490_200)

@Test func parsesRBNRTTYLine() throws {
    let s = try #require(SpotParser.parse("DX de W3LPL-#:    14080.0  DL1ABC       RTTY 25 dB 45 BPS CQ      1203Z", now: refNow, source: .rbn))
    #expect(s.frequencyKHz == 14080.0)
    #expect(s.call == "DL1ABC")
    #expect(s.spotter == "W3LPL-#")
    #expect(s.comment == "RTTY 25 dB 45 BPS CQ")
    #expect(s.mode == "RTTY" && s.isRTTY)
    #expect(s.snr == 25)
    #expect(s.source == .rbn)
    #expect(s.band == "20m")
    #expect(s.time == refNow.addingTimeInterval(-7 * 60))            // 12:03 UTC, datum dnešní
}

@Test func parsesClassicClusterLineWithLocator() throws {
    let s = try #require(SpotParser.parse("DX de OK1ABC:     7040.5  JA1XYZ       599 rtty up 1          1150Z JN79\u{07}", now: refNow))
    #expect(s.frequencyKHz == 7040.5)
    #expect(s.call == "JA1XYZ")
    #expect(s.comment == "599 rtty up 1")
    #expect(s.mode == "RTTY")
    #expect(s.snr == nil)
    #expect(s.band == "40m")
}

@Test func cwSpotIsNotRTTY() throws {
    let s = try #require(SpotParser.parse("DX de DK9IP-#:    14033.2  UA3XYZ       CW 22 dB 26 WPM CQ         1204Z", now: refNow, source: .rbn))
    #expect(s.mode == "CW" && !s.isRTTY)
    #expect(s.snr == 22)
}

@Test func rttyDetectedFromSegmentWhenCommentSilent() throws {
    let inSeg = try #require(SpotParser.parse("DX de OK1ABC: 14085.0 K1ABC CQ DX 1200Z", now: refNow))
    #expect(inSeg.mode == "RTTY")
    let outSeg = try #require(SpotParser.parse("DX de OK1ABC: 14195.0 K1ABC CQ DX 1200Z", now: refNow))
    #expect(outSeg.mode == nil)
    // explicitní jiný mód má přednost před segmentem
    let ft8 = try #require(SpotParser.parse("DX de OK1ABC: 14074.0 K1ABC FT8 -10 dB 1200Z", now: refNow))
    #expect(ft8.mode == "FT8")
    #expect(ft8.snr == -10)
}

@Test func snrWithoutSpace() throws {
    let s = try #require(SpotParser.parse("DX de N2QT-#: 21080.1 W1AW RTTY 31dB 50 BPS CQ 1200Z", now: refNow))
    #expect(s.snr == 31)
}

@Test func timeAfterMidnightBelongsToYesterday() throws {
    // 00:05 UTC, spot z 23:58 předchozího dne
    let now = Date(timeIntervalSince1970: 1_773_446_700)          // 2026-03-14 00:05 UTC
    let s = try #require(SpotParser.parse("DX de OK1ABC: 14080.0 K1ABC RTTY 2358Z", now: now))
    #expect(s.time == now.addingTimeInterval(-7 * 60))
}

@Test func rejectsBadLines() {
    let bad = [
        "",
        "Hello OK1XOE, welcome to the cluster",
        "DX de OK1ABC: 14080.0 DL1ABC RTTY",                          // bez času
        "DX de OK1ABC: 14080.0 DL1ABC RTTY 2561Z",                    // neplatný čas
        "DX de OK1ABC: 14080.0 DL1ABC RTTY 2460Z",
        "DX de OK1ABC: abc DL1ABC RTTY 1200Z",                        // frekvence není číslo
        "DX de OK1ABC: 0.0 DL1ABC RTTY 1200Z",
        "DX de OK1ABC 14080.0 DL1ABC RTTY 1200Z",                     // bez dvojtečky
        "DX de : 14080.0 DL1ABC RTTY 1200Z",                          // bez spotra
        "DX de OK1ABC: 14080.0 !!!! RTTY 1200Z",                      // vadná značka
        "DX de OK1ABC: 14080.0 12345 RTTY 1200Z",                     // značka bez písmen
        "DX de OK1ABC: 14080.0",
        "To ALL de OK1ABC: 14080.0 DL1ABC RTTY 1200Z",
    ]
    for l in bad { #expect(SpotParser.parse(l, now: refNow) == nil, "\(l)") }
}

@Test func bookDedupesCallAndBandKeepingNewest() {
    var b = SpotBook()
    func spot(_ call: String, _ khz: Double, minutesAgo: Double, mode: String? = "RTTY") -> Spot {
        Spot(frequencyKHz: khz, call: call, spotter: "X1X", comment: "", time: refNow.addingTimeInterval(-minutesAgo * 60), mode: mode)
    }
    do { let r = b.add(spot("DL1ABC", 14080, minutesAgo: 10), now: refNow, maxAge: 1800); #expect(r) }
    do { let r = b.add(spot("DL1ABC", 14081, minutesAgo: 2), now: refNow, maxAge: 1800); #expect(r) } // nahradí
    do { let r = b.add(spot("DL1ABC", 14082, minutesAgo: 20), now: refNow, maxAge: 1800); #expect(!r) } // starší – zahodí
    do { let r = b.add(spot("DL1ABC", 7040, minutesAgo: 5), now: refNow, maxAge: 1800); #expect(r) } // jiné pásmo
    #expect(b.count == 2)
    let v = b.visible(rttyOnly: true)
    #expect(v.map(\.frequencyKHz) == [14081, 7040])                                      // nejnovější první
    #expect(b.visible(rttyOnly: true, band: "40m").map(\.call) == ["DL1ABC"])
    #expect(b.visible(rttyOnly: true, band: "15m").isEmpty)
}

@Test func bookAgeLimitAndPrune() {
    var b = SpotBook()
    let old = Spot(frequencyKHz: 14080, call: "K1OLD", spotter: "X", comment: "", time: refNow.addingTimeInterval(-40 * 60), mode: "RTTY")
    let fresh = Spot(frequencyKHz: 14080, call: "K1NEW", spotter: "X", comment: "", time: refNow.addingTimeInterval(-5 * 60), mode: "RTTY")
    do { let r = b.add(old, now: refNow, maxAge: 1800); #expect(!r) }
    do { let r = b.add(fresh, now: refNow, maxAge: 1800); #expect(r) }
    b.prune(now: refNow.addingTimeInterval(30 * 60), maxAge: 1800)
    #expect(b.count == 0)
}

@Test func bookCapsAtMaxDroppingOldest() {
    var b = SpotBook(maxCount: 5)
    for i in 0..<8 {
        b.add(Spot(frequencyKHz: 14080, call: "K\(i)ABC", spotter: "X", comment: "", time: refNow.addingTimeInterval(-Double(100 - i)), mode: "RTTY"),
              now: refNow, maxAge: 1800)
    }
    #expect(b.count == 5)
    #expect(Set(b.visible(rttyOnly: false).map(\.call)) == ["K3ABC", "K4ABC", "K5ABC", "K6ABC", "K7ABC"])
    #expect(SpotBook(maxCount: 10_000).maxCount == 500)
}

@Test func rttyOnlyFilterHidesOthers() {
    var b = SpotBook()
    b.add(Spot(frequencyKHz: 14033, call: "UA3XYZ", spotter: "X", comment: "", time: refNow, mode: "CW"), now: refNow, maxAge: 1800)
    b.add(Spot(frequencyKHz: 14080, call: "DL1ABC", spotter: "X", comment: "", time: refNow, mode: "RTTY"), now: refNow, maxAge: 1800)
    #expect(b.visible(rttyOnly: true).map(\.call) == ["DL1ABC"])
    #expect(b.visible(rttyOnly: false).count == 2)
}

@Test func logIndexStatus() {
    var r = QSORecord(call: "DL1ABC", timeOn: refNow); r.frequency = 14_083_000
    let idx = SpotLogIndex([r])
    func s(_ call: String, _ khz: Double) -> Spot { Spot(frequencyKHz: khz, call: call, spotter: "X", comment: "", time: refNow) }
    #expect(idx.status(of: s("DL1ABC", 14080)) == .workedOnBand)
    #expect(idx.status(of: s("DL1ABC/P", 14080)) == .workedOnBand)
    #expect(idx.status(of: s("DL1ABC", 7040)) == .worked)
    #expect(idx.status(of: s("K1ABC", 14080)) == .none)
}

@Test func telnetFilterStripsNegotiation() {
    var f = TelnetFilter()
    let (t, r) = f.process(Data([255, 253, 1, 255, 251, 3, 72, 105, 255, 255, 33, 255, 250, 24, 1, 255, 240, 10]))
    #expect(Array(t) == [72, 105, 255, 33, 10])
    #expect(Array(r) == [255, 252, 1, 255, 254, 3])
    // sekvence rozdělená mezi bloky
    var g = TelnetFilter()
    let a = g.process(Data([65, 255])), b = g.process(Data([253])), c = g.process(Data([1, 66]))
    #expect(Array(a.text) == [65] && b.text.isEmpty && Array(c.text) == [66])
    #expect(Array(c.reply) == [255, 252, 1])
}

@Test func splitterAndPrompt() {
    var s = LineSplitter()
    let l1 = s.feed(Data("hello\r\nDX de A:".utf8))
    #expect(l1 == ["hello"])
    #expect(s.pending == "DX de A:")
    let l2 = s.feed(Data(" x\r\n".utf8))
    #expect(l2 == ["DX de A: x"])
    #expect(TelnetPrompt.isLogin("login: "))
    #expect(TelnetPrompt.isLogin("Please enter your call: "))
    #expect(!TelnetPrompt.isLogin("DX de OK1ABC: 14080.0 DL1ABC RTTY 1200Z"))
    #expect(!TelnetPrompt.isLogin("Welcome"))
}
