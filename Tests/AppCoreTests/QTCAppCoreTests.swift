import Foundation
import Testing
import DXCC
import Engine
import MacroEngine
import ModemKit
import QSOLog
import RTTYModem
import Settings
import TestSupport
@testable import AppCore

private let cty = """
Fed. Rep. of Germany:     14:  28:  EU:   51.00:   -10.00:    -1.0:  DL:
    DA,DB,DC,DD,DE,DF,DG,DH,DI,DJ,DK,DL,DM,DN,DO,DP,DQ,DR;
Czech Republic:           15:  28:  EU:   50.00:   -16.00:    -1.0:  OK:
    OK,OL;
United States:            05:  08:  NA:   37.53:    91.67:     5.0:  K:
    AA,AB,K,N,W;
"""

func makeWAEApp() throws -> (Harness, QTCStore) {
    var s = AppSettings()
    s.station.call = "OK1XOE"; s.ptt.method = .none
    s.contest.enabled = true; s.contest.format = .wae; s.contest.nextSerial = 1
    let audio = FakeAudioBackend(), clock = ManualClock(), rig = FakeRig2()
    let engine = Engine(modem: try RTTYModem(), rig: rig, audio: audio, config: s.engineConfig(),
                        serialFactory: { _ in FakeSerialPort() }, clock: clock, autoRun: false)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wae-\(UUID())")
    let qtc = try QTCStore(directory: dir)
    let app = AppController(settings: s, engine: engine, log: try QSOLogStore(directory: dir), profiles: nil,
                            countries: try CountryDB(text: cty), qtc: qtc)
    return (Harness(app: app, engine: engine, audio: audio, clock: clock, rig: rig, dir: dir), qtc)
}

private func logQSO(_ h: Harness, _ call: String, rcvd: Int) async throws {
    try await h.app.setQSOField("call", call)
    try await h.app.setQSOField("serialRcvd", String(rcvd))
    _ = try await h.app.logQSO()
}

@Test func waeUsesSerialsAndOffersQTCToOtherContinent() async throws {
    let (h, _) = try makeWAEApp()
    #expect(await h.app.qso.serialSent == 1)                       // WAE = RST + serial number
    try await logQSO(h, "DL1ABC", rcvd: 5)
    try await logQSO(h, "OK2PBR", rcvd: 12)
    let st = await h.app.qtcStatus(for: "W1AW")
    #expect(st.available.map(\.call) == ["DL1ABC", "OK2PBR"] && st.exchanged == 0 && st.nextSeries == 1)
    #expect(st.differentContinent == true)
    let eu = await h.app.qtcStatus(for: "DL9ZZ")
    #expect(eu.differentContinent == false)                         // in RTTY only between continents
}

@Test func sendQTCTransmitsAndSavesAfterConfirm() async throws {
    let (h, store) = try makeWAEApp()
    try await h.app.start()
    try await logQSO(h, "DL1ABC", rcvd: 5)
    try await logQSO(h, "OK2PBR", rcvd: 12)
    try await h.app.setQSOField("call", "W1AW")
    let lines = await h.app.qtcStatus(for: "W1AW").available
    try await h.app.sendQTC(lines)
    await run(h) { await h.engine.state == .rx && h.audio.tx.count > 0 }
    let text = try await decodeTxAudio(h.audio.tx)
    #expect(text.contains("QTC 1/2 QTC 1/2") && text.contains("DL1ABC 005") && text.contains("OK2PBR 012"), "\(text)")
    #expect(await store.series.isEmpty)                            // stored only after confirmation
    try await h.app.confirmSentQTC()
    let s = await store.series
    #expect(s.count == 1 && s[0].direction == .sent && s[0].counterpart == "W1AW" && s[0].count == 2)
    #expect(await h.app.qtcStatus(for: "W1AW").exchanged == 2)
    #expect(await h.app.qtcStatus(for: "K2ZZ").available.isEmpty)   // both QSOs already reported
    #expect(await h.app.qtcStatus(for: "K2ZZ").nextSeries == 2)
    await h.app.stop()
}

@Test func receivedQTCSavedAndInCabrillo() async throws {
    let (h, store) = try makeWAEApp()
    try await h.app.setQSOField("call", "W1AW")
    try await h.app.saveReceivedQTC(counterpart: "W1AW", number: 4, declaredCount: 1, lines: [QTCLine(time: "0915", call: "JA1YY", serial: 7)])
    #expect(await store.series.first?.direction == .received)
    #expect(await h.app.qtcStatus(for: "W1AW").exchanged == 1)
    let cab = await h.app.cabrillo()
    #expect(cab.contains("OK1XOE        4/1   W1AW          0915 JA1YY         007"))
    await #expect(throws: AppError.self) { try await h.app.saveReceivedQTC(counterpart: "W1AW", number: 1, declaredCount: nil, lines: []) }
}

func decodeTxAudio(_ samples: [Float]) async throws -> String {
    let m = try RTTYModem()
    let ev = m.events
    (samples + [Float](repeating: 0, count: 4000)).withUnsafeBufferPointer { m.processRx($0) }
    m.finishEvents()
    var t = ""
    for await e in ev { if case .rxText(let c, false) = e { t.append(c) } }
    return t
}

