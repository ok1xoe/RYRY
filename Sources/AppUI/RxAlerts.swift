// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import Foundation
import QSOLog
import Settings

/// Země pro kontrolu „potřebné“: klíč (hlavní prefix z cty.dat) a název pro zobrazení.
public struct CountryRef: Sendable, Equatable {
    public var key: String
    public var name: String
    public init(key: String, name: String) { self.key = key; self.name = name }
}

/// Index logu pro levné dotazy při zvýrazňování příjmu a hlídání: základní značky, země (celkem a po pásmech)
/// a klíče duplicit v závodě. Přestavuje se při přepnutí logu / změně závodu, při zalogování se jen doplní.
public struct LogIndex: Sendable, Equatable {
    public private(set) var calls: Set<String> = []
    public private(set) var countries: Set<String> = []
    public private(set) var countriesByBand: [String: Set<String>] = [:]
    private var dupes: Set<String> = []
    /// Duplicity rozlišují mód (vlastní závod); předvolby ne – `DupeCheck.perMode`.
    public private(set) var dupePerMode = true

    public init() {}

    /// `contestSince` = začátek běžícího závodu (nil = žádný závod, duplicity se neevidují).
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

    /// Značka (základní) je někdy v logu.
    public func worked(_ call: String) -> Bool { calls.contains(QSORecord.baseCall(call)) }

    /// Země je v logu (na daném pásmu; bez pásma kdykoli).
    public func countryWorked(_ key: String, band: String?) -> Bool {
        guard let band else { return countries.contains(key) }
        return countriesByBand[band]?.contains(key) ?? false
    }

    /// Stejné pravidlo a klíč jako `DupeCheck.isDupe` (bez známého pásma se porovná jen značka, případně mód).
    public func isDupe(call: String, band: String?, mode: String) -> Bool {
        dupes.contains(DupeCheck.key(call: call, band: band, mode: mode, perMode: dupePerMode))
    }
}

/// Styl značky v příjmu.
public enum CallStyle: Equatable, Sendable {
    case own       // moje značka: červeně tučně
    case dupe      // duplicita v závodě: šedě přeškrtnuto
    case worked    // už v logu: modře
    case new       // ještě v logu není: tučně
}

/// Čistá logika zvýrazňování značek v příjmu (bez AppKit, testovatelná).
public enum CallHighlight {
    /// Styl slova (nil = není značka). `myBase` = základní značka stanice, `contest` = běží závod.
    public static func style(word: String, myBase: String, band: String?, mode: String, contest: Bool,
                             index: LogIndex) -> CallStyle? {
        guard let call = WordClassifier.callCandidate(word) else { return nil }
        let base = QSORecord.baseCall(call)
        if !myBase.isEmpty, base == myBase, base.count >= 3 { return .own }
        guard WordClassifier.classify(call) == .call else { return nil }
        if contest, index.isDupe(call: call, band: band, mode: mode) { return .dupe }
        return index.worked(call) ? .worked : .new
    }

    /// Rozsahy slov (úseky bez mezer) v `range`.
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

    /// Odkud přestylovat po přidání textu na pozici `appendedAt`: pokud přidání navazuje na neúplné slovo,
    /// od jeho začátku (slovo rozdělené mezi dvě přidání), jinak od místa přidání.
    public static func restyleStart(in text: NSString, appendedAt: Int) -> Int {
        var i = min(max(0, appendedAt), text.length)
        while i > 0, !isSpace(text.character(at: i - 1)) { i -= 1 }
        return i
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 10 || c == 13 || c == 9 || c == 0xA0 }
}

extension WordClassifier {
    /// Slovo bez okolní interpunkce (kromě „/“) velkými písmeny; nil pro prázdné nebo příliš dlouhé.
    public static func callCandidate(_ word: String) -> String? {
        let w = word.uppercased().trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "/"))
            .union(.whitespacesAndNewlines))
        return w.isEmpty || w.count > 14 ? nil : w
    }
}

/// Čistá logika „potřebné“: hlídaná značka, nová země na pásmu, nová země vůbec.
public enum NeededCheck {
    public enum Reason: Equatable, Sendable {
        case watched
        case newCountry(country: String)
        case newCountryBand(country: String, band: String)
    }

    /// Důvody, proč je značka potřebná (prázdné = není). Nová země vůbec má přednost před novou zemí na pásmu.
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

    /// Klíč pro deduplikaci upozornění (značka + pásmo).
    public static func dedupeKey(call: String, band: String?) -> String { "needed|\(QSORecord.baseCall(call))|\(band ?? "")" }
}

/// Omezení opakování upozornění: stejný klíč nejdřív po `interval` sekundách. Paměť je omezená.
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

/// Výskyty značek v příjmu za posledních `window` sekund (potvrzení značky proti šumu). Paměť je omezená.
public struct RxCallSightings: Sendable {
    public static let window: TimeInterval = 600
    private var seen: [String: [Date]] = [:]
    public let maxKeys: Int
    public init(maxKeys: Int = 2000) { self.maxKeys = max(1, maxKeys) }
    public var count: Int { seen.count }

    /// Zaznamená výskyt značky a vrátí počet jejích výskytů v okně (včetně tohoto).
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

/// Dělí přijímaný text (po znacích i po částech) na dokončená slova; echo vlastního vysílání přeskakuje
/// a ukončuje rozdělané slovo. Značka rozdělená mezi dvě přidání se tak nalezne jednou, celá.
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
                pending = String(pending.dropFirst()); pending.append(ch)     // příliš dlouhé „slovo“ (šum): jen konec
            }
        }
        return out
    }

    public mutating func reset() { pending = "" }
}

/// Zvuk a systémové oznámení (vyměnitelné v testech).
@MainActor public protocol AlertSink: AnyObject {
    func playSound()
    /// Zobrazí oznámení; skutečná implementace ho posílá jen když aplikace není aktivní.
    func notify(title: String, body: String)
    /// Vyžádá oprávnění k oznámením (volá se až při zapnutí funkce).
    func requestNotificationAuthorization()
}

@MainActor public final class NullAlertSink: AlertSink {
    public init() {}
    public func playSound() {}
    public func notify(title: String, body: String) {}
    public func requestNotificationAuthorization() {}
}
