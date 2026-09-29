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
