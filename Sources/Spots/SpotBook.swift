// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import QSOLog

/// Spot list: the last N minutes, at most `maxCount`, deduplication by call + band (the newest one stays).
public struct SpotBook: Sendable, Equatable {
    public static let absoluteMax = 500
    public private(set) var byID: [String: Spot] = [:]
    public var maxCount: Int

    public init(maxCount: Int = SpotBook.absoluteMax) { self.maxCount = min(max(1, maxCount), Self.absoluteMax) }

    public var count: Int { byID.count }

    /// Adds a spot; returns false when it is older than `maxAge` or older than a stored spot of the same call and band.
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

    /// Removes spots older than `maxAge`.
    public mutating func prune(now: Date, maxAge: TimeInterval) {
        let cutoff = now.addingTimeInterval(-maxAge)
        byID = byID.filter { $0.value.time >= cutoff }
    }

    public mutating func removeAll() { byID.removeAll() }

    /// Spots from the newest, according to the display filter (checked bands and mode groups).
    public func visible(_ filter: SpotFilter) -> [Spot] { filter.apply(to: byID.values) }

    /// The same, but only by the mode filter – the band is determined by the band map window or the rig frequency.
    public func visibleModes(_ filter: SpotFilter) -> [Spot] { filter.applyModes(to: byID.values) }
}

/// Is the spot's call already in the log (and on the same band)? Contest dupes are not available, only "in the log".
public struct SpotLogIndex: Sendable {
    public enum Status: Sendable, Equatable { case none, worked, workedOnBand }
    private var bands: [String: Set<String>] = [:]      // base call → bands ("" = unknown)

    public init(_ records: [QSORecord] = []) {
        for r in records { add(r) }
    }

    /// Adds one QSO (after logging, without a rebuild).
    public mutating func add(_ r: QSORecord) { bands[QSORecord.baseCall(r.call), default: []].insert(r.band ?? "") }

    public func status(of s: Spot) -> Status {
        guard let b = bands[QSORecord.baseCall(s.call)] else { return .none }
        if let sb = s.band, b.contains(sb) { return .workedOnBand }
        return .worked
    }
}
