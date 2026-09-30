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
    /// Spoty mimo rozsah (nebo pásmo rigu) se vynechají. Stav podle indexu logu (`LogIndex`, O(1) na spot):
    /// duplicita jen v běžícím závodě, jinak „v logu“ podle značky.
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

    /// Totéž nad seznamem záznamů (index se sestaví jednorázově; pro testy a jednorázové použití).
    nonisolated static func bandMapMarkers(spots: [Spot], dialHz: Double, mode: String?, offsetHz: Double, markHz: Double = 2125,
                                           fromHz: Double, toHz: Double, records: [QSORecord],
                                           contestSince: Date?) -> [BandMapMarker] {
        bandMapMarkers(spots: spots, dialHz: dialHz, mode: mode, offsetHz: offsetHz, markHz: markHz, fromHz: fromHz, toHz: toHz,
                       index: LogIndex(records: records, contestSince: contestSince, country: { _ in nil }),
                       contest: contestSince != nil)
    }

    /// Stav spotu: nová / už v logu / duplicita v závodě (stejné pravidlo jako `DupeCheck`, dotaz do indexu v O(1)).
    public nonisolated static func spotStatus(_ s: Spot, index: LogIndex, contest: Bool) -> BandMapMarker.Status {
        if contest, index.isDupe(call: s.call, band: s.band, mode: s.mode ?? "RTTY") { return .dupe }
        return index.worked(s.call) ? .worked : .new
    }

    /// Stav spotu podle aktuálního indexu logu (okno Band mapa, štítky ve vodopádu).
    public func spotStatus(_ s: Spot) -> BandMapMarker.Status {
        Self.spotStatus(s, index: logIndex, contest: settings.contest.enabled)
    }

    /// Štítky pro aktuální stav; prázdné, když je funkce vypnutá nebo rig nehlásí frekvenci.
    public var bandMapMarkers: [BandMapMarker] {
        guard settings.spots.showInWaterfall, let r = rig, r.online, let dial = r.frequency, dial > 0 else { return [] }
        // pásmo dává frekvence rigu, proto z filtru jen skupiny módů (stejně jako v okně Band mapa)
        return Self.bandMapMarkers(spots: spotFeed.book.visibleModes(spotFeed.filter), dialHz: dial, mode: r.mode,
                                   offsetHz: settings.spots.offsetHz, markHz: mark, fromHz: waterfallFromHz, toHz: waterfallToHz,
                                   index: logIndex, contest: settings.contest.enabled)
    }
}
