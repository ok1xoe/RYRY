// Copyright 2026 OK1XOE (RYRY), LGPL v3
// Plan 16 check: ESM, import from MMTTY, the band map in RTTY/FSK, backups.
import Foundation
import Testing
import AppCore
import Engine
import QSOLog
import Settings
import Spots
@testable import AppUI

@MainActor private func esmFixture(_ extra: @escaping (inout AppSettings) -> Void = { _ in }) -> Fixture {
    let fx = Fixture()
    fx.configure = { s in
        s.contest.enabled = true; s.contest.format = .serial
        s.esm.enabled = true; s.esm.mode = .run
        extra(&s)
    }
    return fx
}

@MainActor private func drain(_ f: Fixture) async {
    for _ in 0..<600 { await f.pump(); if await f.engine.state == .rx { break } }
    await f.settle()
}

// 1: an empty macro does not start ESM (TX would hang), only a message
@Test @MainActor func esmEmptyMacroDoesNotKeyTransmitter() async throws {
    let f = esmFixture { s in s.macros[0] = Macro(name: "CQ", text: " \r\n ") }
    await f.model.start()
    #expect(f.model.esmStep == .cq)
    #expect(await f.model.esmEnter() == nil)
    await f.pump(3)
    #expect(await f.engine.state == .rx)
    #expect(f.model.lastESMMacroForTesting == nil)
    #expect(f.model.messages.contains { $0.contains("prázdné") && $0.contains("ESM") })
    #expect(f.model.esmMacroIsEmpty(0) && !f.model.esmMacroIsEmpty(3))
    await f.model.stop()
}

// 1: the general safeguard – a macro with no text does not key up, %l alone only logs
@Test @MainActor func emptyMacroDoesNotKeyButStillLogs() async throws {
    let f = Fixture()
    f.configure = { s in s.macros[15] = Macro(name: "", text: ""); s.macros[14] = Macro(name: "Log", text: "%l") }
    await f.model.start()
    await f.model.runMacro(15)
    await f.pump(3)
    #expect(await f.engine.state == .rx)
    await f.model.setQSOField("call", "DL1ABC")
    await f.model.runMacro(14)
    await f.pump(3)
    #expect(await f.engine.state == .rx)
    for _ in 0..<50 where f.model.logRecords.isEmpty { await f.settle() }
    #expect(f.model.logRecords.first?.call == "DL1ABC")
    await f.model.stop()
}

// 2: Enter held down / pressed quickly – a second Enter while the first is being processed is ignored
@Test @MainActor func esmEnterIgnoresSecondEnterWhileBusy() async throws {
    let f = esmFixture()
    await f.model.start()
    async let a = f.model.esmEnter()
    async let b = f.model.esmEnter()
    let (ra, rb) = await (a, b)
    #expect(f.model.esmSendCountForTesting == 1)
    #expect((ra == nil) != (rb == nil))
    await f.model.stop()
}

// 3: TU with %l – after esmEnter returns the QSO is already logged and empty (the old exchange does not carry into the next QSO)
@Test @MainActor func esmRunTUClearsQSOBeforeReturning() async throws {
    let f = esmFixture()
    await f.model.start()
    await f.model.setQSOField("call", "DL1ABC")
    _ = await f.model.esmEnter()                                   // the exchange
    await drain(f)
    await f.model.setQSOField("serialRcvd", "12")
    #expect(f.model.esmStep == .tu)
    #expect(await f.model.esmEnter() == "call")
    #expect(f.model.qso.call.isEmpty)
    #expect(f.model.qso.serialRcvd == nil && f.model.qso.exchangeRcvd.isEmpty)
    await drain(f)
    #expect(f.model.esmStep == .cq)
    for _ in 0..<50 where f.model.logRecords.isEmpty { await f.settle() }
    #expect(f.model.logRecords.count == 1 && f.model.logRecords.first?.serialRcvd == 12)
    await f.model.stop()
}

// 6: an import during TX – RX first and stop the repeat
@Test @MainActor func mmttyImportStopsTransmission() async throws {
    let f = Fixture()
    await f.model.start()
    await f.model.toggleTx()
    await f.pump(5)
    #expect(await f.engine.state != .rx)
    let r = MMTTYImport.parse(text: "[MsgName]\nM1=A\n[MsgList]\nM1=\"x\"\n")
    await f.model.applyMMTTYImport(r, options: [.messages])
    await f.pump(3)
    await f.settle()
    #expect(await f.engine.state == .rx)
    await f.model.stop()
}

