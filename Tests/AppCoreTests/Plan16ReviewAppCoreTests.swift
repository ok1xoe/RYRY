// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Testing
import Settings
@testable import AppCore

// Plan 16 check (4): repeating a macro with an infinite / huge interval must not crash (Int(sec * 1000))
@Test func macroRepeatSurvivesInvalidInterval() async throws {
    for bad in [Double.infinity, 1e20, -Double.infinity] {
        let h = try makeApp()
        var macros = AppSettings.defaultMacros
        macros[0] = Macro(name: "CQ", text: "CQ\\")
        macros[0].repeatSeconds = bad                          // bypasses the init validation (the field is a var)
        await h.app.setMacros(macros)
        try await h.app.start()
        try await h.app.runMacro(index: 0)
        await run(h) { await h.engine.state == .rx }
        try await Task.sleep(for: .milliseconds(300))          // the repeat loop would compute the interval now
        #expect(await h.engine.state == .rx)
        await h.app.stop()
    }
}
