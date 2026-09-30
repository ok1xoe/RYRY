// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
@testable import Settings

@Test func alertSettingsDefaultsAndTolerance() throws {
    let d = AppSettings()
    #expect(d.display.highlightCalls)
    #expect(d.alerts.myCallSound && !d.alerts.myCallNotification)
    #expect(!d.alerts.newCountryBand && !d.alerts.newCountryAny && d.alerts.watchCalls.isEmpty)
    let bad = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"alerts":{"myCallSound":"ano","watchCalls":5},"display":{"highlightCalls":1}}"#.utf8))
    #expect(bad.alerts == AlertSettings())
    #expect(bad.display.highlightCalls)
    var s = AppSettings(); s.alerts.watchCalls = "OK1ABC\nDL1ABC"; s.alerts.newCountryAny = true; s.display.highlightCalls = false
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    #expect(back == s)
}
