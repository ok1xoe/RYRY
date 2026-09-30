// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import QSOLog

/// The RTTY part of a band for the "Band map" window (approximate, IARU band plans; same as `SpotParser.rttySegments`).
public enum RTTYBandPlan {
    /// One band of the map: the whole amateur band, plus the part where RTTY and the other digimodes live.
    /// The scale spans the whole band; it only opens on the digimode part, so the map is useful straight away.
    public struct Segment: Sendable, Equatable {
        public let band: String
        public let lowKHz: Double
        public let highKHz: Double
        public let rttyLowKHz: Double
        public let rttyHighKHz: Double
    }

    /// The usual RTTY/digimode part per band (IARU band plans; 160 m, 60 m and 6 m are the digimode corner,
    /// not an RTTY allocation). A band that is missing here opens on its whole width.
    static let digimodeParts: [String: (Double, Double)] = [
        "160m": (1838, 1843), "80m": (3580, 3600), "40m": (7030, 7060), "30m": (10130, 10150),
        "20m": (14070, 14100), "17m": (18095, 18109), "15m": (21070, 21100), "12m": (24910, 24930),
        "10m": (28070, 28120), "6m": (50300, 50500),
    ]

    /// All HF bands and 6 m, with the edges of the band table (`Bands.table`), in the order of that table.
    public static let segments: [Segment] = Bands.hfAnd6m.compactMap { band in
        guard let e = Bands.table.first(where: { $0.band == band }) else { return nil }
        let low = e.lowMHz * 1000, high = e.highMHz * 1000
        let d = digimodeParts[band] ?? (low, high)
        return Segment(band: band, lowKHz: low, highKHz: high,
                       rttyLowKHz: max(low, d.0), rttyHighKHz: min(high, d.1))
    }
    public static var bands: [String] { segments.map(\.band) }
    public static func segment(for band: String?) -> Segment? { segments.first { $0.band == band } }
    /// The band when nothing else determines it (no rig, no frequency in the QSO and no spots).
    public static let defaultBand = "20m"

    /// Window band: manual choice → band from the rig → band from the manual QSO frequency → bands with spots (`spotBands`,
    /// the most interesting first) → `defaultBand`. A band without an RTTY segment is skipped. Never nil, so the map is never empty.
    public static func selectBand(choice: String?, rigHz: Double?, manualHz: Double?, spotBands: [String]) -> String {
        let candidates = [choice, Bands.band(forHz: rigHz), Bands.band(forHz: manualHz)] + spotBands.map { Optional($0) }
        return candidates.compactMap { $0 }.first { segment(for: $0) != nil } ?? defaultBand
    }

    /// Without `spotBands`: returns nil when neither the choice, the rig nor the manual frequency determines the band.
    public static func selectBand(choice: String?, rigHz: Double?, manualHz: Double?) -> String? {
        let candidates = [choice, Bands.band(forHz: rigHz), Bands.band(forHz: manualHz)]
        return candidates.compactMap { $0 }.first { segment(for: $0) != nil }
    }
}

/// Vertical frequency scale (high frequency at the top): the visible range in kHz inside the band.
/// The whole band is reachable; the scale only opens on the digimode part of it.
public struct BandScale: Sendable, Equatable {
    public static let minSpanKHz = 1.0
    public let fullLow: Double, fullHigh: Double
    public private(set) var visibleLow: Double, visibleHigh: Double

    public init(segment: RTTYBandPlan.Segment) {
        fullLow = segment.lowKHz; fullHigh = segment.highKHz
        visibleLow = segment.rttyLowKHz; visibleHigh = segment.rttyHighKHz
    }

    public var span: Double { visibleHigh - visibleLow }
    public func contains(kHz: Double) -> Bool { kHz >= visibleLow && kHz <= visibleHigh }

    public func y(forKHz f: Double, height: Double) -> Double { (visibleHigh - f) / span * height }
    public func kHz(forY y: Double, height: Double) -> Double { visibleHigh - y / height * span }

    /// `factor` < 1 zooms in, > 1 zooms out; the point `around` (kHz) keeps its relative place. The range stays in the band.
    public mutating func zoom(by factor: Double, around f: Double? = nil) {
        guard factor.isFinite, factor > 0 else { return }
        let newSpan = min(max(span * factor, Self.minSpanKHz), fullHigh - fullLow)
        let anchor = min(max(f ?? (visibleLow + visibleHigh) / 2, visibleLow), visibleHigh)
        let rel = (anchor - visibleLow) / span
        place(low: anchor - rel * newSpan, span: newSpan)
    }

