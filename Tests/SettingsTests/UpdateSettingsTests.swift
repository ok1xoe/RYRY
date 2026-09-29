// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
@testable import Settings

@Test func updateSettingsDefaultAndTolerance() throws {
    #expect(AppSettings().updates.autoCheck)
    let bad = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"updates":{"autoCheck":"ano"}}"#.utf8))
    #expect(bad.updates.autoCheck)
    let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"updates":{"autoCheck":false}}"#.utf8))
    #expect(!off.updates.autoCheck)
    #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).updates.autoCheck)
    var s = AppSettings(); s.updates.autoCheck = false
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    #expect(back == s)
}
