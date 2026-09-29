import Foundation
import Testing
import ModemKit
@testable import AppCore

@Test func notchClickSetsNotchAndBroadcastsParams() async throws {
    let h = try makeApp()
    let events = h.app.events()
    await h.app.notchClick(hz: 1650)
    #expect(await h.app.modemParam("notchFreq") == .int(1650))
    #expect(await h.app.modemParam("lms") == .bool(true))
    for await e in events {
        if case .paramsChanged(let p) = e { #expect(p["notchFreq"] == .int(1650)); break }
    }
}
