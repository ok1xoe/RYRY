import AppKit
import Testing
import Settings
@testable import AppViews

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
