import Testing
@testable import RTTYSignalKit

@Test func ita2EncodesLettersAndFigures() {
    // LTRS, C=0x0E, Q=0x17, space=0x04, FIGS, 5=0x10
    #expect(ITA2.encode("CQ 5") == [0x1F, 0x0E, 0x17, 0x04, 0x1B, 0x10])
}

@Test func ita2UppercasesAndSkipsUnknown() {
    #expect(ITA2.encode("aé@b") == [0x1F, 0x03, 0x19])
}

@Test func generatorProducesExpectedLength() {
    let g = RTTYSignalGenerator()
    // 1 character = 1 start + 5 data + 1.5 stop = 7.5 bits
    let samples = g.generate(text: "E", leadIn: 0, tail: 0)   // LTRS + E = 2 characters
    let expected = Int((2 * 7.5 / 45.45 * 11025).rounded())
    #expect(abs(samples.count - expected) <= 2)
}

@Test func generatorToneFrequencyIsMarkWhenIdle() {
    let g = RTTYSignalGenerator()
    let s = g.generate(codes: [], leadIn: 1.0, tail: 0)   // no characters (text: "" would send LTRS)
    // the number of zero crossings per 1 s ≈ 2 × 2125
    var crossings = 0
    for i in 1..<s.count where (s[i - 1] < 0) != (s[i] < 0) { crossings += 1 }
    #expect(abs(crossings - 4250) < 10)
}

@Test func noiseIsDeterministicAndHasRequestedRMS() {
    var a = NoiseGenerator(seed: 42), b = NoiseGenerator(seed: 42)
    var x = [Float](repeating: 0, count: 20000), y = x
    a.addNoise(to: &x, rms: 0.1); b.addNoise(to: &y, rms: 0.1)
    #expect(x == y)
    let rms = (x.map { $0 * $0 }.reduce(0, +) / Float(x.count)).squareRoot()
    #expect(abs(rms - 0.1) < 0.005)
}
