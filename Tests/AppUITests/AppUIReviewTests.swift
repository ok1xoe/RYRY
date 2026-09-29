import Foundation
import Testing
import AppCore
import Engine
import ModemKit
import Settings
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
