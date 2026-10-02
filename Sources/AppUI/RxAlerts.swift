// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppCore
import Foundation
import QSOLog
import Settings

/// An entity for the "needed" check: the key (the main prefix from cty.dat) and the display name.
public struct CountryRef: Sendable, Equatable {
    public var key: String
    public var name: String
    public init(key: String, name: String) { self.key = key; self.name = name }
}

/// A log index for cheap lookups while highlighting the receive text and watching: base calls, entities (overall and per band)
/// and the dupe keys of the contest. It is rebuilt when the log is switched / the contest changes; logging a QSO only adds to it.
public struct LogIndex: Sendable, Equatable {
    public private(set) var calls: Set<String> = []
    public private(set) var countries: Set<String> = []
    public private(set) var countriesByBand: [String: Set<String>] = [:]
    private var dupes: Set<String> = []
    /// Dupes distinguish the mode (for a custom contest); the presets do not - `DupeCheck.perMode`.
    public private(set) var dupePerMode = true

    public init() {}

    /// `contestSince` = the start of the running contest (nil = no contest, dupes are not tracked).
    public init(records: [QSORecord], contestSince: Date?, dupePerMode: Bool = true, country: (String) -> CountryRef?) {
        self.dupePerMode = dupePerMode
        var cache: [String: CountryRef?] = [:]
        for r in records { add(r, contestSince: contestSince, country: country, cache: &cache) }
    }

    public mutating func add(_ r: QSORecord, contestSince: Date?, country: (String) -> CountryRef?) {
        var cache: [String: CountryRef?] = [:]
        add(r, contestSince: contestSince, country: country, cache: &cache)
    }

    private mutating func add(_ r: QSORecord, contestSince: Date?, country: (String) -> CountryRef?,
                              cache: inout [String: CountryRef?]) {
        let base = QSORecord.baseCall(r.call)
        calls.insert(base)
        let c: CountryRef?
        if let hit = cache[base] { c = hit } else { c = country(r.call); cache[base] = .some(c) }
        if let c {
            countries.insert(c.key)
            countriesByBand[r.band ?? "", default: []].insert(c.key)
        }
        if let since = contestSince, r.timeOn >= since {
            dupes.insert(DupeCheck.key(call: r.call, band: nil, mode: r.mode, perMode: dupePerMode))
            dupes.insert(DupeCheck.key(call: r.call, band: r.band ?? "", mode: r.mode, perMode: dupePerMode))
        }
    }

    /// The (base) callsign is in the log at some point.
    public func worked(_ call: String) -> Bool { calls.contains(QSORecord.baseCall(call)) }

    /// The entity is in the log (on the given band; without a band, at any time).
    public func countryWorked(_ key: String, band: String?) -> Bool {
        guard let band else { return countries.contains(key) }
        return countriesByBand[band]?.contains(key) ?? false
    }

    /// The same rule and key as `DupeCheck.isDupe` (with no known band only the call, and possibly the mode, is compared).
    public func isDupe(call: String, band: String?, mode: String) -> Bool {
        dupes.contains(DupeCheck.key(call: call, band: band, mode: mode, perMode: dupePerMode))
    }
}

/// The style of a callsign in the receive window.
public enum CallStyle: Equatable, Sendable {
    case own       // my own call: red and bold
    case dupe      // a dupe in the contest: gray and struck through
    case worked    // already in the log: blue
    case new       // not in the log yet: bold
}

/// Pure logic for highlighting callsigns in the receive window (no AppKit, testable).
public enum CallHighlight {
    /// The style of a word (nil = not a callsign). `myBase` = the station's base call, `contest` = a contest is running.
    public static func style(word: String, myBase: String, band: String?, mode: String, contest: Bool,
                             index: LogIndex) -> CallStyle? {
        guard let call = WordClassifier.callCandidate(word) else { return nil }
        let base = QSORecord.baseCall(call)
        if !myBase.isEmpty, base == myBase, base.count >= 3 { return .own }
        guard WordClassifier.classify(call) == .call else { return nil }
        if contest, index.isDupe(call: call, band: band, mode: mode) { return .dupe }
        return index.worked(call) ? .worked : .new
    }

    /// The ranges of the words (runs without spaces) within `range`.
    public static func wordRanges(in text: NSString, range: NSRange) -> [NSRange] {
        var out: [NSRange] = []
        var start: Int?
        let end = min(NSMaxRange(range), text.length)
        var i = max(0, range.location)
        while i < end {
            let ws = isSpace(text.character(at: i))
            if ws { if let s = start { out.append(NSRange(location: s, length: i - s)); start = nil } }
            else if start == nil { start = i }
            i += 1
        }
        if let s = start { out.append(NSRange(location: s, length: end - s)) }
        return out
    }

    /// Where to restyle from after text was appended at `appendedAt`: if the append continues an incomplete word,
    /// from that word's start (a word split across two appends), otherwise from the append position.
    public static func restyleStart(in text: NSString, appendedAt: Int) -> Int {
        var i = min(max(0, appendedAt), text.length)
        while i > 0, !isSpace(text.character(at: i - 1)) { i -= 1 }
        return i
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 10 || c == 13 || c == 9 || c == 0xA0 }
}

