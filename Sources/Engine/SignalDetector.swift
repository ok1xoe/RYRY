// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import ModemKit

/// Hledání RTTY signálů ve spektru pro vícekanálové dekódování: dvojice vrcholů vzdálených o shift (± tolerance)
/// nad odhadem šumového dna. Spektrum z jádra MMTTY je logaritmické (≈ 3,4 jednotky / dB).
///
/// Jednotlivé snímky se skládají do „držení špiček“ s pomalým poklesem – u RTTY střídavě svítí mark a space,
/// v jediném snímku bývá vidět jen jeden tón.
public struct RTTYSignalDetector: Sendable {
    /// Minimální výška vrcholu nad šumovým dnem (jednotky spektra jádra, ≈ 3,4/dB → výchozí ≈ 7 dB).
    public var threshold: Float = 24
    /// Relativní tolerance vzdálenosti vrcholů od shiftu (0,15 = ± 15 %).
    public var tolerance = 0.15
    /// Pokles držené špičky na snímek (jednotky spektra).
    public var decay: Float = 3
    /// Max. rozdíl úrovní mark a space (jednotky) – jinak nejde o dvojici tónů téhož signálu.
    public var maxImbalance: Float = 60
    public private(set) var held: [Float] = []
    public private(set) var binHz = 0.0

    public init() {}

    public mutating func reset() { held = []; binHz = 0 }

    /// Přidá snímek spektra.
    public mutating func update(_ f: SpectrumFrame) {
        if held.count != f.magnitudes.count || binHz != f.binHz {
            held = f.magnitudes; binHz = f.binHz; return
        }
        for i in held.indices { held[i] = max(f.magnitudes[i], held[i] - decay) }
    }

    /// Kmitočty mark (nižší tón) nalezených signálů, nejsilnější první.
    public func detect(shift: Double, fromHz: Double = 200, toHz: Double = 3000, maxCount: Int = 8) -> [Double] {
        Self.detect(magnitudes: held, binHz: binHz, shift: shift, fromHz: fromHz, toHz: toHz, maxCount: maxCount,
                    threshold: threshold, tolerance: tolerance, maxImbalance: maxImbalance)
    }

    /// Detekce z jednoho (již zprůměrovaného) spektra.
    public static func detect(magnitudes m: [Float], binHz: Double, shift: Double, fromHz: Double = 200, toHz: Double = 3000,
                              maxCount: Int = 8, threshold: Float = 24, tolerance: Double = 0.15,
                              maxImbalance: Float = 60) -> [Double] {
        guard binHz > 0, shift > 0, maxCount > 0, m.count > 4 else { return [] }
        let lo = max(1, Int((fromHz / binHz).rounded(.down)))
        let hi = min(m.count - 2, Int((toHz / binHz).rounded(.up)))
        guard hi - lo > 4 else { return [] }
        // šumové dno = medián v rozsahu (signály zabírají jen malou část pásma)
        let sorted = m[lo...hi].sorted()
        let floor = sorted[sorted.count / 2]
        let level = floor + threshold
        // lokální maxima nad prahem; blízké vrcholy (< třetina shiftu) sloučit na silnější
        var peaks: [(hz: Double, v: Float)] = []
        let merge = shift / 3
        for i in lo...hi where m[i] >= level && m[i] >= m[i - 1] && m[i] > m[i + 1] {
            // parabolické zpřesnění polohy vrcholu
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
        // dvojice mark–space: vzdálenost shift ± tolerance, podobné úrovně; nejsilnější dvojice první
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
            // postranní pásma klíčování silnějšího signálu nesmí vytvořit další „signál“ přes něj
            let span = (peaks[p.i].hz - shift / 2)...(peaks[p.j].hz + shift / 2)
            guard !spans.contains(where: { $0.overlaps(span) }) else { continue }
            spans.append(span)
            used.insert(p.i); used.insert(p.j)
            // mark tak, aby střed dvojice odpovídal (vrcholy bývají posunuté modulací)
            let center = (peaks[p.i].hz + peaks[p.j].hz) / 2
            out.append(center - shift / 2)
            if out.count >= maxCount { break }
        }
        return out
    }
}
