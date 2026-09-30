import Foundation
import Testing
import AppCore
import Engine
import ModemKit
import Settings
import WaveFile
@testable import AppUI

// C1: once the limit is reached the model must report how much was trimmed from the front and how much was added (incremental NSTextView)
@Test @MainActor func rxCountersTrackTrimAndAppend() {
    let f = Fixture()
    f.model.appendRx(String(repeating: "A", count: AppModel.rxLimit), echo: false)
    let appended0 = f.model.rxAppendedTotal, trimmed0 = f.model.rxTrimmedTotal
    f.model.appendRx("XYZ", echo: true)
    #expect(f.model.rxAppendedTotal - appended0 == 3)
    #expect(f.model.rxTrimmedTotal - trimmed0 == 3)
    #expect(f.model.rxCharCount == AppModel.rxLimit)
    let tail = f.model.rxTail(5)
    #expect(tail.map(\.text).joined() == "AAXYZ")
    #expect(tail.last?.echo == true && tail.first?.echo == false)
}

// I3: concurrent settings changes are applied one after another, no engine is left running
@Test @MainActor func concurrentApplySettingsAreSerialized() async throws {
    let f = Fixture()
    await f.model.start()
    var s1 = f.model.settings; s1.station.call = "OK1AAA"
    var s2 = f.model.settings; s2.station.call = "OK2BBB"
    async let a: Void = f.model.applySettings(s1)
    async let b: Void = f.model.applySettings(s2)
    async let c: Void = f.model.start()                 // one extra start (e.g. a second window)
    _ = await (a, b, c)
    #expect(f.engines.count == 3)
    for e in f.engines.dropLast() { #expect(await e.state == .stopped) }
    #expect(await f.engine.state == .rx)
    #expect(["OK1AAA", "OK2BBB"].contains(f.model.settings.station.call))   // the order of concurrent calls is not defined
    await f.model.stop()
}

// I4: Apply settings must not revert modem parameters or macros changed elsewhere
@Test @MainActor func applySettingsKeepsModemParamsAndMacros() async throws {
    let f = Fixture()
    await f.model.start()
    let draft = f.model.settings                         // the dialog was opened with the old values
    await f.model.setParam("demodType", .string("pll"))
    var m = f.model.settings.macros; m[0].text = "NEW CQ"
    await f.model.saveMacros(m)
    var d = draft; d.station.call = "OK9ZZZ"
    await f.model.applySettings(d)
    #expect(f.model.settings.station.call == "OK9ZZZ")
    #expect(f.model.settings.rtty["demodType"] == .string("pll"))
    #expect(f.model.settings.macros[0].text == "NEW CQ")
    #expect(await f.engine.modemParam("demodType") == .string("pll"))
    await f.model.stop()
}

// I6: quitting must not hang – shutdown has a timeout
@Test @MainActor func shutdownHasTimeout() async throws {
    let f = Fixture()
    await f.model.start()
    let t0 = Date()
    await f.model.shutdown(timeout: .seconds(1))
    #expect(Date().timeIntervalSince(t0) < 2)
}

// Review 7: the classifier must not take noise for a call or numbers for an RST
@Test func stricterWordClassifier() {
    for w in ["3580", "1234", "E5T", "R5T", "1A2B"] { #expect(WordClassifier.classify(w) != .call && WordClassifier.classify(w) != .rst, "\(w)") }
    for c in ["OK1ABC", "DL1ABC/P", "W1AW", "VK2/G4ABC", "2E0XYZ"] { #expect(WordClassifier.classify(c) == .call, "\(c)") }
    for r in ["599", "579", "5NN", "599001", "59912"] { #expect(WordClassifier.classify(r) == .rst, "\(r)") }
}

// The contest preset and the receive log from the Settings dialog are stored on Apply
@Test @MainActor func applySettingsTakesPresetAndRxLog() async throws {
    let f = Fixture()
    await f.model.start()
    var d = f.model.settings
    d.contest = ContestSettings.preset(.waeRTTY, year: 2026)
    await f.model.applySettings(d, baseline: f.model.settings)
    #expect(f.model.settings.contest.preset == .waeRTTY)
    let base = f.model.settings
    d = base; d.contest.preset = nil
    d.log.rxText = true
    await f.model.applySettings(d, baseline: base)
    #expect(f.model.settings.contest.preset == nil)
    #expect(f.model.settings.log.rxText && f.model.rxLogActive)
    await f.model.stop()
}

// Recording the receive path into a WAV: the sound card input is written, the file is complete after stopping
@Test @MainActor func recordsInputToWAV() async throws {
    let f = Fixture()
    await f.model.start()
    let url = f.dir.appendingPathComponent("rec.wav")
    try await f.model.startRecordingWAV(to: url)
    #expect(f.model.recordingURL == url)
    f.audio.feedRx([Float](repeating: 0.25, count: 11025))
    await f.pump(40)
    await f.model.stopRecordingWAV()
    #expect(f.model.recordingURL == nil)
    let (s, rate) = try WaveFile.read(from: url)
    #expect(rate == 11025 && s.count == 11025)
    await f.model.stop()
}

// Review 4: Apply from an older copy of the dialog must not turn off the receive log enabled from the menu
@Test @MainActor func applySettingsKeepsRxLogToggledInMenu() async throws {
    let f = Fixture()
    await f.model.start()
    let draft = f.model.settings                       // the dialog is open
    f.model.setRxTextLog(true)                         // the File menu
    var d = draft; d.station.call = "OK9ZZZ"
    await f.model.applySettings(d, baseline: draft)
    #expect(f.model.settings.log.rxText && f.model.rxLogActive)
    await f.model.stop()
}

// Log management: new log, save as, open a foreign ADIF; Apply from an older copy of the dialog does not switch the log back
@Test @MainActor func logManagement() async throws {
    let f = Fixture()
    await f.model.start()
    let draft = f.model.settings
    await f.model.setQSOField("call", "OK1AAA")
    await f.model.logQSO(); await f.settle()
    #expect(f.model.logRecords.count == 1)

    let newURL = f.dir.appendingPathComponent("zavody/cq-ww.adi")
    try await f.model.newLog(file: newURL)
    #expect(f.model.settings.log.name == "cq-ww" && f.model.logRecords.isEmpty)
    #expect(f.model.settings.log.recent.first == newURL.standardizedFileURL.path)

    await f.model.setQSOField("call", "OK2BBB")
    await f.model.logQSO(); await f.settle()
    await #expect(throws: (any Error).self) { try await f.model.newLog(file: newURL) }   // already exists
    let copyURL = f.dir.appendingPathComponent("kopie.adi")
    try await f.model.saveLogAs(file: copyURL)
    #expect(f.model.settings.log.name == "kopie" && f.model.logRecords.map(\.call) == ["OK2BBB"])

    let foreign = f.dir.appendingPathComponent("cizi.adi")
    try "<EOH>\n<CALL:5>W1ABC <QSO_DATE:8>20251012 <TIME_ON:4>1203 <MODE:4>RTTY <EOR>\n".write(to: foreign, atomically: true, encoding: .utf8)
    let msg = try await f.model.openLog(file: foreign)
    #expect(msg.contains("1"))
    #expect(f.model.settings.log.name == "cizi" && f.model.logRecords.map(\.call) == ["W1ABC"])

    var d = draft; d.station.call = "OK9ZZZ"
    await f.model.applySettings(d, baseline: draft)
    #expect(f.model.settings.log.name == "cizi")                     // the dialog did not revert the log
    await f.model.stop()
}

// Items 1, 2, 4: call suggestions from the log, DUPE in a contest, the manual frequency is remembered in the settings
@Test @MainActor func scpDupeAndManualFrequency() async throws {
    let f = Fixture()
    f.configure = { $0.contest = ContestSettings.preset(.cqwpxRTTY, year: 2026); $0.contest.start = Date().addingTimeInterval(-3600) }
    await f.model.start()
    /// Waits for a condition (an asynchronous model update) instead of a fixed delay – stable even under load.
    func until(_ c: () -> Bool) async { for _ in 0..<300 where !c() { try? await Task.sleep(for: .milliseconds(10)) } }
    await f.model.setQSOField("freq", "14080")
    await f.model.setQSOField("call", "DL1ABC")
    await f.model.logQSO()
    // in a contest the QSO window is cleared asynchronously after logging – wait so that a late event does not overwrite the next entry
    await until { f.model.settings.log.manualFrequency == 14_080_000 && f.model.scpCount > 0 && f.model.qso.call.isEmpty }
    #expect(f.model.settings.log.manualFrequency == 14_080_000)
    await f.model.setQSOField("call", "1AB"); await until { f.model.scpPartial == ["DL1ABC"] }
    #expect(f.model.scpPartial == ["DL1ABC"])
    await f.model.setQSOField("call", "DL1ABX"); await until { f.model.scpNear == ["DL1ABC"] }
    #expect(f.model.scpNear == ["DL1ABC"])
    await f.model.setQSOField("call", "DL1ABC"); await until { f.model.isDupe }
    #expect(f.model.isDupe)
    await f.model.setQSOField("freq", "7040"); await until { !f.model.isDupe }
    #expect(!f.model.isDupe)
    await f.model.stop()
}

// Review (deferred): a failure of the receive log also turns the switch off (the menu does not show "on")
@Test @MainActor func rxLogFailureTurnsToggleOff() async throws {
    let f = Fixture()
    await f.model.start()
    let blocker = URL(fileURLWithPath: f.model.settings.log.directory).appendingPathComponent("rx")
    try FileManager.default.createDirectory(at: blocker.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: blocker)               // a file instead of the rx folder → the write fails
    f.model.setRxTextLog(true)
    f.model.appendRx("CQ", echo: false)
    #expect(!f.model.settings.log.rxText && !f.model.rxLogActive)
    await f.model.stop()
}