// 6: importing macros with ESM enabled – a warning and optionally turning ESM off
@Test @MainActor func mmttyImportMacrosWithESMCanDisableESM() async throws {
    let f = esmFixture()
    await f.model.start()
    let r = MMTTYImport.parse(text: "[Macro]\nM1=\"CQ\"\n")
    #expect(f.model.mmttyImportAffectsESM(r, options: .all))
    #expect(!f.model.mmttyImportAffectsESM(r, options: [.messages]))
    await f.model.applyMMTTYImport(r, options: .all, disableESM: true)
    #expect(!f.model.settings.esm.enabled)
    #expect(!SettingsStore(directory: f.dir).load().0.esm.enabled)
    #expect(!f.model.mmttyImportAffectsESM(r, options: .all))
    await f.model.stop()
}

// 5: shortcut clashes against the current settings – a clashing one is not taken over, a warning is shown
@Test @MainActor func mmttyImportShortcutConflictAgainstCurrentSettings() async throws {
    let f = Fixture()
    f.configure = { s in s.shortcuts["toggleTx"] = KeyBinding(key: "1", modifiers: [.command]) }
    await f.model.start()
    let r = MMTTYImport.parse(text: "[MacroKey]\nM1=305\nM2=376\n")       // ⌘1 (clashes), ⌘F9
    await f.model.applyMMTTYImport(r, options: [.shortcuts])
    #expect(f.model.settings.binding(for: .macro(0)) == KeyBinding(key: "f1"))
    #expect(f.model.settings.binding(for: .macro(1)) == KeyBinding(key: "f9", modifiers: [.command]))
    #expect(f.model.settings.conflictingShortcuts().isEmpty)
    #expect(f.model.messages.contains { $0.contains("⌘1") })
    await f.model.stop()
}

// 10: a file larger than 1 MB is not read
@Test @MainActor func mmttyImportRejectsHugeFile() throws {
    let f = Fixture()
    let url = f.dir.appendingPathComponent("big.ini")
    try Data(repeating: 0x41, count: 1_100_000).write(to: url)
    #expect(throws: (any Error).self) { try f.model.previewMMTTYImport(url) }
}

// 7: the band map in RTTY/FSK – audio = the current mark + (dial − spot)
@Test func bandMapMarkersUseCurrentMarkInRTTYMode() {
    let spot = Spot(frequencyKHz: 14_079.5, call: "DL1ABC", spotter: "X", comment: "RTTY", time: Date(), mode: "RTTY", source: .rbn)
    let m = AppModel.bandMapMarkers(spots: [spot], dialHz: 14_080_000, mode: "RTTY", offsetHz: 0, markHz: 2000,
                                    fromHz: 0, toHz: 4000, records: [], contestSince: nil)
    #expect(m.first?.audioHz == 2500)
}

// 9: automatic backup – no overlapping runs and a failure reported only once
@Test @MainActor func autoBackupDoesNotOverlapAndReportsFailureOnce() async throws {
    let f = Fixture()
    f.configure = { s in s.log.backup = true }
    let loc = f.model.logLocation
    try FileManager.default.createDirectory(at: loc.directory, withIntermediateDirectories: true)
    try "{}\n".write(to: loc.jsonlURL, atomically: true, encoding: .utf8)
    try "blokuje".write(to: LogBackup.directory(for: loc), atomically: true, encoding: .utf8)   // a file instead of a folder
    let t1 = f.model.backupLogIfDue(), t2 = f.model.backupLogIfDue()
    #expect(t1 != nil && t2 == nil)
    await t1?.value
    await f.model.backupLogIfDue()?.value
    await f.model.backupLogIfDue()?.value
    #expect(f.model.messages.filter { $0.contains("Záloha") }.count == 1)
}

// 9: a manual backup does not block the MainActor (async)
@Test @MainActor func manualBackupIsAsync() async throws {
    let f = Fixture()
    let loc = f.model.logLocation
    try FileManager.default.createDirectory(at: loc.directory, withIntermediateDirectories: true)
    try "{}\n".write(to: loc.jsonlURL, atomically: true, encoding: .utf8)
    let dir = try await f.model.backupLogNow()
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(loc.jsonlURL.lastPathComponent).path))
}

// 8: the speed in the status bar is computed for the given time (TimelineView) – with no traffic it drops
@Test @MainActor func contestRateDropsWithoutTraffic() async throws {
    let f = Fixture()
    f.configure = { s in s.contest.enabled = true; s.contest.format = .serial }
    await f.model.start()
    await f.model.setQSOField("call", "DL1ABC")
    await f.model.logQSO()
    for _ in 0..<50 where f.model.logRecords.isEmpty { await f.settle() }
    let now = Date()
    #expect(f.model.logStats(now: now).rate10 == 6)
    #expect(f.model.logStats(now: now.addingTimeInterval(11 * 60)).rate10 == 0)
    #expect(f.model.logStats(now: now.addingTimeInterval(61 * 60)).rate60 == 0)
    await f.model.stop()
}
