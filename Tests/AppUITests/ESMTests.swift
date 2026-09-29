import Foundation
import Testing
import AppCore
import Engine
import Settings
@testable import AppUI

private func contest(_ f: ContestFormat, exchange: String = "") -> ContestSettings {
    var c = ContestSettings(); c.enabled = true; c.format = f; c.exchange = exchange; return c
}

private func qso(call: String = "", serialRcvd: Int? = nil, exchangeRcvd: String = "") -> QSOFields {
    var q = QSOFields(); q.call = call; q.serialRcvd = serialRcvd; q.exchangeRcvd = exchangeRcvd; return q
}

private func progress(_ call: String, exch: Bool = false, myCall: Bool = false) -> ESM.Progress {
    ESM.Progress(call: call, exchangeSent: exch, myCallSent: myCall)
}

// MARK: Čistá logika

@Test func esmReceivedFieldsFollowLayout() {
    #expect(ESM.receivedFields(contest(.serial)) == ["serialRcvd"])
    #expect(ESM.receivedFields(contest(.serial, exchange: "NY")) == ["exchangeRcvd"])
    #expect(ESM.receivedFields(contest(.zone)) == ["exchangeRcvd"])
    #expect(ESM.receivedFields(contest(.cqrj)) == ["exchangeRcvd"])
    #expect(ESM.receivedFields(contest(.wae)) == ["serialRcvd"])
    #expect(ESM.receivedFields(contest(.bartg)) == ["serialRcvd", "exchangeRcvd"])
    #expect(ESM.receivedFields(contest(.ped)).isEmpty)
}

@Test func esmReceivedState() {
    #expect(ESM.received(qso(call: "DL1ABC"), contest(.serial)) == .none)
    #expect(ESM.received(qso(call: "DL1ABC", serialRcvd: 12), contest(.serial)) == .complete)
    #expect(ESM.received(qso(call: "DL1ABC", exchangeRcvd: "14"), contest(.zone)) == .complete)
    #expect(ESM.received(qso(call: "DL1ABC", exchangeRcvd: " "), contest(.cqrj)) == .none)
    #expect(ESM.received(qso(call: "DL1ABC", serialRcvd: 5), contest(.bartg)) == .partial)
    #expect(ESM.received(qso(call: "DL1ABC", serialRcvd: 5, exchangeRcvd: "1234"), contest(.bartg)) == .complete)
    #expect(ESM.received(qso(call: "DL1ABC"), contest(.ped)) == .complete)
}

/// Tabulka přechodů: (režim, formát, QSO, průběh) → krok.
@Test func esmTransitionTable() {
    typealias Row = (ESMMode, ContestFormat, QSOFields, ESM.Progress, ESM.Step)
    let rows: [Row] = [
        // Run
        (.run, .serial, qso(), progress(""), .cq),
        (.run, .serial, qso(call: "DL1ABC"), progress("DL1ABC"), .exchange),
        (.run, .serial, qso(call: "DL1ABC"), progress("DL1ABC", exch: true), .exchange),        // nic nepřišlo → znovu výměna
        (.run, .serial, qso(call: "DL1ABC", serialRcvd: 7), progress("DL1ABC", exch: true), .tu),
        (.run, .serial, qso(call: "DL1ABC", serialRcvd: 7), progress("DL1ABC"), .exchange),     // výměna ještě neodešla
        (.run, .zone, qso(call: "DL1ABC", exchangeRcvd: "14"), progress("DL1ABC"), .exchange),  // zóna předvyplněná z DXCC
        (.run, .zone, qso(call: "DL1ABC", exchangeRcvd: "14"), progress("DL1ABC", exch: true), .tu),
        (.run, .cqrj, qso(call: "W1AW"), progress("W1AW", exch: true), .exchange),
        (.run, .cqrj, qso(call: "W1AW", exchangeRcvd: "05 CT"), progress("W1AW", exch: true), .tu),
        (.run, .wae, qso(call: "JA1XYZ", serialRcvd: 101), progress("JA1XYZ", exch: true), .tu),
        (.run, .bartg, qso(call: "G4ABC", serialRcvd: 3), progress("G4ABC", exch: true), .agn),  // jen část výměny
        (.run, .ped, qso(call: "G4ABC"), progress("G4ABC"), .exchange),
        (.run, .ped, qso(call: "G4ABC"), progress("G4ABC", exch: true), .tu),
        // průběh jiné značky neplatí (opravená značka → výměna znovu)
        (.run, .serial, qso(call: "DL1ABD", serialRcvd: 7), progress("DL1ABC", exch: true), .exchange),
        // S&P
        (.sp, .serial, qso(), progress(""), .none),
        (.sp, .serial, qso(call: "DL1ABC"), progress("DL1ABC"), .myCall),
        (.sp, .serial, qso(call: "DL1ABC"), progress("DL1ABC", myCall: true), .myCall),
        (.sp, .serial, qso(call: "DL1ABC", serialRcvd: 44), progress("DL1ABC", myCall: true), .exchangeAndLog),
        (.sp, .zone, qso(call: "DL1ABC", exchangeRcvd: "14"), progress("DL1ABC"), .myCall),
        (.sp, .zone, qso(call: "DL1ABC", exchangeRcvd: "14"), progress("DL1ABC", myCall: true), .exchangeAndLog),
        (.sp, .cqrj, qso(call: "W1AW", exchangeRcvd: "05"), progress("W1AW", myCall: true), .exchangeAndLog),
        (.sp, .wae, qso(call: "JA1XYZ"), progress("JA1XYZ", myCall: true), .myCall),
        (.sp, .wae, qso(call: "JA1XYZ", serialRcvd: 3), progress("JA1XYZ", myCall: true), .exchangeAndLog),
        (.sp, .bartg, qso(call: "G4ABC", exchangeRcvd: "1200"), progress("G4ABC", myCall: true), .agn),
    ]
    for (mode, f, q, p, want) in rows {
        let got = ESM.step(mode: mode, contest: contest(f), qso: q, progress: p, transmitting: false)
        #expect(got == want, "\(mode) \(f) call=\(q.call) → \(got), čekáno \(want)")
    }
}

