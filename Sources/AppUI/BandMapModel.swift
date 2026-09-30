// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import Foundation
import QSOLog
import Settings
import Spots

/// A spot label in the waterfall (band map).
public struct BandMapMarker: Sendable, Equatable, Identifiable {
    /// Status of a call: new station / already in the log / dupe in the contest.
    public enum Status: Sendable, Equatable { case new, worked, dupe }
    public var spot: Spot
    public var audioHz: Double
    public var status: Status
    public var id: String { spot.id }
    public init(spot: Spot, audioHz: Double, status: Status) { self.spot = spot; self.audioHz = audioHz; self.status = status }
}

extension AppModel {
    /// A pure function: spots → labels within the displayed range `fromHz…toHz` (the newest ones, at most `BandMap.maxMarkers`).
    /// Spots outside the range (or the rig's band) are skipped. The status comes from the log index (`LogIndex`, O(1) per spot):
    /// a dupe only during a running contest, otherwise "in the log" by callsign.
    nonisolated static func bandMapMarkers(spots: [Spot], dialHz: Double, mode: String?, offsetHz: Double, markHz: Double = 2125,
                                           fromHz: Double, toHz: Double, index: LogIndex, contest: Bool) -> [BandMapMarker] {
        var out: [BandMapMarker] = []
        for s in spots.sorted(by: { $0.time > $1.time }) {
            guard let a = BandMap.audioOffset(spotHz: s.frequencyHz, dialHz: dialHz, mode: mode, offsetHz: offsetHz, markHz: markHz),
                  a >= fromHz, a <= toHz else { continue }
            out.append(BandMapMarker(spot: s, audioHz: a, status: spotStatus(s, index: index, contest: contest)))
            if out.count >= BandMap.maxMarkers { break }
        }
        return out
    }

    /// The same over a list of records (the index is built once; for tests and one-off use).
    nonisolated static func bandMapMarkers(spots: [Spot], dialHz: Double, mode: String?, offsetHz: Double, markHz: Double = 2125,
                                           fromHz: Double, toHz: Double, records: [QSORecord],
                                           contestSince: Date?) -> [BandMapMarker] {
        bandMapMarkers(spots: spots, dialHz: dialHz, mode: mode, offsetHz: offsetHz, markHz: markHz, fromHz: fromHz, toHz: toHz,
                       index: LogIndex(records: records, contestSince: contestSince, country: { _ in nil }),
                       contest: contestSince != nil)
    }

    /// A spot's status: new / already in the log / dupe in the contest (the same rule as `DupeCheck`, an O(1) index lookup).
    public nonisolated static func spotStatus(_ s: Spot, index: LogIndex, contest: Bool) -> BandMapMarker.Status {
        if contest, index.isDupe(call: s.call, band: s.band, mode: s.mode ?? "RTTY") { return .dupe }
        return index.worked(s.call) ? .worked : .new
    }

    /// A spot's status according to the current log index (the Band map window, the labels in the waterfall).
    public func spotStatus(_ s: Spot) -> BandMapMarker.Status {
        Self.spotStatus(s, index: logIndex, contest: settings.contest.enabled)
    }

    /// Labels for the current state; empty when the feature is off or the rig does not report a frequency.
    public var bandMapMarkers: [BandMapMarker] {
        guard settings.spots.showInWaterfall, let r = rig, r.online, let dial = r.frequency, dial > 0 else { return [] }
        // the band comes from the rig frequency, so only the mode groups are taken from the filter (same as in the Band map window)
        return Self.bandMapMarkers(spots: spotFeed.book.visibleModes(spotFeed.filter), dialHz: dial, mode: r.mode,
                                   offsetHz: settings.spots.offsetHz, markHz: mark, fromHz: waterfallFromHz, toHz: waterfallToHz,
                                   index: logIndex, contest: settings.contest.enabled)
    }
}
