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
    // an old file with none of the new sections and with 12 macros → the default values, the macros padded to 16
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

// Review I-4: the old default contest macro with %M (the received number) → %N (the sent one, as in MMTTY)
@Test func oldDefaultContestMacroMigrated() throws {
    let dir = tmp()
    let old = #"{"macros":[{"name":"Contest","text":"\r\n%c 599 %M %M %c\r\n\\"},{"name":"Mine","text":"%M"}]}"#
    try old.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    let s = SettingsStore(directory: dir).load().0
    #expect(s.macros[0].text == "\r\n%c 599 %N %N %c\r\n\\")
    #expect(s.macros[1].text == "%M")                         // the user's own macros are left alone
    #expect(AppSettings.defaultMacros.allSatisfy { !$0.text.contains("%M") })
}

// Plan 8 / T1, T2
@Test func messagesAndMacroColors() throws {
    let s0 = AppSettings()
    #expect(s0.messages.count >= 3 && s0.messages.allSatisfy { !$0.name.isEmpty && !$0.text.isEmpty })
    let store = SettingsStore(directory: tmp())
    var s = AppSettings()
    s.messages = [Macro(name: "Rig", text: "RIG IS IC-7300 %m\\")]
    s.macros[0].color = "#FF8800"
    try store.save(s)
    let l = store.load().0
    #expect(l.messages.count == 1 && l.messages[0].name == "Rig")
    #expect(l.macros[0].color == "#FF8800" && l.macros[1].color == nil)
    // an invalid colour → no colour, an old file with no messages → the defaults
    let dir = tmp()
    try ##"{"macros":[{"name":"A","text":"x","color":"orange"},{"name":"B","text":"y","color":"#12345G"}]}"##
        .write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    let o = SettingsStore(directory: dir).load().0
    #expect(o.macros[0].color == nil && o.macros[1].color == nil)
    #expect(o.messages == AppSettings.defaultMessages)
}

// OK DX RTTY Contest: the Saturday of the 3rd full weekend in December, 00–24 UTC; the exchange is RST + CQ zone
@Test func contestPresets() {
    let ok = ContestSettings.preset(.okDXRTTY, year: 2026)
    #expect(ok.enabled && ok.format == .zone && ok.name == "OK-DX-RTTY")
    #expect(ok.start == ISO8601DateFormatter().date(from: "2026-12-19T00:00:00Z"))
    #expect(ContestSettings.preset(.okDXRTTY, year: 2027).start == ISO8601DateFormatter().date(from: "2027-12-18T00:00:00Z"))
    let wae = ContestSettings.preset(.waeRTTY, year: 2026)
    #expect(wae.format == .wae && wae.name == "DARC-WAEDC-RTTY" && wae.start == ISO8601DateFormatter().date(from: "2026-11-14T00:00:00Z"))
}

// The preset palette: the start dates follow the usual rules (a full weekend = both the Saturday and the Sunday within the month)
@Test func contestPresetCalendar() {
    let iso = ISO8601DateFormatter()
    let cases: [(ContestPreset, Int, String, ContestFormat, String)] = [
        (.arrlRoundup, 2027, "ARRL-RTTY", .serial, "2027-01-02T18:00:00Z"),
        (.cqwpxRTTY, 2027, "CQ-WPX-RTTY", .serial, "2027-02-13T00:00:00Z"),
        (.bartgHF, 2027, "BARTG-RTTY", .bartg, "2027-03-20T02:00:00Z"),
        (.sartgRTTY, 2026, "SARTG-RTTY", .serial, "2026-08-15T00:00:00Z"),
        (.cqwwRTTY, 2026, "CQ-WW-RTTY", .cqrj, "2026-09-26T00:00:00Z"),
        (.makrothen, 2026, "MAKROTHEN-RTTY", .serial, "2026-10-10T00:00:00Z"),
        (.jartsRTTY, 2026, "JARL-WW-RTTY", .serial, "2026-10-17T00:00:00Z"),
    ]
    for (p, y, name, f, start) in cases {
        let c = ContestSettings.preset(p, year: y)
        #expect(c.enabled && c.name == name && c.format == f, "\(p)")
        #expect(c.start == iso.date(from: start), "\(p)")
        #expect(ContestPreset.matching(c) == p, "\(p)")
    }
    #expect(ContestPreset.allCases.count == 28)
}

// The selected preset is recognised from the name and the format; a manual edit = custom settings
@Test func contestPresetMatching() {
    var c = ContestSettings.preset(.waeRTTY, year: 2026)
    #expect(ContestPreset.matching(c) == .waeRTTY)
    c.name = "MUJ-ZAVOD"
    #expect(ContestPreset.matching(c) == nil)
    #expect(ContestPreset.matching(ContestSettings()) == nil)
}

// The nearest date: this year's if it has not ended yet, otherwise next year's
@Test func contestPresetUpcoming() {
    let iso = ISO8601DateFormatter()
    let now = iso.date(from: "2026-09-29T12:00:00Z")!
    #expect(ContestSettings.upcoming(.cqwwRTTY, now: now).start == iso.date(from: "2027-09-25T00:00:00Z"))
    #expect(ContestSettings.upcoming(.makrothen, now: now).start == iso.date(from: "2026-10-10T00:00:00Z"))
    // the contest is running right now → this year's
    #expect(ContestSettings.upcoming(.cqwwRTTY, now: iso.date(from: "2026-09-27T10:00:00Z")!).start
            == iso.date(from: "2026-09-26T00:00:00Z"))
}

// Makrothen: the exchange = a 4-character locator
@Test func makrothenUsesLocator() {
    #expect(ContestSettings.preset(.makrothen, year: 2026, locator: "jo70fb").exchange == "JO70")
    #expect(ContestSettings.preset(.makrothen, year: 2026).exchange == "")
}

// "Custom settings" are stored and survive even with a name and a format identical to a preset
@Test func contestPresetChoicePersists() throws {
    let dir = tmp()
    var s = AppSettings()
    s.contest = ContestSettings.preset(.waeRTTY, year: 2026)
    #expect(s.contest.preset == .waeRTTY)
    s.contest.preset = nil
    try SettingsStore(directory: dir).save(s)
    let loaded = SettingsStore(directory: dir).load().0
    #expect(loaded.contest.preset == nil && loaded.contest.name == "DARC-WAEDC-RTTY")
    // a format change outside a preset → custom
    var c = ContestSettings.preset(.cqwpxRTTY, year: 2027); c.format = .bartg
    #expect(c.selectedPreset == nil)
    #expect(ContestSettings.preset(.cqwpxRTTY, year: 2027).selectedPreset == .cqwpxRTTY)
}

// An older settings.json with no preset field: the preset is derived from the name and the format
@Test func contestPresetLegacyDecode() throws {
    let dir = tmp()
    try #"{"contest":{"enabled":true,"format":"wae","name":"WAEDC"}}"#
        .write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    #expect(SettingsStore(directory: dir).load().0.contest.preset == .waeRTTY)
}
