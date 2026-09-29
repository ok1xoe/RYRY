import Foundation
import Testing
@testable import QSOLog

private func isoDate(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
private func q(_ call: String, _ t: String, rcvd: Int?) -> QSORecord {
    var r = QSORecord(call: call, timeOn: isoDate("2026-11-14T\(t):00Z"))
    r.serialRcvd = rcvd; r.serialSent = 1; r.frequency = 14_085_000
    return r
}

@Test func plannerRespectsLimitsOnceAndNotOwn() {
    let log = [q("DL1ABC", "10:00", rcvd: 5), q("K1XX", "10:05", rcvd: 17), q("JA1YY", "10:10", rcvd: 3),
               q("OK2PBR", "10:12", rcvd: nil)]                            // bez přijatého čísla → nelze
    var p = QTCPlanner(records: log, series: [])
    // stanici K1XX nelze poslat QTC o ní samé
    #expect(p.available(for: "K1XX").map(\.call) == ["DL1ABC", "JA1YY"])
    #expect(p.available(for: "K1XX").first == QTCLine(time: "1000", call: "DL1ABC", serial: 5))
    // odesláno → podruhé už ne; počitadlo s K1XX
    let s = QTCSeries(direction: .sent, number: 1, counterpart: "K1XX", time: Date(), lines: p.available(for: "K1XX"))
    p = QTCPlanner(records: log, series: [s])
    #expect(p.exchanged(with: "K1XX") == 2 && p.exchanged(with: "K1XX/P") == 2)
    #expect(p.available(for: "W2ZZ").map(\.call) == ["K1XX"])
    #expect(p.nextSeriesNumber == 2)
}

@Test func plannerTenPerPairIncludingReceived() {
    let log = (0..<15).map { q("DL\($0)AA", String(format: "10:%02d", $0), rcvd: $0 + 1) }
    let recv = QTCSeries(direction: .received, number: 4, counterpart: "K1XX", time: Date(),
                         lines: (0..<7).map { QTCLine(time: "0900", call: "EA\($0)A", serial: $0) })
    let p = QTCPlanner(records: log, series: [recv])
    #expect(p.exchanged(with: "K1XX") == 7)
    #expect(p.available(for: "K1XX").count == 3)
    #expect(p.available(for: "W2ZZ").count == 10)                      // série max. 10
}

@Test func qtcTextFormatAndParse() {
    let lines = [QTCLine(time: "1307", call: "DA1AA", serial: 431), QTCLine(time: "1310", call: "OK2PBR", serial: 15)]
    #expect(QTCText.header(number: 3, count: 2) == "QTC 3/2 QTC 3/2")
    #expect(QTCText.line(lines[1]) == "1310 OK2PBR 015")
    #expect(QTCText.body(number: 3, lines: lines) == "\r\nQTC 3/2 QTC 3/2\r\n1307 DA1AA 431\r\n1310 OK2PBR 015\r\n")
    #expect(QTCText.repeatLine(lines[0], index: 1) == "\r\n1 1307 DA1AA 431 1307 DA1AA 431\r\n")
    #expect(QTCText.parseHeader("QTC 3/7").map { [$0.0, $0.1] } == [3, 7])
    #expect(QTCText.parseHeader("3/7").map { [$0.0, $0.1] } == [3, 7])
    #expect(QTCText.parseHeader("QTC") == nil)
    #expect(QTCText.parseLine("1307 DA1AA 431") == QTCLine(time: "1307", call: "DA1AA", serial: 431))
    #expect(QTCText.parseLine("1307 DA1AA 431 1307 DA1AA 431") == QTCLine(time: "1307", call: "DA1AA", serial: 431))
    #expect(QTCText.parseLine("2599 DA1AA 431") == nil)                 // neplatný čas
    #expect(QTCText.parseLine("CQ TEST") == nil)
}

@Test func qtcStorePersists() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qtc-\(UUID())")
    let st = try QTCStore(directory: dir)
    let s = QTCSeries(direction: .received, number: 2, counterpart: "K1XX", time: Date(), frequency: 14_085_000,
                      lines: [QTCLine(time: "1307", call: "DA1AA", serial: 431)])
    try await st.append(s)
    let again = try QTCStore(directory: dir)
    #expect(await again.series == [s])
}

@Test func cabrilloQTCLines() {
    let t = isoDate("2026-11-14T10:28:00Z")
    let sent = QTCSeries(direction: .sent, number: 7, counterpart: "K5XYZ", time: t, frequency: 21_011_000,
                         lines: [QTCLine(time: "1332", call: "S59XYZ", serial: 112)])
    let recv = QTCSeries(direction: .received, number: 2, counterpart: "JA1YY", time: t, frequency: 14_085_000,
                         lines: [QTCLine(time: "0915", call: "UA0AA", serial: 7)])
    let text = Cabrillo.export([], header: CabrilloHeader(callsign: "DL1XYZ", contest: "WAEDC"), qtc: [sent, recv])
    #expect(text.contains("QTC: 21011 RY 2026-11-14 1028 K5XYZ         7/1   DL1XYZ        1332 S59XYZ        112"))
    #expect(text.contains("QTC: 14085 RY 2026-11-14 1028 DL1XYZ        2/1   JA1YY         0915 UA0AA         007"))
}
