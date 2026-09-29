// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import Foundation
import QSOLog
import Settings
import Spots

/// Štítek spotu ve vodopádu (band map).
public struct BandMapMarker: Sendable, Equatable, Identifiable {
    /// Stav značky: nová stanice / už v logu / duplicita v závodě.
    public enum Status: Sendable, Equatable { case new, worked, dupe }
    public var spot: Spot
    public var audioHz: Double
    public var status: Status
    public var id: String { spot.id }
    public init(spot: Spot, audioHz: Double, status: Status) { self.spot = spot; self.audioHz = audioHz; self.status = status }
}

extension AppModel {
    /// Čistá funkce: spoty → štítky v zobrazeném rozsahu `fromHz…toHz` (nejnovější, nejvýše `BandMap.maxMarkers`).
    /// Spoty mimo rozsah (nebo pásmo rigu) se vynechají. Duplicita v závodě jen když je závod zapnutý (`DupeCheck`),
    /// jinak „v logu“ podle značky (`SpotLogIndex`).
    nonisolated static func bandMapMarkers(spots: [Spot], dialHz: Double, mode: String?, offsetHz: Double, markHz: Double = 2125,
                                           fromHz: Double, toHz: Double, records: [QSORecord],
                                           contestSince: Date?) -> [BandMapMarker] {
        let index = SpotLogIndex(records)
        var out: [BandMapMarker] = []
        for s in spots.sorted(by: { $0.time > $1.time }) {
            guard let a = BandMap.audioOffset(spotHz: s.frequencyHz, dialHz: dialHz, mode: mode, offsetHz: offsetHz, markHz: markHz),
                  a >= fromHz, a <= toHz else { continue }
            let st = spotStatus(s, index: index, records: records, contestSince: contestSince)
            out.append(BandMapMarker(spot: s, audioHz: a, status: st))
            if out.count >= BandMap.maxMarkers { break }
        }
        return out
    }

    /// Stav spotu: nová / už v logu (`SpotLogIndex`) / duplicita v závodě (`DupeCheck`, jen když je závod zapnutý).
    public nonisolated static func spotStatus(_ s: Spot, index: SpotLogIndex, records: [QSORecord], contestSince: Date?) -> BandMapMarker.Status {
        var st = BandMapMarker.Status.new
        if index.status(of: s) != .none { st = .worked }
        if let since = contestSince,
           DupeCheck.isDupe(call: s.call, band: s.band, mode: s.mode ?? "RTTY", records: records, since: since) { st = .dupe }
        return st
    }

    /// Štítky pro aktuální stav; prázdné, když je funkce vypnutá nebo rig nehlásí frekvenci.
    public var bandMapMarkers: [BandMapMarker] {
        guard settings.spots.showInWaterfall, let r = rig, r.online, let dial = r.frequency, dial > 0 else { return [] }
        return Self.bandMapMarkers(spots: spotFeed.book.visible(rttyOnly: spotFeed.rttyOnly), dialHz: dial, mode: r.mode,
                                   offsetHz: settings.spots.offsetHz, markHz: mark, fromHz: waterfallFromHz, toHz: waterfallToHz,
                                   records: logRecords,
                                   contestSince: settings.contest.enabled ? settings.contest.effectiveStart : nil)
    }
}
