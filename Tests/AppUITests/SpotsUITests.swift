import Foundation
import Testing
import AppCore
import AudioIO
import Engine
import Keying
import ModemKit
import QSOLog
import RigControl
import RTTYModem
import Settings
import Spots
import TestSupport
@testable import AppUI

final class SpotFakeRig: Rig, @unchecked Sendable {
    private let lock = NSLock()
    private var _freqs: [Double] = []
    var freqs: [Double] { lock.withLock { _freqs } }
    var name: String { "fake" }
    func connect() async throws {}
    func disconnect() async {}
    func frequency() async throws -> Double { freqs.last ?? 0 }
    func setFrequency(_ hz: Double) async throws { lock.withLock { _freqs.append(hz) } }
    func mode() async throws -> String { "LSB" }
    func setMode(_ mode: String) async throws {}
    func setPTT(_ on: Bool) async throws {}
}

@MainActor
func spotModel(rig: Rig, configure: (inout AppSettings) -> Void = { _ in }) -> AppModel {
    let dir = tempDir()
    var s = AppSettings()
    s.station.call = "OK1XOE"
    s.log.directory = dir.appendingPathComponent("log").path
    s.api.fldigiPort = 0; s.api.jsonRPCPort = 0
    s.rig.type = .flrig                       // „rig nastaven“; skutečného řídí továrna enginu
    configure(&s)
    try? SettingsStore(directory: dir).save(s)
    let audio = FakeAudioBackend(), clock = ManualClock()
    return AppModel(settingsStore: SettingsStore(directory: dir), profileStore: ProfileStore(directory: dir),
                    engineFactory: { settings, _ in
                        Engine(modem: try! RTTYModem(config: settings.modemConfig()), rig: rig, audio: audio,
                               config: settings.engineConfig(), serialFactory: { _ in FakeSerialPort() }, clock: clock, autoRun: false)
                    }, spectrumFPS: 0)
}

let spot = Spot(frequencyKHz: 14080.0, call: "DL1ABC", spotter: "W3LPL-#", comment: "RTTY 25 dB", time: Date(),
                        mode: "RTTY", snr: 25, source: .rbn)

@Test @MainActor func doubleClickTunesRigWithOffsetAndFillsCall() async throws {
    let rig = SpotFakeRig()
    let m = spotModel(rig: rig) { $0.spots.offsetHz = 2125 }
    await m.start()
    await m.useSpot(spot)
    #expect(rig.freqs == [14_082_125])                       // kHz → Hz + posun
    #expect(m.qso.call == "DL1ABC")
    await m.stop()
}

@Test @MainActor func spotWithoutOffsetUsesExactFrequency() async throws {
    let rig = SpotFakeRig()
    let m = spotModel(rig: rig)
    await m.start()
    await m.useSpot(spot)
    #expect(rig.freqs == [14_080_000])
    await m.stop()
}

@Test @MainActor func spotWithoutRigOnlyFillsCall() async throws {
    let rig = SpotFakeRig()
    let m = spotModel(rig: rig) { $0.rig.type = .none; $0.spots.offsetHz = 2125 }
    await m.start()
    await m.useSpot(spot)
    #expect(rig.freqs.isEmpty)
    #expect(m.qso.call == "DL1ABC")
    #expect(m.messages.isEmpty)                              // bez rigu žádná chyba
    await m.stop()
}

@Test @MainActor func rigFailureStillFillsCall() async throws {
    let m = spotModel(rig: NoRig())                          // rig nastaven, ale odpojen → chyba nastavení
    await m.start()
    await m.useSpot(spot)
    #expect(m.qso.call == "DL1ABC")
    #expect(m.messages.contains { $0.contains("14080.0") })
    await m.stop()
}

@Test @MainActor func spotFeedConfigFollowsSettings() async throws {
    let m = spotModel(rig: NoRig())
    #expect(m.spotFeedConfig() == nil)                       // výchozí: vše vypnuto, žádná síť
    let m2 = spotModel(rig: NoRig()) {
        $0.spots.clusterEnabled = true; $0.spots.clusterHost = "dxfun.com"; $0.spots.clusterPort = 8000
        $0.spots.clusterCommands = ["sh/dx 30"]; $0.spots.rbnEnabled = true; $0.spots.maxAgeMinutes = 45
    }
    let c = try #require(m2.spotFeedConfig())
    #expect(c.call == "OK1XOE" && c.maxAgeMinutes == 45 && c.rttyOnly)
    #expect(c.cluster == SpotEndpoint(host: "dxfun.com", port: 8000, commands: ["sh/dx 30"]))
    #expect(c.rbn == SpotEndpoint(host: "telnet.reversebeacon.net", port: 7000))
}

@Test @MainActor func disabledSpotsDoNotStartNetwork() async throws {
    let m = spotModel(rig: NoRig())
    await m.start()
    #expect(!m.spotFeed.isRunning)
    await m.stop()
}

@Test @MainActor func settingRTTYOnlyPersists() async throws {
    let m = spotModel(rig: NoRig())
    await m.start()
    m.setSpots { $0.rttyOnly = false }
    #expect(!m.settings.spots.rttyOnly)
    m.setSpots { $0.rttyOnly = true }
    #expect(m.settings.spots.rttyOnly)
    await m.stop()
}
