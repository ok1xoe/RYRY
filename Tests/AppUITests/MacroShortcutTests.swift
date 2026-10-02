import AppKit
import Testing
import Settings
@testable import AppViews
import AppUI

// ⇧F1 has to run macro 13 (⇧F1), not macro 1 (F1): SwiftUI hands the shifted function key to the F1 button.

private func fkey(_ n: Int, shift: Bool) -> NSEvent {
    let ch = String(Character(UnicodeScalar(NSF1FunctionKey + n - 1)!))
    return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift, .function] : [.function],
                            timestamp: 0, windowNumber: 0, context: nil, characters: ch, charactersIgnoringModifiers: ch,
                            isARepeat: false, keyCode: 122)!
}

@Test func shiftedFunctionKeyRunsItsOwnMacro() {
    let s = AppSettings()
    #expect(MacroBar.macroIndex(button: 0, settings: s, event: fkey(1, shift: true)) == 12)
    #expect(MacroBar.macroIndex(button: 0, settings: s, event: fkey(1, shift: false)) == 0)
    #expect(MacroBar.macroIndex(button: 12, settings: s, event: fkey(1, shift: true)) == 12)
    #expect(MacroBar.macroIndex(button: 4, settings: s, event: fkey(5, shift: true)) == nil)   // ⇧F5 has no macro
    #expect(MacroBar.macroIndex(button: 3, settings: s, event: nil) == 3)                      // a mouse click
}

// Turning a contest on switches to its macro set, turning it off brings the normal set back; DX has its own set.
@Test @MainActor func contestAndModeSwitchMacroSets() async throws {
    let f = Fixture()
    await f.model.start()
    var m = f.model.settings.macros; m[0].text = "\r\nMY CQ\r\n\\"
    await f.model.saveMacros(m)
    var s = f.model.settings
    s.contest = ContestSettings.preset(.urcDX, year: 2026, exchange: "BHE")
    await f.model.applySettings(s)
    #expect(f.model.settings.macros == AppSettings.contestMacros(.urcDX))
    #expect(f.model.macroSetTitle == "URC DX RTTY")
    s = f.model.settings; s.contest.enabled = false
    await f.model.applySettings(s)
    #expect(f.model.settings.macros[0].text == "\r\nMY CQ\r\n\\")
    f.model.setOperatingMode(.dx)
    #expect(f.model.settings.macros == AppSettings.dxMacros)
    // stored on disk as well
    let saved = SettingsStore(directory: f.dir).load().0
    #expect(saved.operatingMode == .dx && saved.macroSets["normal"]?[0].text == "\r\nMY CQ\r\n\\")
    await f.model.stop()
}
