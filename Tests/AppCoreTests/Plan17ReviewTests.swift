import Foundation
import Testing
import Engine
import QSOLog
import Settings
import TestSupport
@testable import AppCore

// Kontrola plánu 17

private func contest(_ f: ContestFormat) -> ContestSettings {
    var c = ContestSettings(); c.enabled = true; c.format = f; return c
}
private let roundup = ContestSettings.preset(.arrlRoundup, year: 2027)

// 2: Loc1 jde do lokátoru jen jako platný Maidenhead; jinak je to stát (CQ/RJ, ARRL RU)
@Test func historyLoc1OnlyValidLocatorFillsLocator() {
    let h = CallHistory()
    var off = ContestSettings(); off.enabled = false
    #expect(h.fields(for: CallHistoryEntry(name: "Joe", loc: "CT"), contest: off, isNorthAmerica: true) == ["name": "Joe"])
    #expect(h.fields(for: CallHistoryEntry(loc: "FN31"), contest: off, isNorthAmerica: true) == ["locator": "FN31"])
    #expect(h.fields(for: CallHistoryEntry(loc: "JO70FC"), contest: off, isNorthAmerica: nil) == ["locator": "JO70FC"])
    // CQ/RJ: Loc1 se státem → výměna „zóna stát“, lokátor ne
    #expect(h.fields(for: CallHistoryEntry(loc: "CT", cqZone: 5), contest: contest(.cqrj), isNorthAmerica: true)
        == ["exchangeRcvd": "5 CT"])
    // ARRL RU: Loc1 se státem → přijatá výměna
    #expect(h.fields(for: CallHistoryEntry(loc: "CT"), contest: roundup, isNorthAmerica: true) == ["exchangeRcvd": "CT"])
}

// 11: ARRL RU – stát/provincie z historie do exchangeRcvd (sloupec State, Exch1 i Loc1)
@Test func historyRoundupFillsStateIntoExchange() {
    let h = CallHistory()
    #expect(h.fields(for: CallHistoryEntry(state: "NY"), contest: roundup, isNorthAmerica: true)["exchangeRcvd"] == "NY")
    #expect(h.fields(for: CallHistoryEntry(exch: "ON"), contest: roundup, isNorthAmerica: true)["exchangeRcvd"] == "ON")
    #expect(h.fields(for: CallHistoryEntry(exch: "123"), contest: roundup, isNorthAmerica: true)["exchangeRcvd"] == nil)
    #expect(h.fields(for: CallHistoryEntry(state: "NY"), contest: roundup, isNorthAmerica: false)["exchangeRcvd"] == nil)
}

@Test func historyRoundupFillsStateInApp() async throws {
    let h = try makeFormatApp(.serial)
    var s = await h.app.settings
    s.contest = roundup
    s.callHistory.enabled = true
    await h.app.updateSettingsForTesting(s)
    await h.app.setCallHistory(CallHistory.parse("""
    !!Order!!,Call,Name,Loc1
    W1AW,HIRAM,CT
    """))
    try await h.app.setQSOField("call", "W1AW")
    let q = await h.app.qso
    #expect(q.exchangeRcvd == "CT" && q.locator.isEmpty && q.name == "HIRAM")
}

// 3: přeladění rigu během vysílání odmítne už AppController (stav z enginu)
@Test func setFrequencyRejectedWhileTransmitting() async throws {
    let h = try makeApp(ptt: .none)
    try await h.app.start()
    try await h.app.setFrequency(7_040_000)
    #expect(h.rig.freq == 7_040_000)
    try await h.app.tx()
    await run(h) { await h.engine.state == .tx }
    try #require(await h.engine.state == .tx)
    await #expect(throws: AppError.transmitting) { try await h.app.setFrequency(14_080_000) }
    #expect(h.rig.freq == 7_040_000)
    await h.app.rxNow()
    await run(h) { await h.engine.state == .rx }
    try await h.app.setFrequency(14_080_000)                            // po návratu do RX zase ano
    #expect(h.rig.freq == 14_080_000)
    await h.app.stop()
    await #expect(throws: AppError.engineStopped) { try await h.app.setFrequency(7_040_000) }   // zastavený ≠ vysílání
}

// 9: ruční zadání pole zruší označení „z historie“ i při shodné hodnotě
@Test func historyMarkerClearedByAnyManualSet() async throws {
    let h = try makeFormatApp(.zone)
    var s = await h.app.settings
    s.callHistory.enabled = true
    await h.app.updateSettingsForTesting(s)
    await h.app.setCallHistory(CallHistory.parse("""
    !!Order!!,Call,Name
    DL1ABC,HANS
    """))
    try await h.app.setQSOField("call", "DL1ABC")
    #expect(await h.app.qso.historyFilled["name"] == "HANS")
    try await h.app.setQSOField("name", "HANS")                        // potvrzeno ručně (stejná hodnota)
    #expect(await h.app.qso.historyFilled["name"] == nil)
    try await h.app.setQSOField("call", "OK2AAA")                      // ručně potvrzené jméno zůstane
    #expect(await h.app.qso.name == "HANS")
}
