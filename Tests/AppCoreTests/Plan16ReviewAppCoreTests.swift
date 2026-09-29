// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
import Settings
@testable import AppCore

// Kontrola plánu 16 (4): opakování makra s nekonečným / obřím intervalem nesmí spadnout (Int(sec * 1000))
@Test func macroRepeatSurvivesInvalidInterval() async throws {
    for bad in [Double.infinity, 1e20, -Double.infinity] {
        let h = try makeApp()
        var macros = AppSettings.defaultMacros
        macros[0] = Macro(name: "CQ", text: "CQ\\")
        macros[0].repeatSeconds = bad                          // obchází validaci initu (pole je var)
        await h.app.setMacros(macros)
        try await h.app.start()
        try await h.app.runMacro(index: 0)
        await run(h) { await h.engine.state == .rx }
        try await Task.sleep(for: .milliseconds(300))          // smyčka opakování by teď počítala interval
        #expect(await h.engine.state == .rx)
        await h.app.stop()
    }
}
