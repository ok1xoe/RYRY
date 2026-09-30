import Foundation
import Testing
@testable import QSOLog

// Review C1: a truncated last line must not "swallow" the next record written
@Test func truncatedLastLineDoesNotSwallowNextQSO() async throws {
    let dir = tempDir()
    let a = try QSOLogStore(directory: dir)
    try await a.append(qso("OK1ABC")); try await a.append(qso("OK2DEF"))
    let h = try FileHandle(forWritingTo: await a.jsonlURL)
    h.seekToEndOfFile(); h.write(Data("{\"id\":\"trunc".utf8)); try h.close()     // a power cut
    let b = try QSOLogStore(directory: dir)
    try await b.append(qso("OK3GHI"))
    let c = try QSOLogStore(directory: dir)
    #expect(await c.records.map(\.call) == ["OK1ABC", "OK2DEF", "OK3GHI"])
}

// Review C2: corrupted lines are not dropped when the file is rewritten (an edit/deletion)
@Test func corruptedLinesSurviveRewrite() async throws {
    let dir = tempDir()
    let a = try QSOLogStore(directory: dir)
    let keep = qso("OK1ABC"); try await a.append(keep); try await a.append(qso("OK2DEF"))
    let h = try FileHandle(forWritingTo: await a.jsonlURL)
    h.seekToEndOfFile(); h.write(Data("{\"broken\": true, \"call\": \"RESCUE-ME\"}\n".utf8)); try h.close()
    let b = try QSOLogStore(directory: dir)
    try await b.delete(id: keep.id)
    let text = try String(contentsOf: await b.jsonlURL, encoding: .utf8)
    #expect(text.contains("RESCUE-ME"))
    #expect(await b.records.map(\.call) == ["OK2DEF"])
}

// Review C2: an unreadable log = an error, not an empty log that would then be overwritten
@Test func unreadableLogRefusesWrites() async throws {
    let dir = tempDir()
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("mmtty4mac.jsonl"), withIntermediateDirectories: true)
    let s = try QSOLogStore(directory: dir)
    #expect(!(await s.warnings).isEmpty)
    await #expect(throws: QSOLogError.self) { try await s.append(qso("OK1ABC")) }
}

// Review I5: a failure of the ADIF write must not let JSONL and memory diverge
@Test func adifFailureKeepsJsonlAndMemoryInSync() async throws {
    let dir = tempDir()
    let s = try QSOLogStore(directory: dir)
    try await s.append(qso("OK1ABC"))
    let adif = await s.adifURL
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: adif.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: adif.path) }
    try await s.append(qso("OK2DEF"))                        // JSONL OK, the ADIF write fails → a warning
    #expect(await s.records.count == 2)
    #expect(!(await s.warnings).isEmpty)
    #expect(await s.isADIFConsistent() == false)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: adif.path)
    let again = try QSOLogStore(directory: dir)              // the ADIF is repaired at start-up
    #expect(await again.records.count == 2)
    #expect(await again.isADIFConsistent())
}

// Review I7: a huge field length must not crash the parser
@Test func hugeFieldLengthDoesNotCrash() {
    #expect(ADIF.parse("<EOH><CALL:9223372036854775807>X<EOR>").count == 1)
}
