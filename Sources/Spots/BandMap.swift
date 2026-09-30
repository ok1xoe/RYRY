// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Band map: conversion of a spot's RF frequency to an audio position in the waterfall and the label layout.
public enum BandMap {
    /// Displayable audio frequency (waterfall 0–4000 Hz).
    public static let audioRange = 0.0...4000.0
    /// At most this many labels (the newest spots).
    public static let maxMarkers = 20
    /// At most this many rows of labels above the waterfall; what does not fit is not shown.
    public static let maxRows = 4

    /// How the radio converts RF to audio according to the mode from the rig.
    public enum Sideband: Sendable, Equatable {
        case upper, lower
        /// RTTY/FSK (the rig reports dial ≈ mark): a spot on the dial sounds at the current mark, higher RF = lower tone.
        case rtty
        /// RTTYR / FSK-R: the other way round, higher RF = higher tone.
        case rttyReverse
    }

    /// USB/PKTUSB → upper sideband; LSB/PKTLSB → lower; RTTY/FSK → `rtty`, RTTYR/RTTY-R/FSKR/FSK-R → `rttyReverse`.
    /// Unknown mode (CW, AM…) → nil.
    public static func sideband(mode: String?) -> Sideband? {
        guard let m = mode?.uppercased(), !m.isEmpty else { return nil }
        if m.contains("USB") { return .upper }
        if m.contains("LSB") { return .lower }
        if m.contains("RTTY") || m.contains("FSK") {
            let reversed = m.hasSuffix("R") || m.contains("-R") || m.contains("REV")
            return reversed ? .rttyReverse : .rtty
        }
        return nil
    }

    /// Audio position (Hz) of a spot at rig dial `dialHz` and mode `mode`; nil for an unknown mode or outside 0…4000 Hz.
    ///
    /// USB/LSB: a double click (`useSpot`) sets the rig to `spot + offsetHz` (target `target`). The tone the user has thus
    /// chosen is `offsetHz` in the lower sideband (LSB/AFSK with mark 2125 Hz → +2125) and `−offsetHz` in the upper; from it the
    /// position follows from the dial's distance to the target. The result is physical (USB: spot − dial, LSB: dial − spot):
    /// after a double click the marker sits on the offset's tone exactly, and clicking it (mark = audio position) hits it too.
    ///
    /// RTTY/FSK: the radio reports dial ≈ mark and a station on the dial sounds at the tone the decoder is tuned to –
    /// audio = `markHz` (the current mark) + (dial − spot), with RTTYR the opposite sign. The offset is not used in this mode
    /// (for FSK it should be 0: a double click then tunes the station straight onto the mark). Without `markHz` → nil.
    public static func audioOffset(spotHz: Double, dialHz: Double, mode: String?, offsetHz: Double, markHz: Double? = nil) -> Double? {
        guard let sb = sideband(mode: mode), spotHz > 0, dialHz > 0 else { return nil }
        let target = spotHz + offsetHz
        let audio: Double
        switch sb {
        case .upper: audio = -offsetHz + (target - dialHz)
        case .lower: audio = offsetHz + (dialHz - target)
        case .rtty, .rttyReverse:
            guard let markHz, markHz.isFinite else { return nil }
            audio = sb == .rtty ? markHz + (dialHz - spotHz) : markHz + (spotHz - dialHz)
        }
        return audioRange.contains(audio) ? audio : nil
    }

    /// Lays out the labels (widths in points, center `centers[i]`) into rows: in priority order (first = most important) each
    /// gets the first row where it does not overlap earlier ones (gap `gap`). No room in `maxRows` rows → nil.
    /// A label is shifted so that it stays within 0…`totalWidth`; the overlap is computed with the shifted position.
    public static func layoutRows(centers: [Double], widths: [Double], totalWidth: Double,
                                  gap: Double = 2, maxRows: Int = BandMap.maxRows) -> [Int?] {
        var rows = [[ClosedRange<Double>]](repeating: [], count: max(0, maxRows))
        var out: [Int?] = []
        for (c, w) in zip(centers, widths) {
            let lo = min(max(c - w / 2, 0), max(0, totalWidth - w))
            let r = (lo - gap)...(lo + w + gap)
            if let i = rows.indices.first(where: { row in !rows[row].contains { $0.overlaps(r) } }) {
                rows[i].append(lo...(lo + w)); out.append(i)
            } else { out.append(nil) }
        }
        return out
    }
}
