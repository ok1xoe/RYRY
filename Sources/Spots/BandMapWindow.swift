// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import QSOLog

/// RTTY část pásma pro okno „Band mapa“ (orientačně, IARU pásmové plány; shodné se `SpotParser.rttySegments`).
public enum RTTYBandPlan {
    public struct Segment: Sendable, Equatable {
        public let band: String
        public let lowKHz: Double
        public let highKHz: Double
    }
    public static let segments: [Segment] = [
        Segment(band: "80m", lowKHz: 3580, highKHz: 3600), Segment(band: "40m", lowKHz: 7030, highKHz: 7060),
        Segment(band: "30m", lowKHz: 10130, highKHz: 10150), Segment(band: "20m", lowKHz: 14070, highKHz: 14100),
        Segment(band: "17m", lowKHz: 18095, highKHz: 18109), Segment(band: "15m", lowKHz: 21070, highKHz: 21100),
        Segment(band: "12m", lowKHz: 24910, highKHz: 24930), Segment(band: "10m", lowKHz: 28070, highKHz: 28120),
    ]
    public static var bands: [String] { segments.map(\.band) }
    public static func segment(for band: String?) -> Segment? { segments.first { $0.band == band } }
    /// Pásmo, když nic jiného pásmo neurčí (bez rigu, bez frekvence v QSO a bez spotů).
    public static let defaultBand = "20m"

    /// Pásmo okna: ruční volba → pásmo z rigu → pásmo z ruční frekvence QSO → pásma se spoty (`spotBands`, nejdřív to
    /// nejzajímavější) → `defaultBand`. Pásmo bez RTTY segmentu se přeskočí. Nikdy nevrací nil, aby mapa nezůstala prázdná.
    public static func selectBand(choice: String?, rigHz: Double?, manualHz: Double?, spotBands: [String]) -> String {
        let candidates = [choice, Bands.band(forHz: rigHz), Bands.band(forHz: manualHz)] + spotBands.map { Optional($0) }
        return candidates.compactMap { $0 }.first { segment(for: $0) != nil } ?? defaultBand
    }

    /// Bez `spotBands`: vrací nil, když pásmo neurčí volba, rig ani ruční frekvence.
    public static func selectBand(choice: String?, rigHz: Double?, manualHz: Double?) -> String? {
        let candidates = [choice, Bands.band(forHz: rigHz), Bands.band(forHz: manualHz)]
        return candidates.compactMap { $0 }.first { segment(for: $0) != nil }
    }
}

/// Svislá frekvenční stupnice (vysoká frekvence nahoře): viditelný rozsah v kHz uvnitř RTTY části pásma.
public struct BandScale: Sendable, Equatable {
    public static let minSpanKHz = 1.0
    public let fullLow: Double, fullHigh: Double
    public private(set) var visibleLow: Double, visibleHigh: Double

    public init(segment: RTTYBandPlan.Segment) {
        fullLow = segment.lowKHz; fullHigh = segment.highKHz
        visibleLow = fullLow; visibleHigh = fullHigh
    }

    public var span: Double { visibleHigh - visibleLow }
    public func contains(kHz: Double) -> Bool { kHz >= visibleLow && kHz <= visibleHigh }

    public func y(forKHz f: Double, height: Double) -> Double { (visibleHigh - f) / span * height }
    public func kHz(forY y: Double, height: Double) -> Double { visibleHigh - y / height * span }

    /// `factor` < 1 přiblíží, > 1 oddálí; bod `around` (kHz) zůstane na stejném relativním místě. Rozsah zůstane v pásmu.
    public mutating func zoom(by factor: Double, around f: Double? = nil) {
        guard factor.isFinite, factor > 0 else { return }
        let newSpan = min(max(span * factor, Self.minSpanKHz), fullHigh - fullLow)
        let anchor = min(max(f ?? (visibleLow + visibleHigh) / 2, visibleLow), visibleHigh)
        let rel = (anchor - visibleLow) / span
        place(low: anchor - rel * newSpan, span: newSpan)
    }

    /// Vystředí rozsah na frekvenci (šířka se nemění, posun se ořízne na pásmo).
    public mutating func center(on f: Double) { place(low: f - span / 2, span: span) }

    /// Zpět na celý RTTY úsek pásma.
    public mutating func reset() { visibleLow = fullLow; visibleHigh = fullHigh }

    /// Posun stupnice o `kHz` (kladné = k vyšším frekvencím); ořízne se na pásmo.
    public mutating func pan(by kHz: Double) {
        guard kHz.isFinite else { return }
        place(low: visibleLow + kHz, span: span)
    }

    private mutating func place(low: Double, span s: Double) {
        let lo = min(max(low, fullLow), fullHigh - s)
        visibleLow = lo; visibleHigh = lo + s
        if abs(visibleHigh - fullHigh) < 1e-9 { visibleHigh = fullHigh }
        if abs(visibleLow - fullLow) < 1e-9 { visibleLow = fullLow }
    }
}

