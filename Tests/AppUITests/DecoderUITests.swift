// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
import Engine
import RTTYSignalKit
import Settings
@testable import AppUI

/// Čeká (s pumpováním), dokud neplatí podmínka.
@MainActor func pumpUntil(_ f: Fixture, max: Int = 400, _ cond: () -> Bool) async {
    for _ in 0..<max {
        if cond() { return }
        await f.pump()
        try? await Task.sleep(for: .milliseconds(2))
    }
    await f.settle()
}

@Test @MainActor func secondDecoderTextGoesToOwnPanel() async throws {
    let f = Fixture()
    await f.model.start()
    await f.model.setSecondDecoder(true)
    #expect(f.model.settings.decoders.secondEnabled)
    #expect(f.model.secondDemodEffective == "fft")                // hlavní IIR → druhý FFT
    #expect(SettingsStore(directory: f.dir).load().0.decoders.secondEnabled)
    let text = "CQ CQ DE DL1ABC DL1ABC K"
    f.audio.feedRx(RTTYSignalGenerator().generate(text: text))
    await pumpUntil(f) { f.model.rx2Text.contains(text) }
    #expect(f.model.rx2Text.contains(text))
    #expect(f.model.rxPlainText.contains(text))
    #expect(f.engines.count == 1)                                  // bez restartu
    f.model.clearRx2()
    #expect(f.model.rx2Text.isEmpty && f.model.rx2TrimmedTotal == f.model.rx2AppendedTotal)
    await f.model.stop()
}

@Test @MainActor func channelsListTextAndTune() async throws {
    let f = Fixture()
    f.configure = { $0.decoders.channelsEnabled = true }
    await f.model.start()
    let t = "CQ TEST DE OK2ABC OK2ABC TEST"
    let sig = RTTYSignalGenerator(markHz: 1400, amplitude: 0.3).generate(text: "RYRYRY " + t + " " + t, leadIn: 2)
    var input = sig; var g = NoiseGenerator(seed: 4); g.addNoise(to: &input, rms: 0.05)
    f.audio.feedRx(input)
    await pumpUntil(f) { f.model.decoderChannels.first?.text.contains("OK2ABC") == true }
    let ch = try #require(f.model.decoderChannels.first)
    #expect(abs(ch.mark - 1400) < 15)
    #expect(ch.text.count <= AppModel.channelTextLimit)
    #expect(ch.text.contains("OK2ABC"))
    await f.model.tuneChannel(ch.id)
    #expect(f.model.param("mark") == .double((ch.mark * 10).rounded() / 10))
    await f.model.insertWord("OK2ABC")                             // klik na slovo v kanálu = jako v hlavním příjmu
    #expect(f.model.qso.call == "OK2ABC")
    await f.model.setChannelDecoding(false)
    #expect(f.model.decoderChannels.isEmpty)
    await f.model.stop()
}

@Test @MainActor func channelEventsForUnknownIdAreIgnoredAndTextCapped() {
    let f = Fixture()
    f.model.handleAux(.channelText(id: 9, "X"))
    #expect(f.model.decoderChannels.isEmpty)
    f.model.handleAux(.channels([DecoderChannelInfo(id: 1, mark: 1000), DecoderChannelInfo(id: 2, mark: 1500)]))
    for _ in 0..<200 { f.model.handleAux(.channelText(id: 2, "A")) }
    f.model.handleAux(.channels([DecoderChannelInfo(id: 2, mark: 1502)]))    // kanál 1 zanikl, text 2 zůstává
    #expect(f.model.decoderChannels.map(\.id) == [2])
    #expect(f.model.decoderChannels[0].text.count == AppModel.channelTextLimit)
    #expect(f.model.decoderChannels[0].mark == 1502)
}

@Test @MainActor func applySettingsTakesDecoderChanges() async throws {
    let f = Fixture()
    await f.model.start()
    let base = f.model.settings
    var s = base
    s.decoders.channelsEnabled = true; s.decoders.maxChannels = 6; s.decoders.secondDemod = "pll"
    await f.model.setSecondDecoder(true)                           // mezitím změněno v horní liště
    await f.model.applySettings(s, baseline: base)
    let d = f.model.settings.decoders
    #expect(d.channelsEnabled && d.maxChannels == 6 && d.secondDemod == "pll")
    #expect(d.secondEnabled)                                       // přepínač z lišty dialog nepřepsal
    #expect(await f.engine.auxDecoders == d.auxConfig())
    await f.model.stop()
}
