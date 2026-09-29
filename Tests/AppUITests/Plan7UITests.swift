import Foundation
import Testing
import AppCore
import Engine
import ModemKit
import RTTYModem
import Settings
import AudioIO
import WaveFile
import RTTYSignalKit
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

private func frame(peakAt hz: Double, level: Float) -> SpectrumFrame {
    var m = [Float](repeating: 5, count: 743)
    m[Int(hz / 5.3833)] = level
    return SpectrumFrame(binHz: 5.3833, magnitudes: m)
}

@Test func waterfallGainBrightens() {
    var a = WaterfallRenderer(width: 100, height: 2), b = WaterfallRenderer(width: 100, height: 2)
    b.gainDB = 6
    let f = frame(peakAt: 2125, level: 200)
    a.push(f, fromHz: 0, toHz: 3000); b.push(f, fromHz: 0, toHz: 3000)
    let sa = a.row(0).map(\.brightness).reduce(0, +), sb = b.row(0).map(\.brightness).reduce(0, +)
    #expect(sb > sa, "\(sa) → \(sb)")
}

@Test func manualGainShowsWeakSignalDarkerThanAuto() {
    var auto = WaterfallRenderer(width: 100, height: 2), manual = WaterfallRenderer(width: 100, height: 2)
    manual.autoGain = false
    let f = frame(peakAt: 2125, level: 60)                   // slabý signál
    auto.push(f, fromHz: 0, toHz: 3000); manual.push(f, fromHz: 0, toHz: 3000)
    let x = Int(2125.0 / 30)
    #expect(manual.row(0)[x].brightness < auto.row(0)[x].brightness)
    #expect(abs(manual.lastRow[x] - 60 / 256) < 0.01)
}

@Test @MainActor func displayRangeComesFromSettings() async throws {
    let f = Fixture()
    f.configure = { $0.display.fromHz = 1500; $0.display.toHz = 2500; $0.display.gainDB = 3; $0.display.autoGain = false }
    await f.model.start()
    #expect(f.model.waterfallFromHz == 1500 && f.model.waterfallToHz == 2500)
    #expect(f.model.waterfall.gainDB == 3 && !f.model.waterfall.autoGain)
    await f.model.setDisplay { $0.fromHz = 0; $0.toHz = 4000; $0.gainDB = -6 }
    #expect(f.model.waterfallToHz == 4000 && f.model.waterfall.gainDB == -6)
    #expect(SettingsStore(directory: f.dir).load().0.display.toHz == 4000)
    #expect(f.engines.count == 1)                            // bez restartu
    await f.model.stop()
}

@Test @MainActor func timestampsOnTxRxSwitch() async throws {
    let f = Fixture()
    f.configure = { $0.display.timestamps = true }
    await f.model.start()
    await f.model.toggleTx()
    await f.pump(10)
    await f.settle()
    await f.model.rxNow()
    await f.pump(10)
    await f.settle()
    let text = f.model.rxRuns.map(\.text).joined()
    #expect(text.range(of: #"\[\d\d:\d\d:\d\d UTC TX\]"#, options: .regularExpression) != nil, "\(text.debugDescription)")
    #expect(text.range(of: #"\[\d\d:\d\d:\d\d UTC RX\]"#, options: .regularExpression) != nil, "\(text.debugDescription)")
    await f.model.stop()
}

@Test @MainActor func noTimestampsByDefault() async throws {
    let f = Fixture()
    await f.model.start()
    await f.model.toggleTx(); await f.pump(10); await f.settle()
    await f.model.rxNow(); await f.pump(10); await f.settle()
    #expect(!f.model.rxRuns.map(\.text).joined().contains("UTC"))
    await f.model.stop()
}

