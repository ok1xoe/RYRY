import Foundation
import Testing
@testable import QSOLog

@Test func fractionalSecondsSurviveReload() async throws {
    let dir = tempDir()
    let a = try QSOLogStore(directory: dir)
    let r = QSORecord(call: "OK1ABC", timeOn: Date(timeIntervalSince1970: 1_790_000_000.375))
    try await a.append(r)
    let b = try QSOLogStore(directory: dir)
    #expect(await b.records == [r])
}

@Test func oldWholeSecondDatesStillLoad() async throws {
    let dir = tempDir()
    let line = #"{"call":"OK1ABC","id":"1483B359-B6F6-4FE0-9829-83278AE002B4","mode":"RTTY","timeOn":"2026-09-28T23:47:12Z"}"# + "\n"
    try Data(line.utf8).write(to: dir.appendingPathComponent("RYRY.jsonl"))
    let s = try QSOLogStore(directory: dir)
    #expect(await s.records.count == 1)
}

@Test func callIsNormalizedOnAppendAndUpdate() async throws {
    let s = try QSOLogStore(directory: tempDir())
    var r = QSORecord(call: "OK1ABC", timeOn: Date())
    r.call = "dl1abc/p"
    try await s.append(r)
    #expect(await s.records.first?.call == "DL1ABC/P")
    r.call = "w1aw"
    try await s.update(r)
    #expect(await s.query(call: "W1AW").count == 1)
}
