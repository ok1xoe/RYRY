import Foundation
import Testing
@testable import QSOLog

func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("qsolog-\(UUID())")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

func qso(_ call: String, _ t: TimeInterval = 1_790_000_000, name: String? = nil) -> QSORecord {
    var r = QSORecord(call: call, timeOn: Date(timeIntervalSince1970: t))
    r.frequency = 14_080_000; r.rstSent = "599"; r.rstRcvd = "599"; r.name = name
    return r
}

@Test func appendWritesBothFiles() async throws {
    let dir = tempDir()
    let store = try QSOLogStore(directory: dir)
    for c in ["OK1ABC", "DL1XYZ", "W1AW"] { try await store.append(qso(c)) }
    let jsonl = try String(contentsOf: await store.jsonlURL, encoding: .utf8)
    #expect(jsonl.split(separator: "\n").count == 3)
    let adi = try String(contentsOf: await store.adifURL, encoding: .utf8)
    #expect(adi.contains("<EOH>"))
    let recs = ADIF.parse(adi)
    #expect(recs.count == 3)
    let r = recs[0]
    #expect(r["CALL"] == "OK1ABC")
    #expect(r["QSO_DATE"] == "20260921")
    #expect(r["TIME_ON"]?.count == 6)
    #expect(r["FREQ"] == "14.080000")
    #expect(r["BAND"] == "20m")
    #expect(r["MODE"] == "RTTY")
    #expect(r["RST_SENT"] == "599")
    #expect(r["APP_MMTTY4MAC_ID"] != nil)
}

@Test func reloadReadsSameRecords() async throws {
    let dir = tempDir()
    let a = try QSOLogStore(directory: dir)
    try await a.append(qso("OK1ABC")); try await a.append(qso("OK2DEF"))
    let b = try QSOLogStore(directory: dir)
    #expect(await b.records == a.records)
}

@Test func updateAndDeleteRewriteBothFiles() async throws {
    let dir = tempDir()
    let s = try QSOLogStore(directory: dir)
    let first = qso("OK1ABC"); try await s.append(first); try await s.append(qso("OK2DEF"))
    var changed = first; changed.name = "PETR"
    try await s.update(changed)
    var adi = ADIF.parse(try String(contentsOf: await s.adifURL, encoding: .utf8))
    #expect(adi.count == 2 && adi[0]["NAME"] == "PETR")
    try await s.delete(id: first.id)
    adi = ADIF.parse(try String(contentsOf: await s.adifURL, encoding: .utf8))
    #expect(adi.count == 1 && adi[0]["CALL"] == "OK2DEF")
    #expect(await s.records.count == 1)
    #expect(await s.isADIFConsistent())
}

// Review Focus 5
@Test func unknownIdIsErrorAndFilesUntouched() async throws {
    let dir = tempDir()
    let s = try QSOLogStore(directory: dir)
    try await s.append(qso("OK1ABC"))
    let before = try Data(contentsOf: await s.adifURL) + Data(contentsOf: await s.jsonlURL)
    let ghost = qso("X")
    await #expect(throws: QSOLogError.notFound(ghost.id)) { try await s.update(ghost) }
    await #expect(throws: QSOLogError.notFound(ghost.id)) { try await s.delete(id: ghost.id) }
    let after = try Data(contentsOf: await s.adifURL) + Data(contentsOf: await s.jsonlURL)
    #expect(before == after)
}

// Review Focus 2
@Test func utf8LengthsAreBytes() async throws {
    let dir = tempDir()
    let s = try QSOLogStore(directory: dir)
    var r = qso("OK1ABC", name: "Tomáš"); r.qth = "Plzeň"
    try await s.append(r)
    let adi = try String(contentsOf: await s.adifURL, encoding: .utf8)
    #expect(adi.contains("<NAME:7>Tomáš"))
    #expect(adi.contains("<QTH:6>Plzeň"))
    let p = ADIF.parse(adi)
    #expect(p[0]["NAME"] == "Tomáš" && p[0]["QTH"] == "Plzeň")
}

// Review Focus 1
@Test func corruptedJsonlLineIsSkippedWithWarning() async throws {
    let dir = tempDir()
    let a = try QSOLogStore(directory: dir)
    try await a.append(qso("OK1ABC")); try await a.append(qso("OK2DEF"))
    let h = try FileHandle(forWritingTo: await a.jsonlURL)
    h.seekToEndOfFile(); h.write(Data("{\"id\": broken\n".utf8)); try h.close()
    let b = try QSOLogStore(directory: dir)
    #expect(await b.records.count == 2)
    #expect(!(await b.warnings).isEmpty)
}

@Test func consistencyCheckAndRebuild() async throws {
    let dir = tempDir()
    let s = try QSOLogStore(directory: dir)
    try await s.append(qso("OK1ABC")); try await s.append(qso("OK2DEF"))
    let url = await s.adifURL
    var adi = try String(contentsOf: url, encoding: .utf8)
    adi = String(adi[..<adi.range(of: "<EOR>")!.upperBound])        // truncate the second record
    try adi.write(to: url, atomically: true, encoding: .utf8)
    #expect(await s.isADIFConsistent() == false)
    try await s.rebuildADIF()
    #expect(await s.isADIFConsistent())
}

@Test func previousContactsIgnorePortableSuffix() async throws {
    let s = try QSOLogStore(directory: tempDir())
    try await s.append(qso("OK1ABC", 1_000))
    try await s.append(qso("OK1ABC/P", 2_000))
    try await s.append(qso("OK2DEF", 3_000))
    let prev = await s.previous(call: "ok1abc")
    #expect(prev.map(\.call) == ["OK1ABC/P", "OK1ABC"])
    #expect(await s.query(call: "OK2DEF").count == 1)
    #expect(await s.query(limit: 2).count == 2)
}

@Test func bands() {
    #expect(Bands.band(forHz: 14_080_000) == "20m")
    #expect(Bands.band(forHz: 7_045_000) == "40m")
    #expect(Bands.band(forHz: 3_580_000) == "80m")
    #expect(Bands.band(forHz: 144_300_000) == "2m")
    #expect(Bands.band(forHz: nil) == nil)
    #expect(Bands.band(forHz: 1e12) == nil)
}
