// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
import Engine
import ModemKit
import Settings
@testable import AppUI

private let ini = #"""
[Define]
BaudRate=5.000000e+01
MarkFreq=2.125000e+03
SpaceFreq=2.295000e+03
DEMTYPE=2
AFC=0
Call=OK9MMT
[Macro]
M1="\r\nCQ DE %m\r\n\\"
[MacroName]
M1=CQ
[MsgName]
M1=FINAL
[MsgList]
M1="73 %c\r\n%l\\"
[MacroKey]
M1=1073
"""#

// Import z MMTTY: náhled ze souboru a uložení přes saveMacros / saveMessages / setParam / applySettings
@Test @MainActor func importFromMMTTYFile() async throws {
    let f = Fixture()
    await f.model.start()
    let url = f.dir.appendingPathComponent("Mmtty.ini")
    try Data(ini.utf8).write(to: url)
    let r = try f.model.previewMMTTYImport(url)
    #expect(r.macros?.first?.name == "CQ" && r.messages?.count == 1 && r.station?.call == "OK9MMT")
    #expect(r.rtty["demodType"] == .string("pll") && r.rtty["shift"] == .double(170))

    await f.model.applyMMTTYImport(r, options: .all)
    let s = f.model.settings
    #expect(s.macros[0].text == "\r\nCQ DE %m\r\n\\" && s.macros.count == 16)
    #expect(s.messages == [Macro(name: "FINAL", text: "73 %c\r\n%l\\")])
    #expect(s.station.call == "OK9MMT")
    #expect(s.rtty["baud"] == .double(50) && s.rtty["afc"] == .bool(false))
    #expect(await f.engine.modemParam("demodType") == .string("pll"))
    #expect(await f.engine.modemParam("shift") == .double(170))
    // uloženo i na disk
    #expect(SettingsStore(directory: f.dir).load().0.messages.first?.name == "FINAL")
    await f.model.stop()
}

// Přepínače: nevybrané části se nepřepíšou
@Test @MainActor func importRespectsOptions() async throws {
    let f = Fixture()
    await f.model.start()
    let r = MMTTYImport.parse(text: ini)
    let before = f.model.settings
    await f.model.applyMMTTYImport(r, options: [.messages])
    #expect(f.model.settings.macros == before.macros)
    #expect(f.model.settings.station.call == "OK1XOE")
    #expect(f.model.settings.rtty["baud"] == nil)
    #expect(f.model.settings.messages.count == 1)
    await f.model.stop()
}

// Poškozený soubor: náhled nespadne, nic k importu
@Test @MainActor func importDamagedFilePreview() throws {
    let f = Fixture()
    let url = f.dir.appendingPathComponent("bad.ini")
    try Data([0x00, 0xFF, 0xFE, 0x80, 0x81]).write(to: url)
    let r = try f.model.previewMMTTYImport(url)
    #expect(r.isEmpty && !r.warnings.isEmpty)
    #expect(throws: (any Error).self) { try f.model.previewMMTTYImport(f.dir.appendingPathComponent("nic.ini")) }
}
