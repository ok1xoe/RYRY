// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
@testable import Settings

@Test func plan13Defaults() {
    let s = AppSettings()
    #expect(!s.txWindow.autoCRLF && s.txWindow.wrapColumn == 0)
    #expect(s.display.palette == .classic && s.display.fftResponse == .normal)
    #expect(s.display.xySize == .medium && s.display.xyQuality == .high && s.display.showHints)
    #expect(s.display.rxFont.isEmpty && s.display.rxBackground == nil && s.display.rxEchoColor == nil)
    #expect(s.shortcuts.isEmpty && !s.log.rxText && s.log.rxTimestamps)
}

@Test func plan13RoundTripAndTolerance() throws {
    let dir = tmp()
    var s = AppSettings()
    s.txWindow.autoCRLF = true; s.txWindow.wrapColumn = 64
    s.display.palette = .heat; s.display.fftResponse = .slow; s.display.xySize = .large; s.display.xyQuality = .low
    s.display.showHints = false; s.display.rxFont = "Menlo"; s.display.rxBackground = "#000000"; s.display.rxTextColor = "#00FF00"
    s.shortcuts["macro.0"] = KeyBinding(key: "1", modifiers: [.option])
    s.log.rxText = true
    try SettingsStore(directory: dir).save(s)
    #expect(SettingsStore(directory: dir).load().0 == s)
    try #"{"txWindow":{"wrapColumn":-5},"display":{"palette":"neon","fftResponse":"slow","rxBackground":"blue"},"shortcuts":{"x":{"key":""}}}"#
        .write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    let o = SettingsStore(directory: dir).load().0
    #expect(o.txWindow.wrapColumn == 0 && o.display.palette == .classic && o.display.fftResponse == .slow)
    #expect(o.display.rxBackground == nil)                       // neplatná barva
    #expect(o.shortcuts.isEmpty)                                 // neplatná zkratka
}

@Test func keyBindings() {
    #expect(KeyBinding(key: "F2", modifiers: [.shift]).display == "⇧F2")
    #expect(KeyBinding(key: "1", modifiers: [.command, .option, .option]).display == "⌥⌘1")
    #expect(KeyBinding(key: "return", modifiers: [.control]).display == "⌃↩")
    #expect(RigSettings().catRTS == nil)
    #expect(KeyBinding(key: "f13").isValid && KeyBinding.none.isValid)
    #expect(!KeyBinding(key: "a").isValid)                       // samotné písmeno – kolize s psaním
    #expect(!KeyBinding(key: "space").isValid && !KeyBinding(key: "return").isValid && !KeyBinding(key: "left").isValid)
    #expect(KeyBinding(key: "return", modifiers: [.command]).isValid)
    #expect(!KeyBinding(key: "f21").isValid && !KeyBinding(key: "").isValid && !KeyBinding(key: "ab", modifiers: [.command]).isValid)
    var s = AppSettings()
    #expect(s.binding(for: .macro(12)) == KeyBinding(key: "f1", modifiers: [.shift]))
    #expect(s.binding(for: .toggleTx).display == "⌘T" && s.binding(for: .tune).isNone)
    #expect(s.conflictingShortcuts().isEmpty)
    s.shortcuts["tune"] = KeyBinding(key: "f1")
    #expect(s.conflictingShortcuts() == [[.macro(0), .tune]])
}

// CAT přes USB: vestavěný protokol nebo hamlib spuštěný aplikací
@Test func rigCATSettings() throws {
    var r = RigSettings()
    #expect(r.catProtocol == .icom && r.civAddress == 0x94 && r.baud == 19200 && r.stopBits == 1 && r.hamlibModel == 1)
    r.type = .cat; r.catProtocol = .yaesu; r.serialPort = "/dev/cu.SLAB_USBtoUART"; r.baud = 38400; r.stopBits = 2
    var s = AppSettings(); s.rig = r
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rig-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try SettingsStore(directory: dir).save(s)
    #expect(SettingsStore(directory: dir).load().0.rig == r)
    try #"{"rig":{"type":"hamlibManaged","baud":-3,"stopBits":7,"civAddress":999,"hamlibModel":0}}"#
        .write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    let o = SettingsStore(directory: dir).load().0.rig
    #expect(o.type == .hamlibManaged && o.baud == 19200 && o.stopBits == 1 && o.civAddress == 0x94 && o.hamlibModel == 1)
    #expect(RigSettings.icomAddresses.first { $0.0 == "IC-7300" }?.1 == 0x94)
}
