import Foundation
import Testing
@testable import Settings

private func decode(_ json: String) throws -> AppSettings {
    try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
}

@Test func esmDefaults() {
    let e = ESMSettings()
    #expect(!e.enabled && e.mode == .run)
    #expect(e.runCQ == 0 && e.runExchange == 3 && e.runTU == 4)
    #expect(e.spMyCall == 14 && e.spExchange == 3 && e.agn == 10)
    #expect(AppSettings().esm == e)
    // the default "My call" macro on ⇧F3
    #expect(AppSettings.defaultMacros[14].text.contains("%m"))
    #expect(!AppSettings.defaultMacros[14].name.isEmpty)
    #expect(AppSettings.defaultMacros[15].text.isEmpty)
}

@Test func esmRoundTripAndTolerantDecode() throws {
    var s = AppSettings()
    s.esm.enabled = true; s.esm.mode = .sp; s.esm.spMyCall = 7; s.esm.agn = 11
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    #expect(back.esm == s.esm)
    // invalid values → the defaults, an index outside 0…15 → the default
    let t = try decode(#"{"esm":{"enabled":"x","mode":"weird","runCQ":99,"runTU":-1,"spExchange":5}}"#)
    #expect(!t.esm.enabled && t.esm.mode == .run && t.esm.runCQ == 0 && t.esm.runTU == 4 && t.esm.spExchange == 5)
}

@Test func esmMigrationFillsEmptyMyCallSlot() throws {
    // an older file with no esm section and an empty ⇧F3 → the default "My call" is filled in
    var macros = Array(repeating: #"{"name":"","text":""}"#, count: 16)
    macros[0] = #"{"name":"A","text":"x"}"#
    let old = try decode(#"{"macros":[\#(macros.joined(separator: ","))]}"#)
    #expect(old.macros[14] == AppSettings.defaultMacros[14])
    #expect(old.macros[0].name == "A" && old.macros[15].text.isEmpty)
    // custom content of ⇧F3 is left alone
    macros[14] = #"{"name":"Mine","text":"abc"}"#
    let own = try decode(#"{"macros":[\#(macros.joined(separator: ","))]}"#)
    #expect(own.macros[14].name == "Mine")
    // with a stored esm section an empty macro is no longer filled in (the user may have deleted it)
    macros[14] = #"{"name":"","text":""}"#
    let cleared = try decode(#"{"esm":{},"macros":[\#(macros.joined(separator: ","))]}"#)
    #expect(cleared.macros[14].text.isEmpty)
}

@Test func esmModeShortcut() {
    let s = AppSettings()
    #expect(ShortcutCommand.allCases.contains(.esmMode))
    #expect(s.binding(for: .esmMode) == KeyBinding(key: "r", modifiers: [.control]))
    #expect(s.conflictingShortcuts().isEmpty)
}