@Test @MainActor func playWAVDecodesIntoRxWindow() async throws {
    let f = Fixture()
    await f.model.start()
    let text = "CQ CQ DE DL1ABC DL1ABC K"
    let s = RTTYSignalGenerator(sampleRate: 11025).generate(text: text + "\r\n")
    // WAV na 48 kHz – musí se převzorkovat
    let conv = try SampleRateConverter(from: 11025, to: 48000)
    let url = f.dir.appendingPathComponent("rx.wav")
    try WaveFile.write(samples: conv.process(s) + conv.process([Float](repeating: 0, count: 4096)), sampleRate: 48000, to: url)
    try await f.model.playWAV(url, speed: 0)                    // 0 = co nejrychleji
    #expect(f.model.wavPlaying)
    for _ in 0..<100 where !f.model.rxRuns.map(\.text).joined().contains(text) { await f.pump(); await f.settle() }
    #expect(f.model.rxRuns.map(\.text).joined().contains(text))
    for _ in 0..<50 where f.model.wavPlaying { await f.settle(); try? await Task.sleep(for: .milliseconds(20)) }
    #expect(f.model.wavPlaying == false)
    // restart (Použít) přehrávání ukončí
    try await f.model.playWAV(url, speed: 1)
    await f.model.applySettings(f.model.settings)
    #expect(f.model.wavPlaying == false)
    await f.model.stop()
}

// Review I-1: dialog otevřený se starými hodnotami nesmí vrátit pořadové číslo ani změny zobrazení z rychlého menu
@Test @MainActor func staleDraftKeepsSerialAndDisplayChanges() async throws {
    let f = Fixture()
    f.configure = { $0.contest.enabled = true; $0.contest.nextSerial = 5 }
    await f.model.start()
    let baseline = f.model.settings                       // dialog otevřen
    await f.model.clearQSO()
    await f.model.setQSOField("call", "DL1ABC")
    await f.model.logQSO()
    await f.settle()
    #expect(f.model.settings.contest.nextSerial == 6)
    await f.model.setDisplay { $0.toHz = 4000 }           // rychlé menu u spektra
    var draft = baseline
    draft.display.fontSize = 20                            // uživatel v dialogu změnil jen písmo
    await f.model.applySettings(draft, baseline: baseline)
    #expect(f.model.settings.contest.nextSerial == 6)
    #expect(f.model.settings.display.toHz == 4000 && f.model.settings.display.fontSize == 20)
    // explicitní změna čísla v dialogu platí
    var d2 = f.model.settings; let b2 = d2
    d2.contest.nextSerial = 100
    await f.model.applySettings(d2, baseline: b2)
    #expect(f.model.settings.contest.nextSerial == 100)
    await f.model.stop()
}

// Review minor: QSO okno po startu ukazuje odesílané číslo závodu (bez Clear)
@Test @MainActor func contestSerialVisibleAfterStart() async throws {
    let f = Fixture()
    f.configure = { $0.contest.enabled = true; $0.contest.nextSerial = 42 }
    await f.model.start()
    #expect(f.model.qso.serialSent == 42)
    await f.model.stop()
}

// Review minor: uložený zářez mimo okno mark–space přežije start bez ohledu na pořadí parametrů
@Test @MainActor func persistedNotchSurvivesStartupOrder() async throws {
    let f = Fixture()
    f.configure = {
        $0.rtty = ["mark": .double(1275), "shift": .double(170), "lmsType": .string("notch"),
                   "notchFreq": .int(2200), "notch2Freq": .int(1800), "twoNotch": .bool(true), "lms": .bool(true)]
    }
    await f.model.start()
    #expect(await f.engine.modemParam("notchFreq") == .int(2200))
    #expect(await f.engine.modemParam("notch2Freq") == .int(1800))
    await f.model.stop()
}

@Test func displayRangeCappedAt4000() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("d-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try #"{"display":{"fromHz":0,"toHz":5500}}"#.write(to: dir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
    #expect(SettingsStore(directory: dir).load().0.display.toHz == 3000)
}

// Plán 8 / T3: scope v AppModel (dotazování jen když je zapnutý)
@Test @MainActor func demodScopeInModel() async throws {
    let f = Fixture()
    await f.model.start()
    f.audio.feedRx(RTTYSignalGenerator().generate(text: String(repeating: "RYRYRYRY ", count: 12)))
    await f.pump(30)
    await f.model.pollDemodScope()
    #expect(f.model.demodScope == nil)                   // vypnutý
    await f.model.setDemodScope(true)
    f.audio.feedRx(RTTYSignalGenerator().generate(text: String(repeating: "RYRYRYRY ", count: 12)))
    await f.pump(30)
    await f.model.pollDemodScope()
    let d = try #require(f.model.demodScope)
    #expect(d.bit.count == 8192 && d.marks[0].count == 8192 && d.marks[2].count == 8192)
    // zmrazený záznam se dalšími dávkami nepřepíše (a obsahuje všechny zdroje pro přepínání)
    f.model.scopeFrozen = true
    f.audio.feedRx(RTTYSignalGenerator().generate(text: String(repeating: "RYRYRYRY ", count: 12)))
    await f.pump(30)
    await f.model.pollDemodScope()
    #expect(f.model.demodScope == d)
    await f.model.stop()
}

