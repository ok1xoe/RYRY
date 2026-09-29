import Foundation
import Testing
import AppCore
import Engine
import QSOLog
import RTTYSignalKit
import Settings
@testable import AppUI

@MainActor func waeFixture() async -> Fixture {
    let f = Fixture()
    f.configure = { $0.contest.enabled = true; $0.contest.format = .wae; $0.station.call = "OK1XOE" }
    await f.model.start()
    return f
}

@Test @MainActor func qtcReceiveFromRxTextAndSave() async throws {
    let f = await waeFixture()
    await f.model.setQSOField("call", "W1AW")
    f.model.startQTCReceive()
    let sent = "QTC 2/2 QTC 2/2\r\n0915 JA1YY 007\r\n0920 UA0AA 012\r\n"
    f.audio.feedRx(RTTYSignalGenerator().generate(text: sent))
    for _ in 0..<600 where f.audio.rxRemaining > 0 { await f.pump() }
    await f.pump(5)
    await f.settle()
    f.model.qtcFillFromRx()
    let d = try #require(f.model.qtcReceive)
    #expect(d.number == 2 && d.count == 2)
    #expect(d.lines.compactMap { $0 } == [QTCLine(time: "0915", call: "JA1YY", serial: 7), QTCLine(time: "0920", call: "UA0AA", serial: 12)])
    await f.model.qtcSaveReceived()
    #expect(f.model.qtcReceive == nil)
    await f.model.refreshQTC()
    #expect(f.model.qtcStatus?.exchanged == 2)
    await f.model.stop()
}

@Test @MainActor func qtcReceiveByClickingWords() async throws {
    let f = await waeFixture()
    await f.model.setQSOField("call", "W1AW")
    f.model.startQTCReceive()
    for w in ["QTC", "3/2", "1307", "DA1AA", "431", "1310", "OK2PBR", "015"] { await f.model.insertWord(w) }
    let d = try #require(f.model.qtcReceive)
    #expect(d.number == 3 && d.count == 2)
    #expect(d.lines.compactMap { $0 } == [QTCLine(time: "1307", call: "DA1AA", serial: 431), QTCLine(time: "1310", call: "OK2PBR", serial: 15)])
    #expect(f.model.qso.call == "W1AW")                         // klik při příjmu QTC nepřepisuje QSO okno
    f.model.cancelQTCReceive()
    await f.model.stop()
}

@Test @MainActor func qtcStatusInModel() async throws {
    let f = await waeFixture()
    await f.model.setQSOField("call", "DL1ABC"); await f.model.setQSOField("serialRcvd", "5"); await f.model.logQSO()
    await f.settle()
    await f.model.setQSOField("call", "W1AW")
    await f.settle()
    await f.model.refreshQTC()
    #expect(f.model.qtcStatus?.available.map(\.call) == ["DL1ABC"])
    await f.model.stop()
}

// Review plán 12: AGN řádek na správné místo, jen k řádků, protistanice ze začátku příjmu, směrování jen ve WAE
@Test @MainActor func qtcFillPlacesAGNLineAndKeepsCounterpart() async throws {
    let f = await waeFixture()
    await f.model.setQSOField("call", "W1AW")
    f.model.startQTCReceive()
    f.model.appendRx("QTC 4/3 QTC 4/3\r\n0915 JA1YY 007\r\n09#5 UA0AA 012\r\n0931 VK2XX 015\r\n", echo: false)
    f.model.qtcFillFromRx()
    #expect(f.model.qtcReceive?.lines[1] == nil && f.model.qtcReceive?.lines[2]?.call == "VK2XX")   // řádky zůstaly zarovnané
    f.model.appendRx("2 0920 UA0AA 012 0920 UA0AA 012\r\n1111 EXTRA1 001\r\n", echo: false)
    f.model.qtcFillFromRx()
    let d = try #require(f.model.qtcReceive)
    #expect(d.lines[1]?.call == "UA0AA")
    await f.model.logQSO()                                                    // závod: okno se vyčistí
    await f.settle()
    await f.model.qtcSaveReceived()
    await f.model.refreshQTC()
    let st = await f.model.app!.qtcStatus(for: "W1AW")
    #expect(st.exchanged == 3)                                                // jen k = 3 řádky, pod W1AW
    await f.model.stop()
}

