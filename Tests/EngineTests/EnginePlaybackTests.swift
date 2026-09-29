import Testing
import RTTYSignalKit
import TestSupport
@testable import Engine

// Review I-2: WAV nahrazuje vstup zvukovky (MMTTY TSound::Execute), tempo dává vstup; při TX pauza.
@Test func playbackReplacesLiveInputInRealTime() async throws {
    let r = try makeEngine(ptt: .none)
    try await r.engine.start()
    let text = "CQ CQ DE DL1ABC DL1ABC K"
    let wav = RTTYSignalGenerator().generate(text: text)
    var noise = [Float](repeating: 0, count: wav.count + 22050)
    var g = NoiseGenerator(seed: 9); g.addNoise(to: &noise, rms: 0.3)    // živý vstup = silný šum
    r.audio.feedRx(noise)
    await r.engine.startPlayback(wav, speed: 1)
    #expect(await r.engine.playbackRemaining == wav.count)
    await pump(r) { await r.engine.playbackRemaining == 0 }
    #expect(r.audio.rxRemaining > 0)                 // tempo podle vstupu: vstup se čte stejně rychle
    await r.engine.stop()
    #expect(await collectText(r.events).contains(text))
}

@Test func playbackPausesDuringTxAndStops() async throws {
    let r = try makeEngine(ptt: .none)
    try await r.engine.start()
    r.audio.feedRx([Float](repeating: 0, count: 200_000))
    await r.engine.startPlayback([Float](repeating: 0.1, count: 50_000), speed: 1)
    try await r.engine.tx()
    for _ in 0..<5 { r.clock.advance(ms: 50); await r.engine.pump() }
    #expect(await r.engine.playbackRemaining == 50_000)
    await r.engine.rxNow()
    await pump(r, steps: 3) { false }
    #expect(await r.engine.playbackRemaining < 50_000)
    await r.engine.stopPlayback()
    #expect(await r.engine.playbackRemaining == 0)
    await r.engine.stop()
}
