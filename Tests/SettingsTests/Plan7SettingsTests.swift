import Foundation
import Testing
@testable import Settings

@Test func plan7Defaults() {
    let s = AppSettings()
    #expect(s.clock.rxPPM == 0 && s.clock.txPPM == 0)
    #expect(!s.rttyCore.japanese && !s.rttyCore.doubleShift && s.rttyCore.txUOS)
    #expect(!s.contest.enabled && s.contest.nextSerial == 1 && s.contest.name.isEmpty)
    #expect(s.display.fromHz == 0 && s.display.toHz == 3000 && s.display.gainDB == 0 && s.display.autoGain)
    #expect(!s.display.timestamps && s.display.fontSize == 14)
    #expect(s.macros.count == 16)
}

@Test func plan7RoundTripAndTolerance() throws {
    let store = SettingsStore(directory: tmp())
    var s = AppSettings()
    s.clock.rxPPM = 12.5; s.clock.txPPM = -3
    s.rttyCore.japanese = true; s.rttyCore.doubleShift = true; s.rttyCore.txUOS = false
    s.contest.enabled = true; s.contest.name = "BARTG-RTTY"; s.contest.nextSerial = 42; s.contest.category = "SINGLE-OP ALL LOW"
    s.contest.exchange = "DL"
    s.display.fromHz = 1500; s.display.toHz = 2500; s.display.gainDB = 6; s.display.autoGain = false
    s.display.timestamps = true; s.display.fontSize = 18
    try store.save(s)
    #expect(store.load().0 == s)
    // starý soubor bez nových sekcí a s 12 makry → výchozí hodnoty, makra doplněná na 16
    let dir = tmp()
    let old = #"{"schemaVersion":1,"macros":[{"name":"A","text":"x"},{"name":"B","text":"y"}],"clock":{"rxPPM":"bad"}}"#
    try old.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    let (loaded, warnings) = SettingsStore(directory: dir).load()
    #expect(loaded.macros.count == 16)
    #expect(loaded.macros[0].name == "A" && loaded.macros[15].name == "")
    #expect(loaded.clock.rxPPM == 0)
    #expect(!warnings.isEmpty)
}

@Test func clockPPMIsClamped() {
    var c = ClockSettings()
    c.rxPPM = 50_000
    #expect(c.clampedRx == 20_000)
    c.txPPM = -99_999
    #expect(c.clampedTx == -20_000)
}

// Review I-4: staré výchozí závodní makro s %M (přijaté číslo) → %N (odesílané, jako MMTTY)
@Test func oldDefaultContestMacroMigrated() throws {
    let dir = tmp()
    let old = #"{"macros":[{"name":"Contest","text":"\r\n%c 599 %M %M %c\r\n\\"},{"name":"Mine","text":"%M"}]}"#
    try old.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    let s = SettingsStore(directory: dir).load().0
    #expect(s.macros[0].text == "\r\n%c 599 %N %N %c\r\n\\")
    #expect(s.macros[1].text == "%M")                         // vlastní makra se nemění
    #expect(AppSettings.defaultMacros.allSatisfy { !$0.text.contains("%M") })
}
