// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
@testable import AppCore

private let t0 = ISO8601DateFormatter().date(from: "2026-09-29T12:03:05Z")!

// Časová značka UTC na začátku každého řádku; CR se zahodí (RTTY posílá CR LF)
@Test func rxLogStampsLines() {
    var f = RxTextLog.Formatter(timestamps: true)
    #expect(f.format("CQ CQ", at: t0) == "12:03:05 CQ CQ")
    #expect(f.format(" DE\r\nOK1", at: t0.addingTimeInterval(2)) == " DE\n12:03:07 OK1")
    #expect(f.format("\r\n", at: t0) == "\n")
    #expect(f.format("X", at: t0) == "12:03:05 X")
    var plain = RxTextLog.Formatter(timestamps: false)
    #expect(plain.format("A\r\nB", at: t0) == "A\nB")
}

// Soubor na den UTC v podsložce rx; zápis připojuje
@Test func rxLogWritesDailyFile() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rxlog-\(UUID())")
    let log = RxTextLog(directory: dir, timestamps: true)
    try log.append("RYRY\r\n", at: t0)
    try log.append("CQ", at: t0)
    try log.append("X", at: t0.addingTimeInterval(86_400))
    log.close()
    let a = try String(contentsOf: dir.appendingPathComponent("rx-2026-09-29.txt"), encoding: .utf8)
    #expect(a == "12:03:05 RYRY\n12:03:05 CQ")
    let b = try String(contentsOf: dir.appendingPathComponent("rx-2026-09-30.txt"), encoding: .utf8)
    #expect(b == "12:03:05 X")                   // nový den = nový soubor od začátku řádku
}

// Odeslání textového souboru (MMTTY „Send Text“): konce řádků CR LF, tabulátor = mezera, bez řídicích znaků
@Test func fileTextNormalization() throws {
    #expect(try AppController.fileText(Data("CQ\tTEST\nDE OK1XOE\r\nK\u{07}".utf8)) == "CQ TEST\r\nDE OK1XOE\r\nK")
    #expect(try AppController.fileText(Data([0x50, 0xF8, 0x0A])) == "Pø\r\n")          // Latin-1 náhradou
    #expect(throws: AppController.FileTextError.self) { try AppController.fileText(Data()) }
    #expect(throws: AppController.FileTextError.self) { try AppController.fileText(Data(repeating: 65, count: 20_001)) }
}
