// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
@testable import QSOLog

private func tmp() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("loc-\(UUID())")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@Test func logLocationFromFile() {
    let d = URL(fileURLWithPath: "/tmp/x")
    #expect(LogLocation(file: d.appendingPathComponent("zavod.adi")) == LogLocation(directory: d, name: "zavod"))
    #expect(LogLocation(file: d.appendingPathComponent("zavod.jsonl")).name == "zavod")
    #expect(LogLocation(file: d.appendingPathComponent("moje.log.ADIF")).name == "moje.log")
    let l = LogLocation(directory: d, name: "zavod")
    #expect(l.jsonlURL.lastPathComponent == "zavod.jsonl" && l.adifURL.lastPathComponent == "zavod.adi")
    #expect(l.qtcURL.lastPathComponent == "zavod-qtc.jsonl")
    #expect(LogLocation(directory: d, name: "mmtty4mac").qtcURL.lastPathComponent == "qtc.jsonl")   // the existing file
}

// Opening a foreign ADIF: it is converted to JSONL, the original is backed up
@Test func openForeignADIF() async throws {
    let dir = tmp()
    let adi = "<ADIF_VER:5>3.1.0 <EOH>\n<CALL:6>DL1ABC <QSO_DATE:8>20251012 <TIME_ON:4>1203 <MODE:4>RTTY <FREQ:6>14.085 <EOR>\n<CALL:3>BAD <EOR>\n"
    try adi.write(to: dir.appendingPathComponent("stary.adi"), atomically: true, encoding: .utf8)
    let loc = LogLocation(file: dir.appendingPathComponent("stary.adi"))
    let r = try await loc.prepareForOpen()
    #expect(r.imported == 1 && r.skipped == 1 && r.backup?.lastPathComponent == "stary.adi.orig")
    #expect(FileManager.default.fileExists(atPath: loc.jsonlURL.path))
    let store = try QSOLogStore(directory: loc.directory, baseName: loc.name)
    #expect(await store.records.map(\.call) == ["DL1ABC"])
    // the second time (the JSONL already exists) nothing is converted
    let again = try await loc.prepareForOpen()
    #expect(again.imported == 0 && again.backup == nil)
}

// Save as: a copy of the JSONL, ADIF and QTC files under the new name
@Test func saveLogAsCopiesFiles() async throws {
    let dir = tmp(), dst = tmp()
    let src = LogLocation(directory: dir, name: "mmtty4mac")
    let store = try QSOLogStore(directory: dir, baseName: "mmtty4mac")
    try await store.append(QSORecord(call: "OK2AA", timeOn: Date()))
    try "{}\n".write(to: src.qtcURL, atomically: true, encoding: .utf8)
    let to = LogLocation(directory: dst, name: "kopie")
    try src.copy(to: to)
    let s2 = try QSOLogStore(directory: dst, baseName: "kopie")
    #expect(await s2.records.map(\.call) == ["OK2AA"])
    #expect(FileManager.default.fileExists(atPath: to.adifURL.path) && FileManager.default.fileExists(atPath: to.qtcURL.path))
    #expect(throws: LogLocation.LocationError.self) { try src.copy(to: to) }          // the target exists
    #expect(throws: LogLocation.LocationError.self) { try src.copy(to: src) }
}
