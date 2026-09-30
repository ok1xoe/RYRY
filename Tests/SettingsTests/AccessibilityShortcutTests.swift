// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
// The keyboard routes added for blind operation: the commands are registered, have unique default shortcuts
// and survive a round trip through the settings file.
import Foundation
import Testing
@testable import Settings

@Test func keyboardRouteCommandsAreRegistered() {
    let ids = ShortcutCommand.allCases.map(\.id)
    #expect(ids.contains("tuneStrongest"))
    #expect(ids.contains("notchStrongest"))
    #expect(ids.contains("insertLastCall"))
    #expect(Set(ids).count == ids.count)                 // no duplicate identifiers
}

@Test func keyboardRouteDefaultShortcuts() {
    let s = AppSettings()
    #expect(s.binding(for: .tuneStrongest) == KeyBinding(key: "s", modifiers: [.option, .command]))
    #expect(s.binding(for: .notchStrongest) == KeyBinding(key: "n", modifiers: [.option, .command]))
    #expect(s.binding(for: .insertLastCall) == KeyBinding(key: "c", modifiers: [.option, .command]))
    #expect(s.binding(for: .tuneStrongest).display == "⌥⌘S")
    // every default is usable as a shortcut (a bare letter would collide with typing)
    for c in ShortcutCommand.allCases { #expect(c.defaultBinding.isValid, "\(c.id)") }
}

@Test func defaultShortcutsDoNotCollide() {
    #expect(AppSettings().conflictingShortcuts().isEmpty)
}

@Test func keyboardRouteShortcutsRoundTrip() throws {
    var s = AppSettings()
    s.shortcuts["tuneStrongest"] = KeyBinding(key: "f13")
    s.shortcuts["insertLastCall"] = KeyBinding(key: "w", modifiers: [.control, .shift])
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(AppSettings.self, from: data)
    #expect(back.binding(for: .tuneStrongest) == KeyBinding(key: "f13"))
    #expect(back.binding(for: .insertLastCall) == KeyBinding(key: "w", modifiers: [.control, .shift]))
    #expect(back.binding(for: .notchStrongest) == ShortcutCommand.notchStrongest.defaultBinding)   // untouched = default
}
