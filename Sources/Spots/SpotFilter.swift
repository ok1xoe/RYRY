// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import QSOLog

/// Mode group for the spot filter checkboxes (like the filters in the N1MM bandmap). Every mode that `SpotParser`
/// can produce belongs to exactly one group; an unrecognized mode (nil) and modes without their own group go to `.other`.
public enum SpotModeGroup: String, Codable, Sendable, Hashable, CaseIterable {
    case rtty = "RTTY"
    case cw = "CW"
    case psk = "PSK"
    /// WSJT-X and related (FT8, FT4, JT65…).
    case digi = "DIGI"
    /// Single-sideband phone (SSB, USB, LSB).
    case ssb = "SSB"
    /// Others and unknown (FM, AM, SSTV, OLIVIA… and a spot whose mode cannot be told).
    case other = "OTHER"

    /// Modes of the group in upper case, as `SpotParser` returns them; `.other` is not in the table (it takes the rest).
    static let modes: [SpotModeGroup: Set<String>] = [
        .rtty: ["RTTY"],
        .cw: ["CW"],
        .psk: ["PSK", "PSK31", "PSK63", "PSK125"],
        .digi: ["FT8", "FT4", "JT65", "JT9", "MSK144", "Q65", "WSPR", "FSK441"],
        .ssb: ["SSB", "USB", "LSB"],
    ]

    /// Mode group of a spot; nil, empty or unknown mode → `.other`.
    public static func group(for mode: String?) -> SpotModeGroup {
        guard let m = mode?.trimmingCharacters(in: .whitespaces).uppercased(), !m.isEmpty else { return .other }
        return allCases.first { modes[$0]?.contains(m) == true } ?? .other
    }
}

/// Spot display filter: checked bands and mode groups. Applies **only when displaying** (the Spots table,
/// band map, labels in the waterfall) – nothing is discarded on reception and the list holds spots of all bands and modes.
public struct SpotFilter: Sendable, Equatable, Codable {
    /// Checked bands (names from `Bands`, see `allBands`).
    public var bands: Set<String>
    /// Checked mode groups.
    public var modes: Set<SpotModeGroup>
    /// The "other" checkbox for bands: spots outside the fixed list (630 m and below, 4 m and above, unknown band).
    public var otherBands: Bool

    /// Fixed list of bands with checkboxes (independent of what arrived in the spots).
    public static let allBands = Bands.hfAnd6m
    public static let allBandsSet = Set(Bands.hfAnd6m)
    public static let allModes = Set(SpotModeGroup.allCases)
    /// Everything checked (the "All" buttons).
    public static let all = SpotFilter(bands: allBandsSet, modes: allModes, otherBands: true)

    /// Bands split into rows of checkboxes (the "Band filter" window) – always the whole `allBands` list in order.
    public static func bandRows(perRow: Int) -> [[String]] {
        guard perRow > 0 else { return [allBands] }
        return stride(from: 0, to: allBands.count, by: perRow).map { Array(allBands[$0..<min($0 + perRow, allBands.count)]) }
    }

    /// Default state: all bands including "other", RTTY only (the same display as the former "RTTY only").
    public init(bands: Set<String> = SpotFilter.allBandsSet, modes: Set<SpotModeGroup> = [.rtty], otherBands: Bool = true) {
        self.bands = bands; self.modes = modes; self.otherBands = otherBands
    }

    /// A spot's band passes only when it is checked. A spot outside the fixed list (630 m and below, 4 m and above or an
    /// unknown band) falls under the "other" checkbox – so every spot has exactly one checkbox, as with the mode groups.
    public func matchesBand(_ s: Spot) -> Bool {
        guard let b = s.band, Self.allBandsSet.contains(b) else { return otherBands }
        return bands.contains(b)
    }

    public func matchesMode(_ s: Spot) -> Bool { modes.contains(SpotModeGroup.group(for: s.mode)) }

    public func matches(_ s: Spot) -> Bool { matchesBand(s) && matchesMode(s) }

    /// Spots that pass the filter; newest first.
    public func apply(to spots: some Sequence<Spot>) -> [Spot] { spots.filter(matches).sorted(by: Self.newestFirst) }

    /// Mode filter only – for the band map and the waterfall labels, where the band is given by the window or the rig.
    public func applyModes(to spots: some Sequence<Spot>) -> [Spot] { spots.filter(matchesMode).sorted(by: Self.newestFirst) }

    /// Sorting of the spot list: newest first, at equal times the lower frequency first.
    public static func newestFirst(_ a: Spot, _ b: Spot) -> Bool {
        a.time != b.time ? a.time > b.time : a.frequencyKHz < b.frequencyKHz
    }
}