    /// Centers the range on a frequency (the width does not change, the shift is clamped to the band).
    public mutating func center(on f: Double) { place(low: f - span / 2, span: span) }

    /// Back to the whole RTTY part of the band.
    public mutating func reset() { visibleLow = fullLow; visibleHigh = fullHigh }

    /// Shifts the scale by `kHz` (positive = towards higher frequencies); clamped to the band.
    public mutating func pan(by kHz: Double) {
        guard kHz.isFinite else { return }
        place(low: visibleLow + kHz, span: span)
    }

    /// Sets the lower edge of the range (the width does not change, it is clamped to the band).
    public mutating func moveLow(to low: Double) {
        guard low.isFinite else { return }
        place(low: low, span: span)
    }

    private mutating func place(low: Double, span s: Double) {
        let lo = min(max(low, fullLow), fullHigh - s)
        visibleLow = lo; visibleHigh = lo + s
        if abs(visibleHigh - fullHigh) < 1e-9 { visibleHigh = fullHigh }
        if abs(visibleLow - fullLow) < 1e-9 { visibleLow = fullLow }
    }
}

/// Placement of labels on the vertical axis with a minimum spacing.
public enum BandMapLayout {
    /// Returns adjusted positions (in the input order) within 0…`height`; adjacent labels are at least `minGap` apart
    /// (with too little room the gap shrinks). The order on the axis is kept; a group spreads around its original position.
    public static func spread(_ ys: [Double], minGap: Double, height: Double) -> [Double] {
        let n = ys.count
        guard n > 0 else { return [] }
        let gap = n > 1 ? min(minGap, max(0, height) / Double(n - 1)) : 0
        let order = ys.indices.sorted { ys[$0] != ys[$1] ? ys[$0] < ys[$1] : $0 < $1 }
        // Clustering: adjacent overlapping labels form a cluster whose center is the average of the original positions.
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

/// Data selection for the "Band map" window.
public enum BandMapFilter {
    /// Spots of band `band` younger than `maxAgeMinutes`; newest first. Of the display filter only the mode groups
    /// apply – the band map window picks the band itself, the band checkboxes would only empty the map of the chosen band.
    public static func spots(_ spots: [Spot], band: String, filter: SpotFilter, maxAgeMinutes: Int, now: Date) -> [Spot] {
        let cutoff = now.addingTimeInterval(-Double(maxAgeMinutes) * 60)
        return spots.filter { $0.band == band && filter.matchesMode($0) && $0.time >= cutoff }
            .sorted(by: SpotFilter.newestFirst)
    }

    /// Age of a spot in whole minutes (never negative).
    public static func ageMinutes(of s: Spot, now: Date) -> Int { max(0, Int(now.timeIntervalSince(s.time) / 60)) }

    /// QSOs from the log on band `band` from the last `minutes` minutes (with a frequency); newest first.
    public static func logged(_ records: [QSORecord], band: String, minutes: Int, now: Date) -> [QSORecord] {
        guard minutes > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(minutes) * 60)
        return records.filter { $0.frequency != nil && $0.band == band && $0.timeOn >= cutoff && $0.timeOn <= now.addingTimeInterval(60) }
            .sorted { $0.timeOn > $1.timeOn }
    }
}

/// Scale zoom with the mouse wheel / trackpad. The trackpad sends many small deltas (and momentum), so the deltas are
/// summed up and zooming happens in steps (1 step per `pointsPerStep` points); momentum is ignored. Wheel = one step/event.
/// Used for Shift + wheel; a plain wheel pans the scale instead.
public struct ScrollZoomAccumulator: Sendable, Equatable {
    public static let pointsPerStep = 20.0
    public private(set) var accumulated = 0.0
    public init() {}

    /// `precise` = trackpad / Magic Mouse (delta in points), otherwise the wheel (lines). `momentum` = inertia after the gesture.
    /// Returns the number of steps (positive = zoom in, negative = zoom out, 0 = nothing yet).
    public mutating func feed(deltaY: Double, precise: Bool, momentum: Bool) -> Int {
        guard deltaY.isFinite, !momentum, deltaY != 0 else { return 0 }
        guard precise else { accumulated = 0; return deltaY > 0 ? 1 : -1 }
        if accumulated != 0, (accumulated > 0) != (deltaY > 0) { accumulated = 0 }     // a change of direction starts over
        accumulated += deltaY
        let steps = Int((accumulated / Self.pointsPerStep).rounded(.towardZero))
        accumulated -= Double(steps) * Self.pointsPerStep
        return steps
    }

    /// A new gesture (start of touch) – the remainder from last time is discarded.
    public mutating func reset() { accumulated = 0 }
}
