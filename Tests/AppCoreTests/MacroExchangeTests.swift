import Foundation
import Testing
import Engine
import MacroEngine
import QSOLog
import Settings
@testable import AppCore

// Macro variables for every kind of contest exchange (%N, %S, %X) and the station variables (%a %o %Z).

private func text(_ t: String, _ c: MacroContext) -> String {
    MacroEngine.expand(t, context: c).outputs.compactMap { if case .text(let s) = $0 { return s } else { return nil } }.joined()
}
private func ctx(_ p: ContestPreset, exchange: String = "", station: (inout Station) -> Void = { _ in }) async throws -> MacroContext {
    var s = AppSettings()
    s.station.call = "OK1XOE"; s.station.name = "Tomáš Kaplan"; s.station.locator = "jn89rb"
    station(&s.station)
    s.contest = ContestSettings.preset(p, year: 2026, exchange: exchange); s.contest.nextSerial = 15
    let h = try makeFormatApp(.serial)
    await h.app.updateSettingsForTesting(s)
    await h.app.clearQSO()
    return await h.app.macroContext()
}

@Test func exchangeVariablePerContestFormat() async throws {
    // %N = what the contest sends after the RST: a number, a code, number + text
    #expect(text("%N", try await ctx(.cqwpxRTTY)) == "015")
    #expect(text("%N", try await ctx(.urcDX, exchange: "BHE")) == "BHE")
    #expect(text("%N", try await ctx(.okDXRTTY)) == "15")                      // my CQ zone from DXCC
    #expect(text("%N", try await ctx(.naSprintRTTY, exchange: "TOMAS DX")) == "015 TOMAS DX")
    #expect(text("%N", try await ctx(.naqpRTTY, exchange: "TOMAS")) == "TOMAS")
    #expect(text("%N", try await ctx(.voltaRTTY)) == "015 15")                  // serial + my zone
    let v = try await ctx(.naSprintRTTY, exchange: "TOMAS DX")
    #expect(text("%S|%X", v) == "015|TOMAS DX")
    #expect(text("%a %o %Z", v) == "TOMAS JN89RB 15")
}

@Test func contestMacrosSendTheExchangeOfTheContest() async throws {
    let urc = try await ctx(.urcDX, exchange: "BHE")
    #expect(text(AppSettings.contestMacros(.urcDX)[3].text, urc).contains(" 599 BHE BHE"))
    let sprint = try await ctx(.naSprintRTTY, exchange: "TOMAS DX")
    #expect(text(AppSettings.contestMacros(.naSprintRTTY)[3].text, sprint).contains(" OK1XOE 015 TOMAS DX"))
    let naqp = try await ctx(.naqpRTTY, exchange: "TOMAS")
    #expect(text(AppSettings.contestMacros(.naqpRTTY)[5].text, naqp) == "\r\nTOMAS\r\n")
}
