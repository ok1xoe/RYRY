// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Testing
@testable import QSOLog

private func tmp() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("bk-\(UUID())")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

// Log backup: a copy of the JSONL/ADIF/QTC files into backup/<name>-<time>, only the last N are kept
@Test func logBackupRotates() async throws {
    let dir = tmp()
    let loc = LogLocation(directory: dir, name: "zavod")
    let store = try QSOLogStore(directory: dir, baseName: "zavod")
    try await store.append(QSORecord(call: "OK1AAA", timeOn: Date()))
    try "{}\n".write(to: loc.qtcURL, atomically: true, encoding: .utf8)
    let t0 = ISO8601DateFormatter().date(from: "2026-09-29T12:00:00Z")!
    var made: [URL] = []
    for i in 0..<5 { made.append(try LogBackup.backup(loc, at: t0.addingTimeInterval(Double(i) * 3600), keep: 3)) }
    let root = LogBackup.directory(for: loc)
    let kept = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("zavod-") }.sorted()
    #expect(kept == ["zavod-20260929-140000", "zavod-20260929-150000", "zavod-20260929-160000"])
    let last = made.last!
    for f in ["zavod.jsonl", "zavod.adi", "zavod-qtc.jsonl"] {
        #expect(FileManager.default.fileExists(atPath: last.appendingPathComponent(f).path), "\(f)")
    }
    // the daily backup: it is not made until 24 h have passed
    #expect(!LogBackup.isDue(loc, now: t0.addingTimeInterval(4 * 3600 + 600)))
    #expect(LogBackup.isDue(loc, now: t0.addingTimeInterval(4 * 3600 + 25 * 3600)))
    // an empty log (with no files) is not backed up
    #expect(throws: LogBackup.BackupError.self) { try LogBackup.backup(LogLocation(directory: tmp(), name: "x"), at: t0, keep: 3) }
}

// Statistics: the rate over 10 and 60 min (QSOs/h), the counts per band
@Test func logStats() {
    let now = ISO8601DateFormatter().date(from: "2026-09-29T12:00:00Z")!
    func r(_ c: String, _ minAgo: Double, _ f: Double?) -> QSORecord {
        var q = QSORecord(call: c, timeOn: now.addingTimeInterval(-minAgo * 60)); q.frequency = f; return q
    }
    let recs = [r("A", 2, 14_080_000), r("B", 5, 14_081_000), r("C", 30, 7_040_000), r("D", 90, 7_040_000), r("E", 5, nil)]
    let s = LogStats(records: recs, now: now)
    #expect(s.total == 5)
    #expect(s.last10 == 3 && s.rate10 == 18)          // 3 QSOs in 10 min = 18/h
    #expect(s.last60 == 4 && s.rate60 == 4)
    #expect(s.byBand == [LogStats.BandCount(band: "40m", count: 2), LogStats.BandCount(band: "20m", count: 2),
                         LogStats.BandCount(band: "?", count: 1)])
    let since = LogStats(records: recs, now: now, since: now.addingTimeInterval(-3600))
    #expect(since.total == 4)
}
