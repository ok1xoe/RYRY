import Testing
import Settings
import AppCore
@testable import AppUI

// QSO fields, word clicks and ESM for the contests of the catalogue (exchange "text", "serial + text", "serial or code").

private let base: [QSOLayout.Row] = [.single("call", "Call"), .country, .pair("rstSent", "RST s", "rstRcvd", "RST r")]
private let notes = QSOLayout.Row.single("notes", "Notes")
private let serial = QSOLayout.Row.pair("serialSent", "Nr s", "serialRcvd", "Nr r")

@Test func qsoFieldsForCatalogueFormats() {
    let urc = ContestSettings.preset(.urcDX, year: 2026, exchange: "BHE")
    #expect(QSOLayout.rows(for: urc) == base + [.pair("exchangeSent", "Teritorium s", "exchangeRcvd", "Teritorium r"), notes])
    let ny = ContestSettings.preset(.sartgNewYear, year: 2027, exchange: "TOMAS")
    #expect(QSOLayout.rows(for: ny) == base + [serial, .pair("exchangeSent", "Jméno s", "exchangeRcvd", "Jméno r"), notes])
    let ru = ContestSettings.preset(.russianDigi, year: 2026)
    #expect(ru.receivesSerialOrCode && !ru.isRoundupStateExchange)
    #expect(QSOLayout.rows(for: ru) == base + [serial, .single("exchangeRcvd", "Oblast r"), notes])
    // a Russian station sends its oblast instead of the number
    var ruOwn = ru; ruOwn.exchange = "MA"
    #expect(!ruOwn.receivesSerialOrCode)
    #expect(ContestSettings.preset(.arrlRoundup, year: 2027).isRoundupStateExchange)
}

@Test func esmSerialOrCodeAndOptionalMember() {
    let ru = ContestSettings.preset(.russianRTTY, year: 2026)
    #expect(ESM.receivedGroups(ru) == [["serialRcvd", "exchangeRcvd"]])
    var q = QSOFields(); q.call = "UA3ABC"; q.exchangeRcvd = "MA"
    #expect(ESM.received(q, ru) == .complete)
    // TRC: the member mark is optional – the number alone completes the QSO
    let trc = ContestSettings.preset(.trcDigi, year: 2026)
    #expect(ESM.receivedGroups(trc) == [["serialRcvd"]])
    // NA Sprint: the number and the name + QTH are both needed
    let sprint = ContestSettings.preset(.naSprintRTTY, year: 2026, exchange: "TOMAS DX")
    #expect(ESM.receivedGroups(sprint) == [["serialRcvd"], ["exchangeRcvd"]])
}

private func click(_ w: String, _ c: ContestSettings, serialRcvd: Int? = nil, exch: String = "") -> [String: String] {
    var q = QSOFields(); q.call = "DL1ABC"; q.serialRcvd = serialRcvd; q.exchangeRcvd = exch
    return Dictionary(uniqueKeysWithValues: WordClassifier.contestUpdate(w, format: c.format, serialMode: c.exchange.isEmpty,
                                                                           serialOrCode: c.receivesSerialOrCode, current: q))
}

@Test func wordClicksForCatalogueFormats() {
    let ru = ContestSettings.preset(.russianRTTY, year: 2026)
    #expect(click("599MA", ru) == ["exchangeRcvd": "MA"])
    #expect(click("MA", ru) == ["exchangeRcvd": "MA"])
    #expect(click("015", ru) == ["serialRcvd": "15"])
    let sprint = ContestSettings.preset(.naSprintRTTY, year: 2026, exchange: "TOMAS DX")
    #expect(click("154", sprint) == ["serialRcvd": "154"])
    #expect(click("RICK", sprint, serialRcvd: 154) == ["exchangeRcvd": "RICK"])
    #expect(click("NC", sprint, serialRcvd: 154, exch: "RICK") == ["exchangeRcvd": "RICK NC"])
    #expect(click("RICK", sprint, serialRcvd: 154, exch: "RICK").isEmpty)
    let volta = ContestSettings.preset(.voltaRTTY, year: 2027)
    #expect(click("14", volta, serialRcvd: 117) == ["exchangeRcvd": "14"])
    let urc = ContestSettings.preset(.urcDX, year: 2026, exchange: "BHE")
    #expect(click("SCO", urc) == ["exchangeRcvd": "SCO"])
    #expect(click("599", urc) == ["rstRcvd": "599"])
}
