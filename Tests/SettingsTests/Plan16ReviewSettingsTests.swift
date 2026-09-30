// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
// Plan 16 check: import from MMTTY – invalid numbers, shortcut clashes, the call, the file size; Macro.repeatSeconds.
import Foundation
import Testing
@testable import Settings

// 4: huge / negative / non-numeric numbers must not crash the import (Int(1e20) = fatal error)
@Test func mmttyImportSurvivesHugeNumbers() {
    let ini = """
    [Define]
    Tap=1e20
    DEMTYPE=1e20
    AFCFixShift=-1e300
    TxPort=1e20
    PTT=COM1
    RXlmsNotch=inf
    SmoozOrder=nan
    [MacroTimer]
    M1=1e21
    M2=-1
    M3=nan
    M4=inf
    M5=36001
    M6=1
    M7=50
    M8=0
    [MacroKey]
    M1=1e20
    M2=-1e20
    [SysKey]
    S4=1e20
    [Macro]
    M1="x"
    """
    let r = MMTTYImport.parse(text: ini)
    #expect(r.rtty["firTaps"] == nil && r.rtty["demodType"] == nil && r.rtty["afcMode"] == nil)
    #expect(r.rtty["notchFreq"] == nil && r.rtty["lpfOrder"] == nil)
    let t = r.macros?.map(\.repeatSeconds) ?? []
    #expect(t.count == 16)
    #expect(t[0] == nil && t[1] == nil && t[2] == nil && t[3] == nil && t[4] == nil)
    #expect(t[5] == 0.1 && t[6] == 5 && t[7] == nil)
    #expect(r.warnings.contains { $0.contains("3600") })
    #expect(r.shortcuts.isEmpty)
}

// 4: Macro – repeatSeconds only 0.1–3600 s (both decoding and init)
@Test func macroRepeatSecondsValidated() throws {
    func dec(_ v: String) throws -> Double? {
        try JSONDecoder().decode(Macro.self, from: Data(#"{"name":"a","text":"b","repeatSeconds":\#(v)}"#.utf8)).repeatSeconds
    }
    #expect(try dec("1e20") == nil)
    #expect(try dec("-1") == nil)
    #expect(try dec("0.05") == nil)
    #expect(try dec("5") == 5)
    #expect(Macro(name: "", text: "", repeatSeconds: .infinity).repeatSeconds == nil)
    #expect(Macro(name: "", text: "", repeatSeconds: .nan).repeatSeconds == nil)
    #expect(Macro(name: "", text: "", repeatSeconds: 1e20).repeatSeconds == nil)
    #expect(Macro(name: "", text: "", repeatSeconds: 3600).repeatSeconds == 3600)
    #expect(Macro.validRepeat(-1) == nil && Macro.validRepeat(0.1) == 0.1)
}

// 5: clashes are counted against the target settings; a clashing shortcut is not taken over
@Test func mmttyShortcutConflictsCheckedOnApply() {
    let r = MMTTYImport.parse(text: "[MacroKey]\nM1=305\nM2=113\n[SysKey]\nS4=332\n")   // ⌘1, F2, openLog ⌘L
    #expect(r.shortcuts["openLog"] == KeyBinding(key: "l", modifiers: [.command]))
    #expect(!r.warnings.contains { $0.contains("kryje") })          // the parse does not compare against the default settings
    var s = AppSettings()
    s.shortcuts["toggleTx"] = KeyBinding(key: "1", modifiers: [.command])
    let w = r.apply(to: &s, options: [.shortcuts])
    #expect(s.binding(for: .macro(0)) == KeyBinding(key: "f1"))      // ⌘1 is taken by TX → not adopted
    #expect(s.binding(for: .toggleTx) == KeyBinding(key: "1", modifiers: [.command]))
    #expect(s.binding(for: .openLog) == ShortcutCommand.openLog.defaultBinding)   // ⌘L = Log QSO
    #expect(s.conflictingShortcuts().isEmpty)
    #expect(w.count == 1 && w[0].contains("⌘1") && w[0].contains("⌘L"))
    var t = AppSettings()
    #expect(r.apply(to: &t, options: [.shortcuts]).count == 1)     // openLog only
    #expect(t.binding(for: .macro(0)) == KeyBinding(key: "1", modifiers: [.command]))
}

// 10: the call may only contain A–Z 0–9 /, 15 characters at most
@Test func mmttyImportValidatesCall() {
    #expect(MMTTYImport.parse(text: "[Define]\nCall=ok1xoe/p\n").station?.call == "OK1XOE/P")
    for bad in ["OK1 XOE", "OK1-XOE", "ABCDEFGHIJKLMNOP", "OK1XÖE", "<b>"] {
        let r = MMTTYImport.parse(text: "[Define]\nCall=\(bad)\n")
        #expect(r.station == nil, "\(bad)")
        #expect(r.warnings.contains { $0.contains(bad.uppercased()) }, "\(bad)")
    }
}

// 10: a file over 1 MB is not processed
@Test func mmttyImportRejectsHugeData() {
    let r = MMTTYImport.parse(data: Data(("[Define]\nCall=OK1XOE\n" + String(repeating: ";", count: 1_100_000)).utf8))
    #expect(r.isEmpty && !r.warnings.isEmpty)
    #expect(MMTTYImport.maxFileSize == 1_048_576)
}
