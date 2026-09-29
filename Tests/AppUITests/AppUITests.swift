import Foundation
import Testing
import AppCore
import AudioIO
import Engine
import Keying
import ModemKit
import RigControl
import RTTYModem
import RTTYSignalKit
import Settings
import TestSupport
@testable import AppUI

func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("ui-\(UUID())")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@MainActor
final class Fixture {
    let dir = tempDir()
    let audio = FakeAudioBackend()
    let clock = ManualClock()
    var engines: [Engine] = []
    var configure: (inout AppSettings) -> Void = { _ in }
    lazy var model: AppModel = {
        var s = AppSettings()
        s.station.call = "OK1XOE"
        s.log.directory = dir.appendingPathComponent("log").path
        s.api.fldigiPort = 0; s.api.jsonRPCPort = 0
        configure(&s)
        try? SettingsStore(directory: dir).save(s)
        return AppModel(settingsStore: SettingsStore(directory: dir), profileStore: ProfileStore(directory: dir),
                        engineFactory: { [unowned self] settings, _ in
                            let e = Engine(modem: try! RTTYModem(), rig: NoRig(), audio: self.audio,
                                           config: settings.engineConfig(), serialFactory: { _ in FakeSerialPort() },
                                           clock: self.clock, autoRun: false)
                            self.engines.append(e)
                            return e
                        }, spectrumFPS: 0)
    }()
    var engine: Engine { engines.last! }
    func pump(_ n: Int = 1) async { for _ in 0..<n { clock.advance(ms: 50); await engine.pump() } }
    func settle() async { for _ in 0..<5 { await Task.yield(); try? await Task.sleep(for: .milliseconds(10)) } }
}

// Review Focus 1: bez zvuku aplikace běží a hlásí problém
@Test @MainActor func startWithoutAudioShowsMessage() async throws {
    let f = Fixture()
    f.audio.failStart = true
    await f.model.start()
    #expect(f.model.messages.contains { $0.localizedCaseInsensitiveContains("zvuk") })
    #expect(f.model.settings.station.call == "OK1XOE")
    await f.model.stop()
}

@Test @MainActor func receivesTextIntoRuns() async throws {
    let f = Fixture()
    await f.model.start()
    f.audio.feedRx(RTTYSignalGenerator().generate(text: "CQ DE DL1ABC"))
    await f.pump(60)
    await f.settle()
    #expect(f.model.rxPlainText.contains("CQ DE DL1ABC"))
    await f.model.stop()
}

// Review Focus 3
@Test @MainActor func rxTextIsCapped() async throws {
    let f = Fixture()
    for _ in 0..<5000 { f.model.appendRx(String(repeating: "X", count: 50), echo: false) }
    #expect(f.model.rxCharCount <= AppModel.rxLimit)
    f.model.appendRx("END", echo: true)
    #expect(f.model.rxPlainText.hasSuffix("END"))
    #expect(f.model.rxRuns.last?.echo == true)
}

// Review Focus 2: změna nastavení během TX → RX + restart s novou konfigurací
@Test @MainActor func applySettingsDuringTxRestarts() async throws {
    let f = Fixture()
    await f.model.start()
    let first = f.engine
    await f.model.toggleTx()               // PTT .none → TX
    await f.pump(10)
    #expect(await first.state != .rx)
    var s = f.model.settings
    s.station.call = "OK2ABC"
    await f.model.applySettings(s)
    #expect(await first.state == .stopped)
    #expect(f.engines.count == 2)
    #expect(await f.engine.state == .rx)
    #expect(f.model.settings.station.call == "OK2ABC")
    #expect(SettingsStore(directory: f.dir).load().0.station.call == "OK2ABC")
    await f.model.stop()
}

// Review Focus 5
@Test @MainActor func busyAPIPortIsWarning() async throws {
    let f = Fixture()
    let blocker = HTTPBlocker()
    let port = try await blocker.start()
    f.configure = { $0.api.fldigiPort = Int(port) }
    await f.model.start()
    #expect(f.model.messages.contains { $0.contains("XML-RPC") })
    #expect(f.model.apiStatus.contains("JSON-RPC"))
    await f.model.stop()
    blocker.stop()
}

@Test @MainActor func tuneToMarkAndDraftSending() async throws {
    let f = Fixture()
    await f.model.start()
    await f.model.tune(toMarkHz: 1500)
    #expect(await f.engine.modemParam("mark") == .double(1500))
    f.model.txDraft = "CQ CQ DE OK1X"
    await f.model.sendDraft(mode: .word)
    #expect(f.model.txDraft == "OK1X")                 // nedokončené slovo zůstane
    #expect(await f.engine.txPending > 0)
    f.model.txDraft = "LINE ONE\nLINE T"
    await f.model.sendDraft(mode: .line)
    #expect(f.model.txDraft == "LINE T")
    await f.model.stop()
}

@Test @MainActor func insertWordFillsQSO() async throws {
    let f = Fixture()
    await f.model.start()
    await f.model.insertWord("dl1abc/p")
    await f.model.insertWord("579")
    await f.model.insertWord("HANS")
    #expect(f.model.qso.call == "DL1ABC/P")
    #expect(f.model.qso.rstRcvd == "579")
    #expect(f.model.qso.name == "HANS")
    await f.model.stop()
}

// Review Focus 4 / Task 2
@Test func wordClassifier() {
    for c in ["OK1ABC", "DL1ABC/P", "2E0XYZ", "VK2/G4ABC", "W1AW", "OK1XOE/QRP", "9A1A"] { #expect(WordClassifier.classify(c) == .call, "\(c)") }
    for r in ["599", "579", "5NN", "599001", "59912"] { #expect(WordClassifier.classify(r) == .rst, "\(r)") }
    for n in ["HANS", "TOM", "PETR"] { #expect(WordClassifier.classify(n) == .name, "\(n)") }
    for o in ["CQ", "DE", "TU", "PSE", "RST", "UR", "73", "K", "QTH", "NAME", "HW", "", "---"] {
        #expect(WordClassifier.classify(o) == .other, "\(o)")
    }
}

@Test func waterfallRendererPlacesPeak() {
    var w = WaterfallRenderer(width: 100, height: 10)
    var mags = [Float](repeating: 0, count: 600)
    mags[300] = 1000                                   // 300 × 5 Hz = 1500 Hz
    w.push(SpectrumFrame(binHz: 5, magnitudes: mags), fromHz: 0, toHz: 3000)
    let row = w.row(0)
    let peak = row.enumerated().max { $0.element.brightness < $1.element.brightness }!.offset
    #expect(abs(peak - 50) <= 1)
    w.push(SpectrumFrame(binHz: 5, magnitudes: [Float](repeating: 0, count: 600)), fromHz: 0, toHz: 3000)
    #expect(w.row(1)[peak].brightness > w.row(0)[peak].brightness)   // řádek se posunul dolů
    #expect(w.image != nil)
}
