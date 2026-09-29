import Foundation
import Testing
@testable import QSOLog

private func rec(_ call: String, _ time: String, sent: Int?, rcvd: Int?, exS: String? = nil, exR: String? = nil,
                 freq: Double? = 14_083_500) -> QSORecord {
    let f = ISO8601DateFormatter()
    var r = QSORecord(call: call, timeOn: f.date(from: time)!)
    r.frequency = freq; r.rstSent = "599"; r.rstRcvd = "599"
    r.serialSent = sent; r.serialRcvd = rcvd; r.exchangeSent = exS; r.exchangeRcvd = exR
    return r
}

@Test func cabrilloHeaderAndQSOLines() {
    var h = CabrilloHeader(callsign: "OK1XOE", contest: "BARTG-RTTY")
    h.categories = ["OPERATOR: SINGLE-OP", "CATEGORY-POWER: LOW"]
    h.locator = "JO70"; h.name = "Tomas"
    let recs = [rec("DL1ABC", "2026-09-29T12:03:00Z", sent: 1, rcvd: 15),
                rec("HA7AB", "2026-09-29T12:01:30Z", sent: nil, rcvd: nil, exS: "14", exR: "15", freq: 7_045_000)]
    let text = Cabrillo.export(recs, header: h)
    let lines = text.components(separatedBy: "\r\n")
    #expect(lines.first == "START-OF-LOG: 3.0")
    #expect(lines.contains("CREATED-BY: mmtty4mac"))
    #expect(lines.contains("CALLSIGN: OK1XOE"))
    #expect(lines.contains("CONTEST: BARTG-RTTY"))
    #expect(lines.contains("CATEGORY-OPERATOR: SINGLE-OP"))
    #expect(lines.contains("CATEGORY-POWER: LOW"))
    #expect(lines.contains("GRID-LOCATOR: JO70"))
    let qsos = lines.filter { $0.hasPrefix("QSO:") }
    // chronologicky
    #expect(qsos == [
        "QSO:  7045 RY 2026-09-29 1201 OK1XOE        599 14     HA7AB         599 15",
        "QSO: 14083 RY 2026-09-29 1203 OK1XOE        599 001    DL1ABC        599 015",
    ])
    #expect(lines.suffix(2) == ["END-OF-LOG:", ""])
}

@Test func cabrilloWithoutFrequencyUsesZeroAndEmptyLog() {
    let t = Cabrillo.export([rec("DL1ABC", "2026-09-29T12:03:00Z", sent: 1, rcvd: nil, freq: nil)],
                            header: CabrilloHeader(callsign: "OK1XOE", contest: ""))
    #expect(t.contains("QSO:     0 RY 2026-09-29 1203 OK1XOE        599 001    DL1ABC        599"))
    let empty = Cabrillo.export([], header: CabrilloHeader(callsign: "OK1XOE", contest: "X"))
    #expect(!empty.contains("QSO:") && empty.hasSuffix("END-OF-LOG:\r\n"))
}

@Test func adifContainsDXCCFields() {
    var r = QSORecord(call: "JA1XYZ", timeOn: Date(timeIntervalSince1970: 0))
    r.country = "Japan"; r.continent = "AS"; r.cqZone = 25; r.ituZone = 45
    let a = ADIF.record(r)
    #expect(a.contains("<COUNTRY:5>Japan ") && a.contains("<CONT:2>AS ") && a.contains("<CQZ:2>25 ") && a.contains("<ITUZ:2>45 "))
    let back = ADIF.parse("<EOH>" + a)
    #expect(back.first?["COUNTRY"] == "Japan")
}
