// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import QSOLog

/// Seznam spotů: posledních N minut, nejvýše `maxCount`, deduplikace značka + pásmo (zůstává nejnovější).
public struct SpotBook: Sendable, Equatable {
    public static let absoluteMax = 500
    public private(set) var byID: [String: Spot] = [:]
    public var maxCount: Int

    public init(maxCount: Int = SpotBook.absoluteMax) { self.maxCount = min(max(1, maxCount), Self.absoluteMax) }

    public var count: Int { byID.count }

    /// Přidá spot; vrací false, když je starší než `maxAge` nebo starší než už uložený spot téže značky a pásma.
    @discardableResult
    public mutating func add(_ s: Spot, now: Date, maxAge: TimeInterval) -> Bool {
        guard s.time >= now.addingTimeInterval(-maxAge) else { return false }
        if let old = byID[s.id], old.time > s.time { return false }
        byID[s.id] = s
        if byID.count > maxCount {
            let drop = byID.values.sorted { $0.time < $1.time }.prefix(byID.count - maxCount)
            for d in drop { byID[d.id] = nil }
        }
        return true
    }

    /// Odstraní spoty starší než `maxAge`.
    public mutating func prune(now: Date, maxAge: TimeInterval) {
        let cutoff = now.addingTimeInterval(-maxAge)
        byID = byID.filter { $0.value.time >= cutoff }
    }

    public mutating func removeAll() { byID.removeAll() }

    /// Spoty od nejnovějšího podle filtru zobrazení (zaškrtnutá pásma a skupiny módů).
    public func visible(_ filter: SpotFilter) -> [Spot] { filter.apply(to: byID.values) }

    /// Totéž, ale jen podle filtru módů – pásmo určuje okno band mapy nebo frekvence rigu.
    public func visibleModes(_ filter: SpotFilter) -> [Spot] { filter.applyModes(to: byID.values) }
}

/// Zda je značka ze spotu už v logu (a na stejném pásmu). Duplicity v závodě nejsou k dispozici, jen „v logu“.
public struct SpotLogIndex: Sendable {
    public enum Status: Sendable, Equatable { case none, worked, workedOnBand }
    private var bands: [String: Set<String>] = [:]      // základní značka → pásma ("" = neznámé)

    public init(_ records: [QSORecord] = []) {
        for r in records { add(r) }
    }

    /// Doplní jedno spojení (po zalogování, bez přestavby).
    public mutating func add(_ r: QSORecord) { bands[QSORecord.baseCall(r.call), default: []].insert(r.band ?? "") }

    public func status(of s: Spot) -> Status {
        guard let b = bands[QSORecord.baseCall(s.call)] else { return .none }
        if let sb = s.band, b.contains(sb) { return .workedOnBand }
        return .worked
    }
}
