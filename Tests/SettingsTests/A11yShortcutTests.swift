// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
@testable import Settings

// The reading commands are in the key-binding tab and their default shortcuts clash with nothing.
@Test func readingCommandsHaveDefaultShortcuts() {
    let s = AppSettings()
    #expect(ShortcutCommand.allCases.contains(.readLastLine))
    #expect(ShortcutCommand.allCases.contains(.readPreviousLine))
    #expect(ShortcutCommand.allCases.contains(.speakTuning))
    #expect(s.binding(for: .readLastLine).display == "⌥⌘R")
    #expect(s.binding(for: .readPreviousLine).display == "⌥⇧⌘R")
    #expect(s.binding(for: .speakTuning).display == "⌥⌘T")
    #expect([ShortcutCommand.readLastLine, .readPreviousLine, .speakTuning].allSatisfy { s.binding(for: $0).isValid })
    #expect(s.conflictingShortcuts().isEmpty)
    // a custom shortcut is stored and taken (the same mechanism as the other commands)
    var t = s
    t.shortcuts[ShortcutCommand.readLastLine.id] = KeyBinding(key: "f13")
    #expect(t.binding(for: .readLastLine) == KeyBinding(key: "f13"))
}

// Turning the spoken announcements off survives saving and loading.
@Test func speakAlertsRoundTrips() throws {
    var s = AlertSettings()
    #expect(s.speakAlerts)
    s.speakAlerts = false
    let d = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(AlertSettings.self, from: d).speakAlerts == false)
    // an older settings.json without the key keeps the default
    let old = Data(#"{"myCallSound":true}"#.utf8)
    #expect(try JSONDecoder().decode(AlertSettings.self, from: old).speakAlerts)
}
