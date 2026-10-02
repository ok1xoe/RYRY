import Foundation
import Testing
@testable import Settings

// Macro sets: normal, DX and one per contest; switching stores the active set and loads the other one.

@Test func macroSetKeys() {
    var s = AppSettings()
    #expect(s.activeMacroSetKey == "normal")
    s.operatingMode = .dx
    #expect(s.activeMacroSetKey == "dx")
    s.contest = ContestSettings.preset(.urcDX, year: 2026)
    #expect(s.activeMacroSetKey == "contest.urcDX")
    s.contest.preset = nil
    #expect(s.activeMacroSetKey == "contest.custom")
}

@Test func switchingStoresAndRestoresSets() {
    var s = AppSettings()
    s.macros[0].text = "MY NORMAL CQ"
    let old = s.activeMacroSetKey
    s.contest = ContestSettings.preset(.cqwwRTTY, year: 2026)
    s = s.switchingMacroSet(from: old)
    #expect(s.macroSets["normal"]?[0].text == "MY NORMAL CQ")
    #expect(s.macros == AppSettings.contestMacros(.cqwwRTTY))
    s.macros[3].text = "MY CQWW EXCH"
    s.contest.enabled = false
    s = s.switchingMacroSet(from: "contest.cqwwRTTY")
    #expect(s.macros[0].text == "MY NORMAL CQ")
    s.contest.enabled = true
    s = s.switchingMacroSet(from: "normal")
    #expect(s.macros[3].text == "MY CQWW EXCH")
    // DX has its own defaults
    s.contest.enabled = false; s.operatingMode = .dx
    s = s.switchingMacroSet(from: "contest.cqwwRTTY")
    #expect(s.macros == AppSettings.dxMacros)
}

@Test func contestDefaultsFollowTheExchangeAndESM() {
    let e = ESMSettings()
    for p in ContestPreset.allCases {
        let m = AppSettings.contestMacros(p)
        #expect(m.count == AppSettings.macroCount)
        #expect((m[e.runExchange].text.contains("%N") || m[e.runExchange].text.contains("%x %y")) && m[e.runTU].text.contains("%l"), "\(p)")
        #expect(m[e.spMyCall].text.contains("%m") && m[e.runCQ].text.contains("CQ"), "\(p)")
    }
    #expect(AppSettings.contestMacros(.naSprintRTTY)[3].text == "\r\n%c %m %N\r\n\\")
    #expect(AppSettings.contestMacros(.naSprintRTTY)[2].text == "\r\n%c %N %m\r\n\\")
    #expect(AppSettings.contestMacros(.urcDX)[3].text == "\r\n%c 599 %N %N %c\r\n\\")
    #expect(AppSettings.contestMacros(.urcDX)[2].text == "\r\n%c TU 599 %N %N %m\r\n\\")
    #expect(AppSettings.contestMacros(.urcDX)[4].text == "\r\n%c TU %m TEST\r\n%l\\")
    #expect(AppSettings.contestMacros(.naqpRTTY)[3].text == "\r\n%c %N %N %c\r\n\\")
    #expect(AppSettings.contestMacros(.urcDX)[11].name == "EXCH?")
}

@Test func macroSetsSurviveSaveAndLoad() throws {
    var s = AppSettings()
    s.macroSets["dx"] = AppSettings.dxMacros; s.operatingMode = .dx
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(AppSettings.self, from: data)
    #expect(back.macroSets["dx"] == AppSettings.dxMacros && back.operatingMode == .dx)
}
