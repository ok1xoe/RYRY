import Foundation
import Testing
@testable import WaveFile

@Test func roundTripPreservesSamples() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    let input: [Float] = [0, 0.5, -0.5, 1.0, -1.0, 0.25]
    try WaveFile.write(samples: input, sampleRate: 11025, to: url)
    let (out, sr) = try WaveFile.read(from: url)
    #expect(sr == 11025)
    #expect(out.count == input.count)
    for (a, b) in zip(input, out) { #expect(abs(a - b) < 1.0 / 16384) }
}

@Test func clipsOutOfRangeSamples() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    try WaveFile.write(samples: [2.0, -2.0], sampleRate: 8000, to: url)
    let (out, _) = try WaveFile.read(from: url)
    #expect(out[0] > 0.99 && out[1] < -0.99)
}

@Test func rejectsNonWaveData() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("bad-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("hello".utf8).write(to: url)
    #expect(throws: WaveFile.Error.self) { try WaveFile.read(from: url) }
}