@Test func esmDoesNothingOutsideContestOrDuringTX() {
    var off = contest(.serial); off.enabled = false
    for mode in ESMMode.allCases {
        #expect(ESM.step(mode: mode, contest: off, qso: qso(), progress: progress(""), transmitting: false) == .none)
        #expect(ESM.step(mode: mode, contest: off, qso: qso(call: "DL1ABC", serialRcvd: 1),
                         progress: progress("DL1ABC", exch: true, myCall: true), transmitting: false) == .none)
        #expect(ESM.step(mode: mode, contest: contest(.serial), qso: qso(call: "DL1ABC"),
                         progress: progress("DL1ABC"), transmitting: true) == .none)
    }
    #expect(ESM.step(mode: .run, contest: contest(.serial), qso: qso(), progress: progress(""), transmitting: true) == .none)
}

@Test func esmMacroSelectionFollowsSettings() {
    var e = ESMSettings()
    #expect(ESM.macro(for: .cq, e) == 0 && ESM.macro(for: .exchange, e) == 3 && ESM.macro(for: .tu, e) == 4)
    #expect(ESM.macro(for: .myCall, e) == 14 && ESM.macro(for: .exchangeAndLog, e) == 3 && ESM.macro(for: .agn, e) == 10)
    #expect(ESM.macro(for: .none, e) == nil)
    e.runCQ = 12; e.runExchange = 13; e.runTU = 5; e.spMyCall = 1; e.spExchange = 2; e.agn = 11
    #expect(ESM.macro(for: .cq, e) == 12 && ESM.macro(for: .exchange, e) == 13 && ESM.macro(for: .tu, e) == 5)
    #expect(ESM.macro(for: .myCall, e) == 1 && ESM.macro(for: .exchangeAndLog, e) == 2 && ESM.macro(for: .agn, e) == 11)
}

@Test func esmMacroLogDetection() {
    #expect(ESM.macroLogs("\r\nTU %c DE %m QRZ?\r\n%l\\"))
    #expect(!ESM.macroLogs("\r\n%c 599 %N %N %c\r\n\\"))
    #expect(!ESM.macroLogs("TU %E %l"))                  // za %E se nic nezpracuje
    #expect(!ESM.macroLogs("100%%l"))                   // %% není %l
    #expect(ESM.needsExplicitLog(.tu, macroText: "TU %c\\") && !ESM.needsExplicitLog(.tu, macroText: "TU %l\\"))
    #expect(ESM.needsExplicitLog(.exchangeAndLog, macroText: "%c 599 %N\\"))
    #expect(!ESM.needsExplicitLog(.exchange, macroText: "%c 599 %N\\"))
}

@Test func esmNextFocus() {
    let c = contest(.serial)
    #expect(ESM.nextFocus(after: .cq, qso: qso(), contest: c) == "call")
    #expect(ESM.nextFocus(after: .exchange, qso: qso(call: "DL1ABC"), contest: c) == "serialRcvd")
    #expect(ESM.nextFocus(after: .myCall, qso: qso(call: "DL1ABC"), contest: contest(.bartg)) == "serialRcvd")
    #expect(ESM.nextFocus(after: .agn, qso: qso(call: "G4ABC", serialRcvd: 3), contest: contest(.bartg)) == "exchangeRcvd")
    #expect(ESM.nextFocus(after: .exchange, qso: qso(call: "DL1ABC", exchangeRcvd: "14"), contest: contest(.zone)) == "exchangeRcvd")
    #expect(ESM.nextFocus(after: .tu, qso: qso(), contest: c) == "call")
    #expect(ESM.nextFocus(after: .none, qso: qso(), contest: c) == "call")
    #expect(ESM.nextFocus(after: .exchange, qso: qso(call: "G4ABC"), contest: contest(.ped)) == "call")
}

