import Foundation
import Testing
import Engine
import MacroEngine
import QSOLog
import Settings
@testable import AppCore

// Macro variables for every kind of contest exchange (%e, %S, %X, %N) and the station variables (%a %o %Z).

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
    #expect(text("%e", try await ctx(.cqwpxRTTY)) == "599 015")
    #expect(text("%e", try await ctx(.urcDX, exchange: "BHE")) == "599 BHE")
    #expect(text("%e", try await ctx(.okDXRTTY)) == "599 15")                     // my CQ zone from DXCC
    #expect(text("%e", try await ctx(.naSprintRTTY, exchange: "TOMAS DX")) == "015 TOMAS DX")   // no RST
    #expect(text("%e", try await ctx(.naqpRTTY, exchange: "TOMAS")) == "TOMAS")
    #expect(text("%e", try await ctx(.bartgSprint)) == "015")
    #expect(text("%e", try await ctx(.voltaRTTY)) == "599 015 15")                 // serial + my zone
    #expect(text("%e", try await ctx(.sartgNewYear, exchange: "TOMAS")) == "599 015 TOMAS")
    let v = try await ctx(.naSprintRTTY, exchange: "TOMAS DX")
    #expect(text("%S|%X|%N", v) == "015|TOMAS DX|015 TOMAS DX")               // %N without the BARTG "-"
    #expect(text("%a %o %Z", v) == "TOMAS JN89RB 15")
}

@Test func exchangeOutsideContestIsRST() {
    var c = ContestSettings(); c.enabled = false
    #expect(ContestCatalog.sentExchange(c, rst: "579", serial: 3, text: "X") == "579")
    #expect(ContestCatalog.sentExchange(ContestSettings.preset(.wrt, year: 2026), rst: "599", serial: nil, text: "TOMAS OK") == "TOMAS OK")
}
