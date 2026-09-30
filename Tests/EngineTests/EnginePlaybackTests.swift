import Testing
import RTTYSignalKit
import TestSupport
@testable import Engine

// Review I-2: a WAV replaces the sound card input (MMTTY TSound::Execute), the input sets the pace; paused during TX.
@Test func playbackReplacesLiveInputInRealTime() async throws {
    let r = try makeEngine(ptt: .none)
    try await r.engine.start()
    let text = "CQ CQ DE DL1ABC DL1ABC K"
    let wav = RTTYSignalGenerator().generate(text: text)
    var noise = [Float](repeating: 0, count: wav.count + 22050)
    var g = NoiseGenerator(seed: 9); g.addNoise(to: &noise, rms: 0.3)    // the live input = strong noise
    r.audio.feedRx(noise)
    await r.engine.startPlayback(wav, speed: 1)
    #expect(await r.engine.playbackRemaining == wav.count)
    await pump(r) { await r.engine.playbackRemaining == 0 }
    #expect(r.audio.rxRemaining > 0)                 // paced by the input: the input is read at the same rate
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

// Recording: the engine collects the live input, the application drains it as it goes (the WAV is written outside the engine)
@Test func recordingCollectsLiveInput() async throws {
    let r = try makeEngine(ptt: .none)
    try await r.engine.start()
    await r.engine.setRecording(true)
    let input = (0..<30_000).map { Float($0 % 100) / 100 }
    r.audio.feedRx(input)
    await pump(r, steps: 60) { r.audio.rxRemaining == 0 }
    var got = await r.engine.drainRecording()
    #expect(got.count == input.count)
    #expect(got.prefix(1000) == input.prefix(1000))
    #expect(await r.engine.drainRecording().isEmpty)          // drained
    await r.engine.setRecording(false)
    r.audio.feedRx([0.5, 0.5])
    await pump(r, steps: 3) { false }
    got = await r.engine.drainRecording()
    #expect(got.isEmpty)
    await r.engine.stop()
}

// Pausing, seeking and rewinding the playback
@Test func playbackPauseSeekRewind() async throws {
    let r = try makeEngine(ptt: .none)
    try await r.engine.start()
    r.audio.feedRx([Float](repeating: 0, count: 400_000))
    await r.engine.startPlayback([Float](repeating: 0.1, count: 100_000), speed: 1)
    await r.engine.setPlaybackPaused(true)
    await pump(r, steps: 5) { false }
    #expect(await r.engine.playbackPosition == 0)             // paused: nothing is played
    await r.engine.seekPlayback(toFraction: 0.5)
    #expect(await r.engine.playbackPosition == 50_000)
    await r.engine.setPlaybackPaused(false)
    await pump(r, steps: 3) { false }
    #expect(await r.engine.playbackPosition > 50_000)
    await r.engine.seekPlayback(toFraction: 0)                // rewind to the start
    #expect(await r.engine.playbackPosition == 0)
    #expect(await r.engine.playbackTotal == 100_000)
    await r.engine.stop()
}
