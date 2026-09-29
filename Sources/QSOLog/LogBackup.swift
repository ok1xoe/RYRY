// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Zálohy logu: kopie `<název>.jsonl`, `.adi` a QTC do `<složka logu>/backup/<název>-RRRRMMDD-HHMMSS/`;
/// drží se jen posledních `keep` záloh daného logu.
public enum LogBackup {
    public enum BackupError: Error, Equatable { case nothingToBackup }

    static let stamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd-HHmmss"; return f
    }()

    public static func directory(for loc: LogLocation) -> URL { loc.directory.appendingPathComponent("backup") }

    /// Zálohy daného logu, nejstarší první.
    public static func existing(for loc: LogLocation) -> [URL] {
        let root = directory(for: loc)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { $0.hasPrefix(loc.name + "-") && stamp.date(from: String($0.dropFirst(loc.name.count + 1))) != nil }
            .sorted().map { root.appendingPathComponent($0) }
    }

    @discardableResult
    public static func backup(_ loc: LogLocation, at date: Date = Date(), keep: Int = 10) throws -> URL {
        let fm = FileManager.default
        let files = [loc.jsonlURL, loc.adifURL, loc.qtcURL].filter { fm.fileExists(atPath: $0.path) }
        guard files.contains(loc.jsonlURL) else { throw BackupError.nothingToBackup }
        let dst = directory(for: loc).appendingPathComponent("\(loc.name)-\(stamp.string(from: date))")
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        for f in files {
            let to = dst.appendingPathComponent(f.lastPathComponent)
            if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
            try fm.copyItem(at: f, to: to)
        }
        let all = existing(for: loc)
        for old in all.dropLast(max(1, keep)) { try? fm.removeItem(at: old) }
        return dst
    }

    /// Je čas na denní zálohu (poslední je starší než 24 h, nebo žádná není)?
    public static func isDue(_ loc: LogLocation, now: Date = Date(), interval: TimeInterval = 86_400) -> Bool {
        guard let last = existing(for: loc).last,
              let d = stamp.date(from: String(last.lastPathComponent.dropFirst(loc.name.count + 1))) else { return true }
        return now.timeIntervalSince(d) >= interval
    }
}

/// Statistika logu: rychlost (spojení/h za posledních 10 a 60 min) a počty podle pásem.
public struct LogStats: Sendable, Equatable {
    public struct BandCount: Sendable, Equatable, Identifiable {
        public var band: String, count: Int
        public var id: String { band }
        public init(band: String, count: Int) { self.band = band; self.count = count }
    }
    public let total: Int, last10: Int, last60: Int
    public var rate10: Int { last10 * 6 }
    public var rate60: Int { last60 }
    public let byBand: [BandCount]

    public init(records: [QSORecord], now: Date = Date(), since: Date? = nil) {
        let recs = since.map { s in records.filter { $0.timeOn >= s } } ?? records
        total = recs.count
        last10 = recs.filter { now.timeIntervalSince($0.timeOn) >= 0 && now.timeIntervalSince($0.timeOn) <= 600 }.count
        last60 = recs.filter { now.timeIntervalSince($0.timeOn) >= 0 && now.timeIntervalSince($0.timeOn) <= 3600 }.count
        var counts: [String: Int] = [:]
        for r in recs { counts[r.band ?? "?", default: 0] += 1 }
        let order = Bands.table.map(\.0)
        byBand = counts.map { BandCount(band: $0.key, count: $0.value) }
            .sorted { (order.firstIndex(of: $0.band) ?? .max, $0.band) < (order.firstIndex(of: $1.band) ?? .max, $1.band) }
    }
}
