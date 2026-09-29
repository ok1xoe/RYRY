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

// Plán 9: 24/32bit PCM, float32 a WAVE_FORMAT_EXTENSIBLE; srozumitelná chyba
private func wav(format: UInt16, bits: UInt16, channels: UInt16 = 2, extensible: Bool = false, samples: [Double]) -> Data {
    var d = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    let bps = Int(bits / 8), frame = bps * Int(channels)
    let dataBytes = UInt32(samples.count * frame)
    let fmtSize: UInt32 = extensible ? 40 : 16
    d.append(contentsOf: Array("RIFF".utf8)); u32(4 + 8 + fmtSize + 8 + dataBytes); d.append(contentsOf: Array("WAVE".utf8))
    d.append(contentsOf: Array("fmt ".utf8)); u32(fmtSize)
    u16(extensible ? 0xFFFE : format); u16(channels); u32(48000); u32(UInt32(48000 * frame)); u16(UInt16(frame)); u16(bits)
    if extensible {
        u16(22); u16(bits); u32(3)
        u16(format); d.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71])
    }
    d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
    for s in samples {
        for ch in 0..<Int(channels) {
            let v = ch == 0 ? s : -s
            switch (format, bits) {
            case (3, 32): withUnsafeBytes(of: Float(v).bitPattern.littleEndian) { d.append(contentsOf: $0) }
            case (1, 24): let i = Int32((v * 8_388_607).rounded()); d.append(contentsOf: [UInt8(i & 0xFF), UInt8((i >> 8) & 0xFF), UInt8((i >> 16) & 0xFF)])
            case (1, 32): withUnsafeBytes(of: Int32((v * 2_147_483_647).rounded()).littleEndian) { d.append(contentsOf: $0) }
            default: withUnsafeBytes(of: Int16((v * 32767).rounded()).littleEndian) { d.append(contentsOf: $0) }
            }
        }
    }
    return d
}

@Test(arguments: [(UInt16(1), UInt16(24), false), (1, 32, false), (3, 32, false), (1, 16, true), (3, 32, true), (1, 24, true)])
func readsMoreWaveFormats(format: UInt16, bits: UInt16, ext: Bool) throws {
    let src: [Double] = [0, 0.5, -0.25, 0.999, -1]
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("w-\(UUID()).wav")
    try wav(format: format, bits: bits, extensible: ext, samples: src).write(to: url)
    let (s, rate) = try WaveFile.read(from: url)
    #expect(rate == 48000 && s.count == src.count)
    for (a, b) in zip(s, src) { #expect(abs(Double(a) - b) < 0.001, "\(format)/\(bits)/\(ext)") }
}

@Test func unsupportedWaveFormatMessageIsReadable() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("w-\(UUID()).wav")
    try wav(format: 6, bits: 8, samples: [0, 0.5]).write(to: url)          // A-law
    #expect(throws: WaveFile.Error.self) { _ = try WaveFile.read(from: url) }
    do { _ = try WaveFile.read(from: url) } catch {
        #expect((error as? LocalizedError)?.errorDescription?.contains("PCM 16/24/32 bit nebo float") == true)
    }
}

// Streamovaný zápis (nahrávání příjmu): hlavička se doplní při zavření, čtení vrátí totéž
@Test func streamingWriterRoundTrip() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID()).wav")
    let w = try WaveWriter(url: url, sampleRate: 11025)
    let a: [Float] = [0, 0.5, -0.5, 1], b: [Float] = [0.25, -1]
    try w.append(a); try w.append(b)
    #expect(w.sampleCount == 6)
    try w.close()
    let (s, rate) = try WaveFile.read(from: url)
    #expect(rate == 11025 && s.count == 6)
    for (x, y) in zip(s, a + b) { #expect(abs(x - y) < 0.0001) }
}