@Test @MainActor func qtcRoutingOnlyInWAE() async throws {
    let f = await waeFixture()
    await f.model.setQSOField("call", "W1AW")
    f.model.startQTCReceive()
    var s = f.model.settings; let b = s; s.contest.format = .serial
    await f.model.applySettings(s, baseline: b)
    #expect(f.model.qtcReceive == nil)
    await f.model.insertWord("DL1ABC")
    #expect(f.model.qso.call == "DL1ABC")
    await f.model.stop()
}

// Chyba z ukázky: druhé „Načíst z příjmu“ po AGN nedoplnilo řádek 8
@Test @MainActor func agnRepeatAfterEchoFillsRow() async throws {
    let f = await waeFixture()
    await f.model.setQSOField("call", "K3LR")
    f.model.startQTCReceive()
    f.model.appendRx("K3LR QRV QRV BK\r\n", echo: true)
    f.model.appendRx("QTC 12/10 QTC 12/10\r\n0712 JA3YBK 118\r\n0719 UA9CDC 204\r\n0725 VK4KW 067\r\n0734 ZS1ADD 093\r\n0741 PY2ZEA 150\r\n0752 LU1DX 041\r\n0758 VU2PTT 022\r\n083 BY4AOM 176\r\n0811 JE1CKA 233\r\n0820 ZL3IO 087\r\nBKKA", echo: false)
    f.model.qtcFillFromRx()
    #expect(f.model.qtcReceive?.lines[7] == nil && f.model.qtcReceive?.lines[8]?.call == "JE1CKA")
    // jako na pásmu: moje AGN (echo) a opakování protistanice bez úvodního CR/LF → „BKKA8 0803 …“
    f.model.appendRx("\r\nK3LR AGN 8 8 BK\r\n", echo: true)
    f.model.appendRx("8 0803 BY4AOM 176 0803 BY4AOM 176 BKNWU", echo: false)
    f.model.qtcFillFromRx()
    #expect(f.model.qtcReceive?.lines[7] == QTCLine(time: "0803", call: "BY4AOM", serial: 176))
    await f.model.stop()
}

@Test @MainActor func qtcSeriesListAndSummaryInModel() async throws {
    let f = await waeFixture()
    try await f.model.app!.saveReceivedQTC(counterpart: "K3LR", number: 12, declaredCount: nil,
                                           lines: [QTCLine(time: "0712", call: "JA3YBK", serial: 118), QTCLine(time: "0719", call: "UA9CDC", serial: 204)])
    await f.settle()
    await f.model.refreshQTCSeries()
    #expect(f.model.qtcSeries.count == 1)
    #expect(f.model.qtcSummary.received == 2 && f.model.qtcSummary.sent == 0 && f.model.qtcSummary.points == 2)
    var s = f.model.qtcSeries[0]; s.lines.removeLast()
    await f.model.updateQTCSeries(s)
    #expect(f.model.qtcSummary.received == 1)
    await f.model.deleteQTCSeries(s.id)
    #expect(f.model.qtcSeries.isEmpty)
    await f.model.stop()
}

// Série přišla dřív, než operátor otevřel příjem → příjem začne od poslední zmínky protistanice
@Test @MainActor func lateReceiveStartLooksBackToCounterpart() async throws {
    let f = await waeFixture()
    await f.model.setQSOField("call", "K3LR")
    f.model.appendRx("OK1XOE DE DL5XYZ QTC 3/2 QRV?\r\n1111 AA1AA 001\r\n", echo: false)     // starší, jiná stanice
    f.model.appendRx("OK1XOE DE K3LR YES QTC 9/2 QRV? BK", echo: false)
    f.model.appendRx("QRV", echo: true)
    f.model.appendRx("\r\nQTC 9/2 QTC 9/2\r\n0707 BY4AOM 101\r\n0714 A71A 174\r\nBK", echo: false)
    f.model.startQTCReceive()
    f.model.qtcFillFromRx()
    let d = try #require(f.model.qtcReceive)
    #expect(d.number == 9 && d.count == 2)
    #expect(d.lines.compactMap { $0 }.map(\.call) == ["BY4AOM", "A71A"])
    await f.model.stop()
}

@Test @MainActor func qrvStartsReceiveAndTransmits() async throws {
    let f = await waeFixture()
    await f.model.setQSOField("call", "K3LR")
    await f.model.qtcQRVReceive()
    #expect(f.model.qtcReceive?.counterpart == "K3LR")
    await f.pump(5)
    #expect(await f.engine.state != .rx || f.audio.tx.count > 0)
    await f.model.rxNow()
    await f.model.stop()
}
