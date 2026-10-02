import Foundation
import Testing
@testable import QSOLog

@Test func oldJSONLWithoutUploadsStillReads() async throws {
    let dir = tempDir()
    let line = #"{"call":"OK1ABC","id":"\#(UUID().uuidString)","mode":"RTTY","timeOn":"2026-09-21T10:00:00.000Z"}"#
    try (line + "\n").write(to: dir.appendingPathComponent("RYRY.jsonl"), atomically: true, encoding: .utf8)
    let store = try QSOLogStore(directory: dir)
    let recs = await store.records
    #expect(recs.count == 1 && recs[0].uploads == nil)
    #expect(!recs[0].isUploaded(.lotw))
}

@Test func markUploadedPersistsAndSurvivesReload() async throws {
    let dir = tempDir()
    let store = try QSOLogStore(directory: dir)
    let a = qso("OK1ABC"), b = qso("DL1XYZ", 1_790_000_100)
    try await store.append(a); try await store.append(b)
    let when = Date(timeIntervalSince1970: 1_790_001_000)
    let n = try await store.markUploaded(ids: [a.id], target: .eqsl, at: when)
    #expect(n == 1)
    let re = try QSOLogStore(directory: dir)
    let recs = await re.records
    let r = recs.first { $0.id == a.id }!
    #expect(r.isUploaded(.eqsl) && !r.isUploaded(.lotw))
    #expect(abs(r.uploads![UploadTarget.eqsl.rawValue]!.timeIntervalSince(when)) < 0.01)
    #expect(recs.first { $0.id == b.id }!.uploads == nil)
    // an unknown id is ignored
    #expect(try await store.markUploaded(ids: [UUID()], target: .lotw) == 0)
}

@Test func adifExportsUploadStatusButUploadRecordDoesNot() {
    var r = qso("OK1ABC")
    #expect(!ADIF.record(r).contains("LOTW_QSL_SENT"))
    let t = Date(timeIntervalSince1970: 1_790_001_000)
    r.markUploaded(.lotw, at: t); r.markUploaded(.eqsl, at: t); r.markUploaded(.clublog, at: t)
    let f = ADIF.parse(ADIF.record(r))[0]
    #expect(f["LOTW_QSL_SENT"] == "Y" && f["EQSL_QSL_SENT"] == "Y" && f["CLUBLOG_QSO_UPLOAD_STATUS"] == "Y")
    #expect(f["LOTW_QSLSDATE"] == "20260921" && f["CLUBLOG_QSO_UPLOAD_DATE"] == "20260921")
    let u = ADIF.parse(ADIF.uploadRecord(r))[0]
    #expect(u["LOTW_QSL_SENT"] == nil && u["CALL"] == "OK1ABC")
}

@Test func adifImportReadsUploadStatus() {
    var r = qso("OK1ABC")
    r.markUploaded(.clublog, at: Date(timeIntervalSince1970: 1_790_001_000))
    let imp = ADIF.importRecords(ADIF.header() + ADIF.record(r)).records[0]
    #expect(imp.isUploaded(.clublog) && !imp.isUploaded(.eqsl))
}

// Review Critical 1: two log instances over the same files (an upload across Apply) – the rewrite must not delete
// a QSO written by the second instance
@Test func rewriteReloadsWhenFileChangedElsewhere() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stale-\(UUID())")
    let old = try QSOLogStore(directory: dir)
    let a = QSORecord(call: "OK1AAA", timeOn: Date())
    try await old.append(a)
    let fresh = try QSOLogStore(directory: dir)                   // a restart after Apply
    try await Task.sleep(for: .milliseconds(20))                  // a different file modification time
    try await fresh.append(QSORecord(call: "OK2BBB", timeOn: Date()))
    try await old.markUploaded(ids: [a.id], target: .lotw)        // an upload that finished in the old instance
    let check = try QSOLogStore(directory: dir)
    let calls = await check.records.map(\.call)
    #expect(calls.sorted() == ["OK1AAA", "OK2BBB"])
    #expect(await check.records.first { $0.call == "OK1AAA" }?.uploads?["lotw"] != nil)
    #expect(await check.isADIFConsistent())
}