extension WordClassifier {
    /// The word without the surrounding punctuation (except "/") in uppercase; nil for an empty or overly long one.
    public static func callCandidate(_ word: String) -> String? {
        let w = word.uppercased().trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "/"))
            .union(.whitespacesAndNewlines))
        return w.isEmpty || w.count > 14 ? nil : w
    }
}

/// Pure "needed" logic: a watched call, a new entity on the band, a new entity at all.
public enum NeededCheck {
    public enum Reason: Equatable, Sendable {
        case watched
        case newCountry(country: String)
        case newCountryBand(country: String, band: String)
    }

    /// The reasons why a call is needed (empty = it is not). A brand-new entity takes precedence over a new entity on the band.
    public static func check(call: String, band: String?, country: CountryRef?, settings: AlertSettings,
                             index: LogIndex) -> [Reason] {
        var out: [Reason] = []
        if settings.watchSet.contains(QSORecord.baseCall(call)) { out.append(.watched) }
        if let country {
            if settings.newCountryAny, !index.countryWorked(country.key, band: nil) {
                out.append(.newCountry(country: country.name))
            } else if settings.newCountryBand, let band, !index.countryWorked(country.key, band: band) {
                out.append(.newCountryBand(country: country.name, band: band))
            }
        }
        return out
    }

    /// The key for deduplicating alerts (call + band).
    public static func dedupeKey(call: String, band: String?) -> String { "needed|\(QSORecord.baseCall(call))|\(band ?? "")" }
}

/// Rate limit for repeated alerts: the same key no sooner than `interval` seconds later. The memory is bounded.
public struct AlertThrottle: Sendable {
    private var last: [String: Date] = [:]
    public let maxKeys: Int
    public init(maxKeys: Int = 2000) { self.maxKeys = max(1, maxKeys) }
    public var count: Int { last.count }

    public mutating func allow(_ key: String, now: Date, interval: TimeInterval) -> Bool {
        if let t = last[key], now.timeIntervalSince(t) < interval { return false }
        last[key] = now
        if last.count > maxKeys {
            for (k, _) in last.sorted(by: { $0.value < $1.value }).prefix(last.count - maxKeys) where k != key { last[k] = nil }
        }
        return true
    }
}

/// Occurrences of callsigns in the receive text over the last `window` seconds (confirming a call against noise). The memory is bounded.
public struct RxCallSightings: Sendable {
    public static let window: TimeInterval = 600
    private var seen: [String: [Date]] = [:]
    public let maxKeys: Int
    public init(maxKeys: Int = 2000) { self.maxKeys = max(1, maxKeys) }
    public var count: Int { seen.count }

    /// Records an occurrence of a call and returns how many times it occurred within the window (including this one).
    public mutating func record(_ call: String, now: Date) -> Int {
        var list = (seen[call] ?? []).filter { now.timeIntervalSince($0) < Self.window }
        list.append(now)
        if list.count > 3 { list.removeFirst(list.count - 3) }
        seen[call] = list
        if seen.count > maxKeys {
            seen = seen.filter { k, v in k == call || v.contains { now.timeIntervalSince($0) < Self.window } }
            if seen.count > maxKeys {
                let old = seen.filter { $0.key != call }.sorted { ($0.value.last ?? .distantPast) < ($1.value.last ?? .distantPast) }
                for (k, _) in old.prefix(seen.count - maxKeys) { seen[k] = nil }
            }
        }
        return list.count
    }
}

/// Splits the received text (character by character or in chunks) into completed words; it skips the echo of our own transmission
/// and terminates the word in progress. A call split across two appends is therefore found once, whole.
public struct RxWordScanner: Sendable {
    public static let maxWord = 40
    private var pending = ""
    public init() {}
    public var pendingCount: Int { pending.count }

    public mutating func feed(_ s: String, echo: Bool) -> [String] {
        if echo { pending = ""; return [] }
        var out: [String] = []
        for ch in s {
            if ch.isWhitespace {
                if !pending.isEmpty { out.append(pending); pending = "" }
            } else if pending.count < Self.maxWord {
                pending.append(ch)
            } else {
                pending = String(pending.dropFirst()); pending.append(ch)     // an overly long "word" (noise): keep only the end
            }
        }
        return out
    }

    public mutating func reset() { pending = "" }
}

/// Sound and system notification (replaceable in tests).
@MainActor public protocol AlertSink: AnyObject {
    func playSound()
    /// Shows a notification; the real implementation only posts it when the app is not active.
    func notify(title: String, body: String)
    /// Requests notification permission (only called when the feature is turned on).
    func requestNotificationAuthorization()
}

@MainActor public final class NullAlertSink: AlertSink {
    public init() {}
    public func playSound() {}
    public func notify(title: String, body: String) {}
    public func requestNotificationAuthorization() {}
}