// Review plan 12: the rules are checked when sending as well, the continent is enforced, the other station is passed explicitly
@Test func sendQTCValidatesLinesAndContinent() async throws {
    let (h, store) = try makeWAEApp()
    try await h.app.start()
    try await logQSO(h, "K2ZZ", rcvd: 5)
    try await logQSO(h, "DL1ABC", rcvd: 6)
    let forW1 = await h.app.qtcStatus(for: "W1AW").available               // contains K2ZZ
    try await h.app.setQSOField("call", "K2ZZ")
    await #expect(throws: AppError.self) { try await h.app.sendQTC(forW1) }  // a QTC about K2ZZ to station K2ZZ
    try await h.app.setQSOField("call", "DL9ZZ")                              // the same continent (EU)
    let forDL = await h.app.qtcStatus(for: "DL9ZZ").available
    await #expect(throws: AppError.self) { try await h.app.sendQTC(forDL) }
    await #expect(throws: AppError.self) { try await h.app.saveReceivedQTC(counterpart: "DL9ZZ", number: 1, declaredCount: 1,
                                                                          lines: [QTCLine(time: "0915", call: "JA1YY", serial: 7)]) }
    #expect(await store.series.isEmpty)
    await h.app.stop()
}

@Test func failedSendLeavesNoPendingSeries() async throws {
    let (h, _) = try makeWAEApp()
    try await logQSO(h, "DL1ABC", rcvd: 5)
    try await h.app.setQSOField("call", "W1AW")
    await h.app.setTxDisabled(true)
    await #expect(throws: (any Error).self) { try await h.app.sendQTC(await h.app.qtcStatus(for: "W1AW").available) }
    #expect(await h.app.pendingQTCSeries == nil)
}

@Test func receivedSeriesUsesExplicitCounterpart() async throws {
    let (h, store) = try makeWAEApp()
    try await h.app.setQSOField("call", "OK2NEXT")                            // the window already holds the next one
    try await h.app.saveReceivedQTC(counterpart: "W1AW", number: 2, declaredCount: 10,
                                    lines: [QTCLine(time: "0915", call: "JA1YY", serial: 7)])
    let s = try #require(await store.series.first)
    #expect(s.counterpart == "W1AW" && s.declaredCount == 10)
}

@Test func updateAndDeleteQTCSeries() async throws {
    let (h, store) = try makeWAEApp()
    try await h.app.saveReceivedQTC(counterpart: "K3LRX", number: 12, declaredCount: 10,
                                    lines: [QTCLine(time: "0712", call: "JA3YBK", serial: 118)])
    var s = try #require(await store.series.first)
    let ev = h.app.events()
    s.counterpart = "K3LR"
    try await h.app.updateQTCSeries(s)
    #expect(await store.series.first?.counterpart == "K3LR")
    let a = await h.app.qtcStatus(for: "K3LR").exchanged, b = await h.app.qtcStatus(for: "K3LRX").exchanged
    #expect(a == 1 && b == 0)
    var saw = false
    for await e in ev { if case .qtcChanged = e { saw = true; break } }
    #expect(saw)
    try await h.app.deleteQTCSeries(s.id)
    #expect(await store.series.isEmpty)
}

// The "RST + CQ zone" format (OK DX RTTY): my zone from DXCC, the other station's zone prefilled from the call
@Test func zoneFormatFillsZones() async throws {
    var s = AppSettings(); s.station.call = "OK1XOE"; s.ptt.method = .none
    s.contest = ContestSettings.preset(.okDXRTTY, year: 2026)
    let audio = FakeAudioBackend(), clock = ManualClock()
    let engine = Engine(modem: try RTTYModem(), rig: FakeRig2(), audio: audio, config: s.engineConfig(),
                        serialFactory: { _ in FakeSerialPort() }, clock: clock, autoRun: false)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("okdx-\(UUID())")
    let app = AppController(settings: s, engine: engine, log: try QSOLogStore(directory: dir), profiles: nil,
                            countries: try CountryDB(text: cty))
    let q0 = await app.qso
    #expect(q0.exchangeSent == "15" && q0.serialSent == nil)
    try await app.setQSOField("call", "W1AW")
    #expect(await app.qso.exchangeRcvd == "5")
    let t = MacroEngine.expand("%N|%M", context: await app.macroContext()).outputs
        .compactMap { if case .text(let x) = $0 { return x } else { return nil } }.joined()
    #expect(t == "15|5")
    try await app.setQSOField("exchangeRcvd", "4")                      // the station sent a different one – the correction wins
    let r = try await app.logQSO()
    #expect(r.exchangeSent == "15" && r.exchangeRcvd == "4")
    let q1 = await app.qso
    #expect(q1.exchangeSent == "15" && q1.call.isEmpty)
}

// CQ WW RTTY (CQ/RJ) with no exchange filled in: my CQ zone from DXCC
@Test func cqwwFillsOwnZone() async throws {
    var s = AppSettings(); s.station.call = "OK1XOE"; s.ptt.method = .none
    s.contest = ContestSettings.preset(.cqwwRTTY, year: 2026)
    let engine = Engine(modem: try RTTYModem(), rig: FakeRig2(), audio: FakeAudioBackend(), config: s.engineConfig(),
                        serialFactory: { _ in FakeSerialPort() }, clock: ManualClock(), autoRun: false)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cqww-\(UUID())")
    let app = AppController(settings: s, engine: engine, log: try QSOLogStore(directory: dir), profiles: nil,
                            countries: try CountryDB(text: cty))
    #expect(await app.qso.exchangeSent == "15")
    try await app.setQSOField("call", "W1AW")
    #expect(await app.qso.exchangeRcvd == "")                       // the received CQ/RJ exchange also carries a state – do not prefill
    _ = try await app.logQSO()
    #expect(await app.qso.exchangeSent == "15")
}
