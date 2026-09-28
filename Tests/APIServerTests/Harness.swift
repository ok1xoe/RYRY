import Foundation
import AppCore
import AudioIO
import Engine
import Keying
import QSOLog
import RigControl
import RTTYModem
import Settings
import TestSupport

final class APIFakeRig: Rig, @unchecked Sendable {
    var freq = 14_083_000.0
    var name: String { "fake-rig" }
    func connect() async throws {}
    func disconnect() async {}
    func frequency() async throws -> Double { freq }
    func setFrequency(_ hz: Double) async throws { freq = hz }
    func mode() async throws -> String { "USB" }
    func setMode(_ mode: String) async throws {}
    func setPTT(_ on: Bool) async throws {}
}

struct APIHarness {
    let app: AppController
    let engine: Engine
    let audio: FakeAudioBackend
    let clock: ManualClock
    let rig: APIFakeRig

    func run(steps: Int = 2000, until: () async -> Bool) async {
        for _ in 0..<steps {
            if await until() { return }
            clock.advance(ms: 50)
            await engine.pump()
        }
    }
}

func makeAPIHarness(ptt: PTTMethod = .cat, rig: Rig? = nil) async throws -> APIHarness {
    var s = AppSettings()
    s.station.call = "OK1XOE"
    s.ptt.method = ptt
    let audio = FakeAudioBackend(), clock = ManualClock(), fr = APIFakeRig()
    let engine = Engine(modem: try RTTYModem(), rig: rig ?? fr, audio: audio, config: s.engineConfig(),
                        serialFactory: { _ in FakeSerialPort() }, clock: clock, autoRun: false)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("api-\(UUID())")
    let app = AppController(settings: s, engine: engine, log: try QSOLogStore(directory: dir),
                            profiles: ProfileStore(directory: dir))
    try await app.start()
    await engine.pollRig()
    return APIHarness(app: app, engine: engine, audio: audio, clock: clock, rig: fr)
}
