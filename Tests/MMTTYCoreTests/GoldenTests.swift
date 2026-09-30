import Foundation
import Testing
import MMTTYCore
import RTTYSignalKit
import WaveFile

struct GoldenCase: Sendable, CustomStringConvertible {
    let name: String, baud: Double, shift: Double, markOffset: Double
    let noiseRMS: Float, demod: Int
    var description: String { name }
}

let goldenText = String(repeating: "RYRYRY CQ CQ DE OK1XOE OK1XOE PSE K\r\nUR RST 599 599 NR 012 BK\r\n", count: 2)

let goldenCases: [GoldenCase] = [
    .init(name: "clean-45-iir",     baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0,    demod: 0),
    .init(name: "noise6db-45-iir",  baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0.1,  demod: 0),
    .init(name: "noise0db-45-iir",  baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0.2,  demod: 0),
    .init(name: "noise0db-45-fft",  baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0.2,  demod: 3),
    .init(name: "noise0db-45-pll",  baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0.2,  demod: 2),
    .init(name: "noise3db-75-fir",  baud: 75,    shift: 170, markOffset: 0,   noiseRMS: 0.15, demod: 1),
    .init(name: "offset40-45-afc",  baud: 45.45, shift: 170, markOffset: -40, noiseRMS: 0.1,  demod: 0),
    // Hard cases with errors – sensitive to any change in the DSP (bit-exact output).
    .init(name: "noise-4db-45-iir", baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0.35, demod: 0),
    .init(name: "noise-6db-45-iir", baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0.45, demod: 0),
    .init(name: "noise-6db-45-fir", baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0.45, demod: 1),
    .init(name: "noise-6db-45-pll", baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0.45, demod: 2),
    .init(name: "noise-6db-45-fft", baud: 45.45, shift: 170, markOffset: 0,   noiseRMS: 0.45, demod: 3),
    .init(name: "noise-8db-45-afc", baud: 45.45, shift: 170, markOffset: -40, noiseRMS: 0.55, demod: 0),
]

let fixturesDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/golden")

func goldenDecode(_ c: GoldenCase, samples: [Float]) throws -> String {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_DEMOD_TYPE, Double(c.demod)) == RC_OK)
    #expect(rttycore_set_param(core, RC_BAUD, c.baud) == RC_OK)
    #expect(rttycore_set_param(core, RC_SPACE, 2125 + c.shift) == RC_OK)
    return runWithTicks(core, samples)
}

@Test(arguments: goldenCases)
func golden(_ c: GoldenCase) throws {
    let wav = fixturesDir.appendingPathComponent("\(c.name).wav")
    let expected = fixturesDir.appendingPathComponent("\(c.name).expected.txt")
    if ProcessInfo.processInfo.environment["RECORD_GOLDEN"] == "1" {
        var s = RTTYSignalGenerator(baud: c.baud, markHz: 2125 + c.markOffset,
                                    shiftHz: c.shift, amplitude: 0.3).generate(text: goldenText)
        var noise = NoiseGenerator(seed: 2026)
        if c.noiseRMS > 0 { noise.addNoise(to: &s, rms: c.noiseRMS) }
        try WaveFile.write(samples: s, sampleRate: 11025, to: wav)
        let (readBack, _) = try WaveFile.read(from: wav)          // decode the 16-bit version as well
        try goldenDecode(c, samples: readBack).write(to: expected, atomically: true, encoding: .utf8)
        return
    }
    let (samples, rate) = try WaveFile.read(from: wav)
    #expect(rate == 11025)
    let want = try String(contentsOf: expected, encoding: .utf8)
    #expect(try goldenDecode(c, samples: samples) == want)
}

@Test func cleanGoldenIsPerfect() throws {
    let want = try String(contentsOf: fixturesDir.appendingPathComponent("clean-45-iir.expected.txt"),
                          encoding: .utf8)
    #expect(want == goldenText)
}
