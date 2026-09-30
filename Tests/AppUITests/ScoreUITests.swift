import Foundation
import Testing
import AppCore
import DXCC
import Settings
@testable import AppUI

// Skóre závodu v AppModel: zalogování přičte (bez úplného přepočtu), výsledek = úplný výpočet; mimo závod nic.
@Test @MainActor func loggedQSOUpdatesScoreIncrementally() async throws {
    let f = Fixture()
    f.configure = { s in
        s.station.call = "OK1XOE"
        s.contest = ContestSettings.preset(.cqwwRTTY, year: 2026)
        s.contest.start = Date().addingTimeInterval(-3600)
    }
    await f.model.start()
    #expect(f.model.score?.score == 0)
    let before = f.model.multiplierFullRecomputes
    for (i, (call, x, khz)) in [("DL1ABC", "14", "14085"), ("W1AW", "5 CT", "14086"), ("DL1ABC", "14", "14087")].enumerated() {
        await f.model.setQSOField("call", call)
        await f.model.setQSOField("freq", khz)
        await f.model.setQSOField("exchangeRcvd", x)
        await f.model.logQSO()
        for _ in 0..<100 where f.model.logRecords.count <= i { await f.settle() }
    }
    #expect(f.model.multiplierFullRecomputes == before)
    let s = try #require(f.model.score)
    #expect(s.qsos == 3 && s.dupes == 1 && s.points == 2 + 3)
    let calc = ScoreCalculator(preset: .cqwwRTTY, ownCall: "OK1XOE", ownLocator: "", countries: CountryDB.shared)
    let full = calc.tally(records: f.model.logRecords, qtc: [], since: f.model.settings.contest.effectiveStart)
    #expect(s == full)
    #expect(s.score == 5 * 5)                                           // zóny 14, 5 + DL, K + CT
    await f.model.stop()
}

@Test @MainActor func noScoreOutsideContest() async throws {
    let f = Fixture()
    await f.model.start()
    #expect(f.model.score == nil)
    await f.model.stop()
}
