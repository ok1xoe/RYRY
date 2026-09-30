import Foundation

/// Deterministic Gaussian noise (SplitMix64 + Box–Muller).
public struct NoiseGenerator: Sendable {
    private var state: UInt64
    private var spare: Float?

    public init(seed: UInt64) { state = seed }

    private mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    private mutating func uniform() -> Double {
        (Double(next() >> 11) + 0.5) / Double(UInt64(1) << 53)
    }

    public mutating func gaussian() -> Float {
        if let s = spare { spare = nil; return s }
        let u1 = uniform(), u2 = uniform()
        let r = (-2 * log(u1)).squareRoot()
        spare = Float(r * sin(2 * .pi * u2))
        return Float(r * cos(2 * .pi * u2))
    }

    public mutating func addNoise(to samples: inout [Float], rms: Float) {
        for i in samples.indices { samples[i] += rms * gaussian() }
    }
}
