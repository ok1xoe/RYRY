import Foundation
import Testing
import AppCore
import Settings
@testable import AppUI

// Násobiče: přepočet při zalogování, NEW MULT pro zadanou značku podle pásma, mimo závod nic.
@Test @MainActor func newMultBadgeFollowsLogAndBand() async throws {
    let f = Fixture()
    f.configure = { $0.contest = ContestSettings.preset(.cqwwRTTY, year: 2026); $0.contest.start = Date().addingTimeInterval(-3600) }
    await f.model.start()
    #expect(f.model.multiplierRule?.preset == .cqwwRTTY && f.model.multipliers?.total == 0)
    await f.model.setQSOField("freq", "14080")
    await f.model.setQSOField("call", "DL1ABC"); await f.settle()
    #expect(f.model.newMultiplier.band == "20m")
    #expect(f.model.newMultiplier.hits.contains(MultiplierHit(.dxcc, "DL")))
    await f.model.setQSOField("exchangeRcvd", "14")
    await f.model.logQSO(); await f.settle()
    #expect(f.model.multipliers?.total == 2)                           // zóna 14 + DL na 20 m
    await f.model.setQSOField("call", "DL2XYZ"); await f.settle()
    #expect(f.model.newMultiplier.isEmpty)                              // stejná země a zóna na 20 m
    await f.model.setQSOField("freq", "7040"); await f.settle()
    #expect(f.model.newMultiplier.band == "40m" && !f.model.newMultiplier.isEmpty)
    await f.model.stop()
}

@Test @MainActor func noMultipliersOutsideContest() async throws {
    let f = Fixture()
    await f.model.start()
    await f.model.setQSOField("freq", "14080")
    await f.model.setQSOField("call", "DL1ABC"); await f.settle()
    #expect(f.model.multiplierRule == nil && f.model.multipliers == nil && f.model.newMultiplier.isEmpty)
    await f.model.stop()
}
