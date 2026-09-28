import Testing
import MMTTYCore
import RTTYSignalKit

// Review Focus 5
@Test func squelchSuppressesNoiseOnlyInput() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_SQUELCH, 1) == RC_OK)
    var s = [Float](repeating: 0, count: 11025 * 5)
    var noise = NoiseGenerator(seed: 7)
    noise.addNoise(to: &s, rms: 0.05)
    #expect(runWithTicks(core, s).isEmpty)
    #expect(rttycore_signal(core).squelchOpen == 0)
}

@Test func overdrivenInputIsFlaggedAndStillDecodes() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    let s = RTTYSignalGenerator(amplitude: 3.0).generate(text: sample)   // 3× přes plný rozsah
    let out = runWithTicks(core, s)
    #expect(rttycore_signal(core).overflow == 1)
    #expect(out.contains("CQ CQ DE OK1XOE"))
}

@Test func silenceAndEmptyBuffersAreHarmless() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    rttycore_process_rx(core, nil, 0)
    let zeros = [Float](repeating: 0, count: 11025)
    #expect(runWithTicks(core, zeros).isEmpty)
}

@Test func nanSamplesDoNotPoisonDecoder() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    var s = RTTYSignalGenerator().generate(text: sample)
    s.insert(contentsOf: [Float.nan, .infinity, -.infinity], at: 100)
    #expect(runWithTicks(core, s).contains("CQ CQ DE OK1XOE"))
}
