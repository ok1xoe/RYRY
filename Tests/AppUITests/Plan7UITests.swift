import Foundation
import Testing
import AppCore
import Engine
import ModemKit
import RTTYModem
import Settings
@testable import AppUI

@Test func modemConfigFromSettings() {
    var s = AppSettings()
    s.clock.rxPPM = 120; s.clock.txPPM = 99_999
    s.rttyCore.japanese = true; s.rttyCore.doubleShift = true; s.rttyCore.txUOS = false
    let c = s.modemConfig()
    #expect(c.rxClockPPM == 120 && c.txClockPPM == 20_000)
    #expect(c.codeSet == .japanese && c.doubleShift && !c.txUOS)
}

@Test @MainActor func applySettingsStoresPlan7Sections() async throws {
    let f = Fixture()
    await f.model.start()
    var s = f.model.settings
    s.clock.rxPPM = 33; s.rttyCore.doubleShift = true
    s.display.fontSize = 20; s.display.timestamps = true
    s.contest.enabled = true; s.contest.name = "TEST"
    await f.model.applySettings(s)
    #expect(f.model.settings.clock.rxPPM == 33 && f.model.settings.rttyCore.doubleShift)
    #expect(f.model.settings.display.fontSize == 20 && f.model.settings.display.timestamps)
    #expect(f.model.settings.contest.enabled && f.model.settings.contest.name == "TEST")
    #expect(SettingsStore(directory: f.dir).load().0.clock.rxPPM == 33)
    await f.model.stop()
}

@Test @MainActor func measureClockUsesDeviceRates() async throws {
    let f = Fixture()
    await f.model.start()
    f.model.clockRates = { _, input in input ? (48000, 48000 * (1 + 50e-6)) : (44100, 44100 * (1 - 20e-6)) }
    let r = await f.model.measureClock(seconds: 0.2)
    #expect(abs((r.rx ?? 0) - 50) < 0.01 && abs((r.tx ?? 0) + 20) < 0.01)
    f.model.clockRates = { _, _ in (48000, 0) }             // zařízení neběží
    let none = await f.model.measureClock(seconds: 0.1)
    #expect(none.rx == nil && none.tx == nil)
    await f.model.stop()
}

func cf(_ w: String, _ serial: Bool) -> [String]? { WordClassifier.contestField(w, serialMode: serial).map { [$0.0, $0.1] } }

@Test func contestWordClassification() {
    #expect(cf("015", true) == ["serialRcvd", "15"])
    #expect(cf("599015", true) == ["serialRcvd", "15"])
    #expect(cf("5NN", true) == nil)
    #expect(cf("599", true) == ["rstRcvd", "599"])
    #expect(cf("14", false) == ["exchangeRcvd", "14"])
    #expect(cf("59914", false) == ["exchangeRcvd", "14"])
    #expect(cf("DL", false) == ["exchangeRcvd", "DL"])
    #expect(cf("TU", false) == nil)
}

@Test @MainActor func contestInsertWordAndSerialPersisted() async throws {
    let f = Fixture()
    f.configure = { $0.contest.enabled = true; $0.contest.nextSerial = 3 }
    await f.model.start()
    await f.model.clearQSO()
    #expect(f.model.qso.serialSent == 3)
    await f.model.insertWord("DL1ABC")
    await f.model.insertWord("599012")
    await f.settle()
    #expect(f.model.qso.call == "DL1ABC" && f.model.qso.serialRcvd == 12)
    await f.model.logQSO()
    await f.settle()
    #expect(f.model.settings.contest.nextSerial == 4)
    #expect(SettingsStore(directory: f.dir).load().0.contest.nextSerial == 4)
    await f.model.stop()
}

@Test @MainActor func cabrilloTextFromModel() async throws {
    let f = Fixture()
    f.configure = { $0.contest.enabled = true; $0.contest.name = "TEST-RTTY" }
    await f.model.start()
    await f.model.clearQSO()
    await f.model.setQSOField("call", "DL1ABC")
    await f.model.logQSO()
    await f.settle()
    let t = await f.model.cabrilloText()
    #expect(t.contains("CONTEST: TEST-RTTY") && t.contains("CALLSIGN: OK1XOE"))
    #expect(t.contains("DL1ABC        599"))
    await f.model.stop()
}
