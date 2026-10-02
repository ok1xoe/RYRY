// Copyright 2026 OK1XOE (RYRY), LGPL v3
import ModemKit

/// Searching the spectrum for RTTY signals for multi-channel decoding: pairs of peaks a shift apart (± tolerance)
/// above an estimate of the noise floor. The spectrum from the MMTTY core is logarithmic (≈ 3.4 units / dB).
///
/// Individual frames are combined into a "peak hold" with a slow decay – in RTTY mark and space light up alternately,
/// so a single frame usually shows only one tone.
public struct RTTYSignalDetector: Sendable {
    /// Minimum peak height above the noise floor (core spectrum units, ≈ 3.4/dB → default ≈ 7 dB).
    public var threshold: Float = 24
    /// Relative tolerance of the peak spacing from the shift (0.15 = ± 15 %).
    public var tolerance = 0.15
    /// Decay of the held peak per frame (spectrum units).
    public var decay: Float = 3
    /// Max. difference between the mark and space levels (units) – otherwise it is not a tone pair of one signal.
    public var maxImbalance: Float = 60
    public private(set) var held: [Float] = []
    public private(set) var binHz = 0.0

    public init() {}

    public mutating func reset() { held = []; binHz = 0 }

    /// Adds a spectrum frame.
    public mutating func update(_ f: SpectrumFrame) {
        if held.count != f.magnitudes.count || binHz != f.binHz {
            held = f.magnitudes; binHz = f.binHz; return
        }
        for i in held.indices { held[i] = max(f.magnitudes[i], held[i] - decay) }
    }

    /// Mark frequencies (the lower tone) of the signals found, strongest first.
    public func detect(shift: Double, fromHz: Double = 200, toHz: Double = 3000, maxCount: Int = 8) -> [Double] {
        Self.detect(magnitudes: held, binHz: binHz, shift: shift, fromHz: fromHz, toHz: toHz, maxCount: maxCount,
                    threshold: threshold, tolerance: tolerance, maxImbalance: maxImbalance)
    }

    /// Detection from a single (already averaged) spectrum.
    public static func detect(magnitudes m: [Float], binHz: Double, shift: Double, fromHz: Double = 200, toHz: Double = 3000,
                              maxCount: Int = 8, threshold: Float = 24, tolerance: Double = 0.15,
                              maxImbalance: Float = 60) -> [Double] {
        guard binHz > 0, shift > 0, maxCount > 0, m.count > 4 else { return [] }
        let lo = max(1, Int((fromHz / binHz).rounded(.down)))
        let hi = min(m.count - 2, Int((toHz / binHz).rounded(.up)))
        guard hi - lo > 4 else { return [] }
        // noise floor = the median over the range (signals occupy only a small part of the band)
        let sorted = m[lo...hi].sorted()
        let floor = sorted[sorted.count / 2]
        let level = floor + threshold
        // local maxima above the threshold; nearby peaks (< a third of the shift) merged into the stronger one
        var peaks: [(hz: Double, v: Float)] = []
        let merge = shift / 3
        for i in lo...hi where m[i] >= level && m[i] >= m[i - 1] && m[i] > m[i + 1] {
            // parabolic refinement of the peak position
            let a = Double(m[i - 1]), b = Double(m[i]), c = Double(m[i + 1])
            let den = a - 2 * b + c
            let off = den != 0 ? max(-0.5, min(0.5, 0.5 * (a - c) / den)) : 0
            let hz = (Double(i) + off) * binHz
            if let last = peaks.last, hz - last.hz < merge {
                if m[i] > last.v { peaks[peaks.count - 1] = (hz, m[i]) }
            } else {
                peaks.append((hz, m[i]))
            }
        }
        // mark–space pairs: spacing of shift ± tolerance, similar levels; the strongest pair first
        var pairs: [(i: Int, j: Int, score: Float)] = []
        for i in peaks.indices {
            for j in peaks.indices where j > i {
                let d = peaks[j].hz - peaks[i].hz
                guard abs(d - shift) <= shift * tolerance else { continue }
                guard abs(peaks[i].v - peaks[j].v) <= maxImbalance else { continue }
                pairs.append((i, j, min(peaks[i].v, peaks[j].v)))
            }
        }
        pairs.sort { $0.score > $1.score }
        var used = Set<Int>()
        var spans: [ClosedRange<Double>] = []
        var out: [Double] = []
        for p in pairs where !used.contains(p.i) && !used.contains(p.j) {
            // the keying sidebands of a stronger signal must not create another "signal" on top of it
            let span = (peaks[p.i].hz - shift / 2)...(peaks[p.j].hz + shift / 2)
            guard !spans.contains(where: { $0.overlaps(span) }) else { continue }
            spans.append(span)
            used.insert(p.i); used.insert(p.j)
            // mark chosen so that the centre of the pair matches (the peaks tend to be shifted by modulation)
            let center = (peaks[p.i].hz + peaks[p.j].hz) / 2
            out.append(center - shift / 2)
            if out.count >= maxCount { break }
        }
        return out
    }
}