/// Rozmístění štítků na svislé ose s minimální roztečí.
public enum BandMapLayout {
    /// Vrací upravené polohy (ve stejném pořadí jako vstup) v 0…`height`; sousední štítky jsou nejméně `minGap` od sebe
    /// (při nedostatku místa se rozteč zmenší). Pořadí štítků na ose se nemění; skupina se rozjede kolem původní polohy.
    public static func spread(_ ys: [Double], minGap: Double, height: Double) -> [Double] {
        let n = ys.count
        guard n > 0 else { return [] }
        let gap = n > 1 ? min(minGap, max(0, height) / Double(n - 1)) : 0
        let order = ys.indices.sorted { ys[$0] != ys[$1] ? ys[$0] < ys[$1] : $0 < $1 }
        // Shlukování: sousední překrývající se štítky tvoří shluk, jehož střed je průměr původních poloh.
        struct Cluster { var first: Int; var count: Int; var sum: Double; var start = 0.0 }   // sum = Σ (y_j − j·gap)
        var clusters: [Cluster] = []
        func place(_ c: inout Cluster) {
            let ideal = c.sum / Double(c.count) + Double(c.first) * gap
            c.start = min(max(ideal, 0), max(0, height - Double(c.count - 1) * gap))
        }
        for (k, idx) in order.enumerated() {
            var c = Cluster(first: k, count: 1, sum: min(max(ys[idx], 0), height) - Double(k) * gap)
            place(&c)
            while let prev = clusters.last, prev.start + Double(prev.count) * gap > c.start + 1e-9 {
                clusters.removeLast()
                c = Cluster(first: prev.first, count: prev.count + c.count, sum: prev.sum + c.sum)
                place(&c)
            }
            clusters.append(c)
        }
        var pos = [Double](repeating: 0, count: n)
        for c in clusters { for j in 0..<c.count { pos[c.first + j] = c.start + Double(j) * gap } }
        var out = [Double](repeating: 0, count: n)
        for (k, idx) in order.enumerated() { out[idx] = min(max(pos[k], 0), height) }
        return out
    }
}

/// Výběr dat pro okno „Band mapa“.
public enum BandMapFilter {
    /// Spoty pásma `band` mladší než `maxAgeMinutes`; nejnovější první. Z filtru zobrazení se uplatní jen skupiny
    /// módů – pásmo si okno band mapy vybírá samo, zaškrtávátka pásem by mapu zvoleného pásma jen vyprázdnila.
    public static func spots(_ spots: [Spot], band: String, filter: SpotFilter, maxAgeMinutes: Int, now: Date) -> [Spot] {
        let cutoff = now.addingTimeInterval(-Double(maxAgeMinutes) * 60)
        return spots.filter { $0.band == band && filter.matchesMode($0) && $0.time >= cutoff }
            .sorted(by: SpotFilter.newestFirst)
    }

    /// Stáří spotu v celých minutách (nikdy záporné).
    public static func ageMinutes(of s: Spot, now: Date) -> Int { max(0, Int(now.timeIntervalSince(s.time) / 60)) }

    /// Spojení z logu na pásmu `band` z posledních `minutes` minut (má frekvenci); nejnovější první.
    public static func logged(_ records: [QSORecord], band: String, minutes: Int, now: Date) -> [QSORecord] {
        guard minutes > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(minutes) * 60)
        return records.filter { $0.frequency != nil && $0.band == band && $0.timeOn >= cutoff && $0.timeOn <= now.addingTimeInterval(60) }
            .sorted { $0.timeOn > $1.timeOn }
    }
}

/// Zoom stupnice kolečkem myši / trackpadem. Trackpad posílá mnoho malých posunů (a setrvačnost), proto se posuny
/// sčítají a zoomuje se po krocích (1 krok na `pointsPerStep` bodů); setrvačnost se ignoruje. Kolečko = krok na událost.
public struct ScrollZoomAccumulator: Sendable, Equatable {
    public static let pointsPerStep = 20.0
    public private(set) var accumulated = 0.0
    public init() {}

    /// `precise` = trackpad / Magic Mouse (posun v bodech), jinak kolečko (řádky). `momentum` = setrvačnost po gestu.
    /// Vrací počet kroků (kladné = přiblížit, záporné = oddálit, 0 = zatím nic).
    public mutating func feed(deltaY: Double, precise: Bool, momentum: Bool) -> Int {
        guard deltaY.isFinite, !momentum, deltaY != 0 else { return 0 }
        guard precise else { accumulated = 0; return deltaY > 0 ? 1 : -1 }
        if accumulated != 0, (accumulated > 0) != (deltaY > 0) { accumulated = 0 }     // změna směru začíná znovu
        accumulated += deltaY
        let steps = Int((accumulated / Self.pointsPerStep).rounded(.towardZero))
        accumulated -= Double(steps) * Self.pointsPerStep
        return steps
    }

    /// Nové gesto (začátek dotyku) – zbytek z minula se zahodí.
    public mutating func reset() { accumulated = 0 }
}
