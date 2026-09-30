import Foundation

/// Independent AFSK RTTY generator with continuous phase. Mark = the lower tone (as in MMTTY),
/// space = mark + shift. reverse swaps the tones.
public struct RTTYSignalGenerator: Sendable {
    public var sampleRate: Double, baud: Double, markHz: Double, shiftHz: Double
    public var stopBits: Double, amplitude: Float, reverse: Bool

    public init(sampleRate: Double = 11025, baud: Double = 45.45, markHz: Double = 2125,
                shiftHz: Double = 170, stopBits: Double = 1.5, amplitude: Float = 0.5,
                reverse: Bool = false) {
        self.sampleRate = sampleRate; self.baud = baud; self.markHz = markHz
        self.shiftHz = shiftHz; self.stopBits = stopBits; self.amplitude = amplitude
        self.reverse = reverse
    }

    public func generate(text: String, leadIn: Double = 1.0, tail: Double = 0.5) -> [Float] {
        generate(codes: ITA2.encode(text), leadIn: leadIn, tail: tail)
    }

    public func generate(codes: [UInt8], leadIn: Double = 1.0, tail: Double = 0.5) -> [Float] {
        // List of segments (isMark, length in bits)
        var segs: [(Bool, Double)] = []
        if leadIn > 0 { segs.append((true, leadIn * baud)) }
        for c in codes {
            segs.append((false, 1))                                   // start
            for b in 0..<5 { segs.append(((c >> b) & 1 == 1, 1)) }   // LSB first
            segs.append((true, stopBits))                             // stop
        }
        if tail > 0 { segs.append((true, tail * baud)) }

        var out: [Float] = []
        var phase = 0.0
        var tBits = 0.0          // exact time in bits, without accumulating rounding error
        var n = 0
        let samplesPerBit = sampleRate / baud
        for (isMark, lenBits) in segs {
            tBits += lenBits
            let end = Int((tBits * samplesPerBit).rounded())
            let mark = isMark != reverse
            let f = mark ? markHz : markHz + shiftHz
            let dphi = 2 * Double.pi * f / sampleRate
            while n < end {
                out.append(amplitude * Float(sin(phase)))
                phase += dphi
                if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                n += 1
            }
        }
        return out
    }
}