// MARK: AppModel (Fixture)

@MainActor private func esmFixture(_ f: ContestFormat = .serial, mode: ESMMode = .run) -> Fixture {
    let fx = Fixture()
    fx.configure = { s in
        s.contest.enabled = true; s.contest.format = f
        s.esm.enabled = true; s.esm.mode = mode
    }
    return fx
}

/// Počká na návrat do RX (makro dovysílá).
@MainActor private func drain(_ f: Fixture) async {
    for _ in 0..<600 { await f.pump(); if await f.engine.state == .rx { break } }
    await f.settle()
}

@Test @MainActor func esmRunSequenceSendsMacrosAndLogs() async throws {
    let f = esmFixture()
    await f.model.start()
    #expect(f.model.esmStep == .cq)
    #expect(await f.model.esmEnter() == "call")
    #expect(f.model.lastESMMacroForTesting == 0)                    // F1 CQ
    #expect(await f.engine.state != .rx)
    await drain(f)
    await f.model.setQSOField("call", "DL1ABC")
    #expect(f.model.esmStep == .exchange)
    #expect(await f.model.esmEnter() == "serialRcvd")
    #expect(f.model.lastESMMacroForTesting == 3)                    // F4 Contest
    await drain(f)
    #expect(f.model.esmStep == .exchange)                           // nic nepřijato → znovu výměna
    await f.model.setQSOField("serialRcvd", "12")
    #expect(f.model.esmStep == .tu)
    #expect(await f.model.esmEnter() == "call")
    #expect(f.model.lastESMMacroForTesting == 4)                    // F5 TU (%l zaloguje)
    await drain(f)
    for _ in 0..<50 where f.model.logRecords.isEmpty { await f.settle() }
    #expect(f.model.logRecords.count == 1)
    #expect(f.model.logRecords.first?.call == "DL1ABC" && f.model.logRecords.first?.serialRcvd == 12)
    #expect(f.model.qso.call.isEmpty)
    #expect(f.model.esmStep == .cq)
    await f.model.stop()
}

@Test @MainActor func esmSearchAndPounceLogsExplicitly() async throws {
    let f = esmFixture(.zone, mode: .sp)
    await f.model.start()
    #expect(await f.model.esmEnter() == "call")                     // prázdná značka → nic, jen fokus
    #expect(f.model.lastESMMacroForTesting == nil)
    #expect(await f.engine.state == .rx)
    await f.model.setQSOField("call", "DL1ABC")
    await f.model.setQSOField("exchangeRcvd", "14")
    #expect(f.model.esmStep == .myCall)
    _ = await f.model.esmEnter()
    #expect(f.model.lastESMMacroForTesting == 14)                   // ⇧F3 Moje značka
    await drain(f)
    #expect(f.model.esmStep == .exchangeAndLog)
    _ = await f.model.esmEnter()
    #expect(f.model.lastESMMacroForTesting == 3)
    // F4 nemá %l → zalogováno explicitně hned
    #expect(f.model.logRecords.count == 1 && f.model.logRecords.first?.exchangeRcvd == "14")
    #expect(f.model.qso.call.isEmpty)
    await drain(f)
    #expect(f.model.logRecords.count == 1)
    await f.model.stop()
}

@Test @MainActor func esmIgnoredDuringTXAndWhenDisabled() async throws {
    let f = esmFixture()
    await f.model.start()
    await f.model.setQSOField("call", "DL1ABC")
    await f.model.toggleTx()
    await f.pump(5)
    #expect(await f.engine.state != .rx)
    #expect(await f.model.esmEnter() == nil)
    #expect(f.model.lastESMMacroForTesting == nil)
    await f.model.rxNow()
    await f.settle()
    // ESM vypnuté → Enter nic nespustí
    var s = f.model.settings; s.esm.enabled = false
    await f.model.applySettings(s)
    #expect(await f.model.esmEnter() == nil)
    #expect(f.model.lastESMMacroForTesting == nil)
    await f.model.stop()
}

@Test @MainActor func esmManualMacroCountsAsSentAndModeToggles() async throws {
    let f = esmFixture()
    await f.model.start()
    await f.model.setQSOField("call", "DL1ABC")
    await f.model.runMacro(3)                                       // výměna ručně přes F4
    await drain(f)
    await f.model.setQSOField("serialRcvd", "5")
    #expect(f.model.esmStep == .tu)
    f.model.toggleESMMode()
    #expect(f.model.settings.esm.mode == .sp)
    #expect(SettingsStore(directory: f.dir).load().0.esm.mode == .sp)
    #expect(f.model.esmStep == .myCall)
    f.model.toggleESMMode()
    #expect(f.model.settings.esm.mode == .run)
    await f.model.stop()
}
