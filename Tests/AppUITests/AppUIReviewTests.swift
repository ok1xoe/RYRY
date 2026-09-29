import Foundation
import Testing
import AppCore
import Engine
import ModemKit
import Settings
import WaveFile
@testable import AppUI

// C1: po dosažení limitu musí model hlásit, kolik se ořízlo zepředu a kolik přibylo (pro inkrementální NSTextView)
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

// I3: souběžné změny nastavení se provedou postupně, žádný engine nezůstane běžet
@Test @MainActor func concurrentApplySettingsAreSerialized() async throws {
    let f = Fixture()
    await f.model.start()
    var s1 = f.model.settings; s1.station.call = "OK1AAA"
    var s2 = f.model.settings; s2.station.call = "OK2BBB"
    async let a: Void = f.model.applySettings(s1)
    async let b: Void = f.model.applySettings(s2)
    async let c: Void = f.model.start()                 // navíc start (např. druhé okno)
    _ = await (a, b, c)
    #expect(f.engines.count == 3)
    for e in f.engines.dropLast() { #expect(await e.state == .stopped) }
    #expect(await f.engine.state == .rx)
    #expect(["OK1AAA", "OK2BBB"].contains(f.model.settings.station.call))   // pořadí souběžných volání není dané
    await f.model.stop()
}

// I4: Použít nastavení nesmí vrátit parametry modemu ani makra změněná jinde
@Test @MainActor func applySettingsKeepsModemParamsAndMacros() async throws {
    let f = Fixture()
    await f.model.start()
    let draft = f.model.settings                         // dialog otevřen se starými hodnotami
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

// I6: ukončení nesmí viset – shutdown má časový limit
@Test @MainActor func shutdownHasTimeout() async throws {
    let f = Fixture()
    await f.model.start()
    let t0 = Date()
    await f.model.shutdown(timeout: .seconds(1))
    #expect(Date().timeIntervalSince(t0) < 2)
}

// Review 7: klasifikace nesmí brát šum jako značku ani čísla jako RST
@Test func stricterWordClassifier() {
    for w in ["3580", "1234", "E5T", "R5T", "1A2B"] { #expect(WordClassifier.classify(w) != .call && WordClassifier.classify(w) != .rst, "\(w)") }
    for c in ["OK1ABC", "DL1ABC/P", "W1AW", "VK2/G4ABC", "2E0XYZ"] { #expect(WordClassifier.classify(c) == .call, "\(c)") }
    for r in ["599", "579", "5NN", "599001", "59912"] { #expect(WordClassifier.classify(r) == .rst, "\(r)") }
}

// Předvolba závodu a záznam příjmu z dialogu Nastavení se po Použít uloží
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

// Nahrávání příjmu do WAV: vstup zvukovky se zapíše, po zastavení je soubor kompletní
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

// Review 4: Použít ze starší kopie dialogu nesmí vypnout záznam příjmu zapnutý v menu
@Test @MainActor func applySettingsKeepsRxLogToggledInMenu() async throws {
    let f = Fixture()
    await f.model.start()
    let draft = f.model.settings                       // dialog otevřen
    f.model.setRxTextLog(true)                         // menu Soubor
    var d = draft; d.station.call = "OK9ZZZ"
    await f.model.applySettings(d, baseline: draft)
    #expect(f.model.settings.log.rxText && f.model.rxLogActive)
    await f.model.stop()
}

// Správa logu: nový log, uložit jako, otevřít cizí ADIF; Použít ze starší kopie dialogu log nepřepne zpět
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
    await #expect(throws: (any Error).self) { try await f.model.newLog(file: newURL) }   // už existuje
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
    #expect(f.model.settings.log.name == "cizi")                     // dialog log nevrátil
    await f.model.stop()
}

// Bod 1, 2, 4: návrhy značek z logu, DUPE v závodě, ruční frekvence se pamatuje v nastavení
@Test @MainActor func scpDupeAndManualFrequency() async throws {
    let f = Fixture()
    f.configure = { $0.contest = ContestSettings.preset(.cqwpxRTTY, year: 2026); $0.contest.start = Date().addingTimeInterval(-3600) }
    await f.model.start()
    await f.model.setQSOField("freq", "14080")
    await f.model.setQSOField("call", "DL1ABC")
    await f.model.logQSO(); await f.settle()
    #expect(f.model.settings.log.manualFrequency == 14_080_000)
    await f.model.setQSOField("call", "1AB"); await f.settle()
    #expect(f.model.scpPartial == ["DL1ABC"])
    await f.model.setQSOField("call", "DL1ABX"); await f.settle()
    #expect(f.model.scpNear == ["DL1ABC"])
    await f.model.setQSOField("call", "DL1ABC"); await f.settle()
    #expect(f.model.isDupe)
    await f.model.setQSOField("freq", "7040"); await f.settle()
    #expect(!f.model.isDupe)
    await f.model.stop()
}

// Review (odloženo): selhání záznamu příjmu vypne i přepínač (menu neukazuje „zapnuto“)
@Test @MainActor func rxLogFailureTurnsToggleOff() async throws {
    let f = Fixture()
    await f.model.start()
    let blocker = URL(fileURLWithPath: f.model.settings.log.directory).appendingPathComponent("rx")
    try FileManager.default.createDirectory(at: blocker.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("x".utf8).write(to: blocker)               // místo složky rx soubor → zápis selže
    f.model.setRxTextLog(true)
    f.model.appendRx("CQ", echo: false)
    #expect(!f.model.settings.log.rxText && !f.model.rxLogActive)
    await f.model.stop()
}
