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
    // výchozí makro „Moje značka“ na ⇧F3
    #expect(AppSettings.defaultMacros[14].text.contains("%m"))
    #expect(!AppSettings.defaultMacros[14].name.isEmpty)
    #expect(AppSettings.defaultMacros[15].text.isEmpty)
}

@Test func esmRoundTripAndTolerantDecode() throws {
    var s = AppSettings()
    s.esm.enabled = true; s.esm.mode = .sp; s.esm.spMyCall = 7; s.esm.agn = 11
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    #expect(back.esm == s.esm)
    // neplatné hodnoty → výchozí, index mimo 0…15 → výchozí
    let t = try decode(#"{"esm":{"enabled":"x","mode":"weird","runCQ":99,"runTU":-1,"spExchange":5}}"#)
    #expect(!t.esm.enabled && t.esm.mode == .run && t.esm.runCQ == 0 && t.esm.runTU == 4 && t.esm.spExchange == 5)
}

@Test func esmMigrationFillsEmptyMyCallSlot() throws {
    // starší soubor bez sekce esm s prázdným ⇧F3 → doplní se výchozí „Moje značka“
    var macros = Array(repeating: #"{"name":"","text":""}"#, count: 16)
    macros[0] = #"{"name":"A","text":"x"}"#
    let old = try decode(#"{"macros":[\#(macros.joined(separator: ","))]}"#)
    #expect(old.macros[14] == AppSettings.defaultMacros[14])
    #expect(old.macros[0].name == "A" && old.macros[15].text.isEmpty)
    // vlastní obsah ⇧F3 se nemění
    macros[14] = #"{"name":"Mine","text":"abc"}"#
    let own = try decode(#"{"macros":[\#(macros.joined(separator: ","))]}"#)
    #expect(own.macros[14].name == "Mine")
    // s uloženou sekcí esm se prázdné makro už nedoplňuje (uživatel ho mohl smazat)
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
