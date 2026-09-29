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