// Plán 8 / T1: zprávy v modelu – uložení a odeslání
@Test @MainActor func messagesSavedAndSent() async throws {
    let f = Fixture()
    await f.model.start()
    await f.model.saveMessages([Macro(name: "A", text: "TEST %m\\")])
    #expect(f.model.settings.messages.map(\.name) == ["A"])
    #expect(SettingsStore(directory: f.dir).load().0.messages.map(\.name) == ["A"])
    await f.model.runMessage(0)
    await f.pump(20)
    #expect(await f.engine.state == .tx || f.audio.tx.count > 0)
    await f.model.rxNow()
    await f.model.stop()
}

// Plán 8 / T5: klik na slovo v závodních formátech (MMTTY StoreZone/StoreQTH/StoreNR/StoreUTC)
func cu(_ w: String, _ f: ContestFormat, exch: String = "", serialMode: Bool = true) -> [String: String] {
    var q = QSOFields(); q.call = "DL1ABC"; q.exchangeRcvd = exch
    return Dictionary(uniqueKeysWithValues: WordClassifier.contestUpdate(w, format: f, serialMode: serialMode, current: q))
}

@Test func contestUpdateCQRJ() {
    #expect(cu("14", .cqrj) == ["exchangeRcvd": "14"])
    #expect(cu("59914", .cqrj) == ["exchangeRcvd": "14"])
    #expect(cu("OH", .cqrj, exch: "14") == ["exchangeRcvd": "14 OH"])
    #expect(cu("15", .cqrj, exch: "14 OH") == ["exchangeRcvd": "15 OH"])
    #expect(cu("NY", .cqrj, exch: "05 OH") == ["exchangeRcvd": "05 NY"])
    #expect(cu("599", .cqrj) == ["rstRcvd": "599"])
    #expect(cu("TU", .cqrj).isEmpty)
}

@Test func contestUpdateBARTG() {
    #expect(cu("015", .bartg) == ["serialRcvd": "15"])
    #expect(cu("599015", .bartg) == ["serialRcvd": "15"])
    #expect(cu("1203", .bartg) == ["exchangeRcvd": "1203"])
    #expect(cu("12:03", .bartg) == ["exchangeRcvd": "1203"])
    #expect(cu("2599", .bartg) == ["serialRcvd": "2599"])          // neplatný čas → číslo (MMTTY StoreUTC → StoreNR)
    #expect(cu("TU", .bartg).isEmpty)
}

@Test @MainActor func pedClickAlwaysSetsCall() async throws {
    let f = Fixture()
    f.configure = { $0.contest.enabled = true; $0.contest.format = .ped }
    await f.model.start()
    await f.model.insertWord("DL1ABC")
    await f.model.insertWord("OK2PBR")                       // i když značka už je vyplněná
    await f.settle()
    #expect(f.model.qso.call == "OK2PBR" && f.model.qso.serialSent == nil)
    await f.model.stop()
}

// Review plán 8 #1: formát závodu z dialogu Nastavení se musí uložit
@Test @MainActor func contestFormatAppliedFromSettingsDialog() async throws {
    let f = Fixture()
    await f.model.start()
    let base = f.model.settings
    var d = base; d.contest.enabled = true; d.contest.format = .bartg
    await f.model.applySettings(d, baseline: base)
    #expect(f.model.settings.contest.format == .bartg)
    #expect(SettingsStore(directory: f.dir).load().0.contest.format == .bartg)
    await f.model.stop()
}

// Review plán 8 #4, #5
@Test func contestUpdateEdgeCases() {
    #expect(cu("OK", .cqrj, exch: "04") == ["exchangeRcvd": "04 OK"])      // Oklahoma
    #expect(cu("AR", .cqrj, exch: "04") == ["exchangeRcvd": "04 AR"])      // Arkansas
    #expect(cu("TU", .cqrj).isEmpty)
    #expect(cu("01203", .bartg) == ["exchangeRcvd": "1203"])               // MMTTY StoreUTC: > 3 číslice = čas, je-li platný
}
