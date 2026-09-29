// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import DXCC
import Localization
import QSOLog
import Settings

// Násobiče v závodech (jen násobiče, ne body ani skóre). Pravidla a zdroje: docs/rulings.md, „Násobiče v závodech“.

/// Druh násobiče.
public enum MultiplierKind: String, Sendable, CaseIterable, Hashable, Codable {
    /// Země DXCC (u CQ WW i seznam WAE).
    case dxcc
    /// CQ zóna 1–40 (z přijaté výměny, jinak z DXCC).
    case cqZone
    /// Prefix podle pravidel CQ WPX.
    case wpxPrefix
    /// Stát USA z přijaté výměny (48 kontinentálních + DC).
    case usState
    /// Kanadská provincie/oblast z přijaté výměny (14 včetně LB).
    case veProvince
    /// Číselná oblast JA/W/VE/VK (W1, VE3, JA7, VK2 …).
    case callArea
    /// WAE DX Contest: země seznamu WAE, u W/VE/VK/ZL/ZS/JA/BY/PY/UA9 číselné oblasti.
    case waeCountry
    /// Kontinent (BARTG, jednou za závod).
    case continent
    /// OK DX RTTY: každá stanice OK/OL.
    case okStation

    public var title: String {
        switch self {
        case .dxcc: return L("Země DXCC")
        case .cqZone: return L("CQ zóny")
        case .wpxPrefix: return L("Prefixy WPX")
        case .usState: return L("Státy USA")
        case .veProvince: return L("Kanadské provincie")
        case .callArea: return L("Oblasti JA/W/VE/VK")
        case .waeCountry: return L("Země WAE")
        case .continent: return L("Kontinenty")
        case .okStation: return L("Stanice OK/OL")
        }
    }

    /// Konečná množina hodnot (pro seznam chybějících); nil = otevřená množina.
    public var universe: [String]? {
        switch self {
        case .cqZone: return (1...40).map(String.init)
        case .usState: return Multipliers.usStates
        case .veProvince: return Multipliers.veProvinces
        case .continent: return ["AF", "AS", "EU", "NA", "OC", "SA"]
        default: return nil
        }
    }

    /// Hodnota pro štítek (zóna jako „Z14“, ostatní beze změny).
    public func label(_ value: String) -> String { self == .cqZone ? "Z\(value)" : value }
}

/// Jeden druh násobiče v pravidlech závodu.
public struct MultiplierComponent: Sendable, Equatable, Hashable {
    public var kind: MultiplierKind
    /// true = počítá se na každém pásmu zvlášť, false = jednou za závod.
    public var perBand: Bool
    public init(_ kind: MultiplierKind, perBand: Bool) { self.kind = kind; self.perBand = perBand }
}

/// Pravidla násobičů jednoho závodu.
public struct MultiplierRule: Sendable, Equatable {
    public var preset: ContestPreset
    public var components: [MultiplierComponent]
    /// Země (primární prefix cty.dat), které se jako země DXCC nepočítají.
    public var excludedCountries: Set<String> = []
    /// Země se hledají i v seznamu WAE (Sicílie, Shetlandy, evropské Turecko, …).
    public var waeList = false
    /// Země (primární prefix cty.dat), u kterých se počítají číselné oblasti.
    public var callAreaCountries: [String] = []
    /// Váha pásma (WAE: 80 m × 4, 40 m × 3, ostatní × 2); chybějící pásmo = 1.
    public var bandWeights: [String: Int] = [:]
    /// Pravidlo ověřené v oficiálních pravidlech závodu (zdroj v `source`).
    public var verified: Bool
    /// Neověřené části pravidla (prázdné = vše ověřeno).
    public var unverifiedNote: String = ""
    public var source: String
    /// Poznámka k závodu pro okno Násobiče.
    public var note: String = ""

    public var hasMultipliers: Bool { !components.isEmpty }
    public func component(_ k: MultiplierKind) -> MultiplierComponent? { components.first { $0.kind == k } }

    /// Pravidla pro závodní nastavení; nil = mimo závod nebo vlastní (nerozpoznaný) závod.
    /// `ownCountry` = primární prefix vlastní země (OK DX RTTY: stanice OK/OL mají jiné násobiče).
    public static func rule(for contest: ContestSettings, ownCountry: String?) -> MultiplierRule? {
        guard contest.enabled, let p = contest.selectedPreset else { return nil }
        return rule(for: p, ownCountry: ownCountry)
    }

    public static func rule(for p: ContestPreset, ownCountry: String? = nil) -> MultiplierRule {
        let jwvv = ["K", "VE", "JA", "VK"]
        switch p {
        case .arrlRoundup:
            return MultiplierRule(preset: p, components: [.init(.dxcc, perBand: false), .init(.usState, perBand: false),
                                                          .init(.veProvince, perBand: false)],
                                  excludedCountries: ["K", "VE"], verified: true,
                                  source: "https://contests.arrl.org/ContestRules/RTTY-RU-Rules.pdf",
                                  note: L("Země DXCC kromě USA a Kanady (KH6 a KL7 jsou země), státy USA + DC, kanadské provincie a teritoria + LB – každý jednou za závod. Stát/provincii zapisujte do pole výměny."))
        case .cqwpxRTTY:
            return MultiplierRule(preset: p, components: [.init(.wpxPrefix, perBand: false)], verified: true,
                                  unverifiedNote: L("Značka s /číslice (W1ABC/3 → W3) – v pravidlech CQ WPX neuvedeno, použita obvyklá praxe."),
                                  source: "https://cqwpxrtty.com/rules.htm",
                                  note: L("Každý prefix jednou za závod (PA/N8BJQ = PA0, XEFTJW = XE0, /P /M /MM /QRP se ignorují)."))
        case .bartgHF:
            return MultiplierRule(preset: p, components: [.init(.dxcc, perBand: true), .init(.callArea, perBand: true),
                                                          .init(.continent, perBand: false)],
                                  callAreaCountries: jwvv, verified: true,
                                  source: "https://bartg.org.uk/wp-content/uploads/2025/05/bartg-hf-rtty-rules-2025-v3.pdf",
                                  note: L("Země DXCC (včetně JA, W, VE, VK) a oblasti JA/W/VE/VK na každém pásmu; kontinenty jednou za závod (max. 6), ve skóre se násobí zvlášť."))
        case .sartgRTTY:
            return MultiplierRule(preset: p, components: [.init(.dxcc, perBand: true), .init(.callArea, perBand: true)],
                                  callAreaCountries: jwvv, verified: true, source: "https://www.sartg.com/contest/wwrules.htm",
                                  note: L("Země DXCC (včetně VK, VE, JA, W) a oblasti VK/VE/JA/W na každém pásmu."))
        case .cqwwRTTY:
            return MultiplierRule(preset: p, components: [.init(.cqZone, perBand: true), .init(.dxcc, perBand: true),
                                                          .init(.usState, perBand: true), .init(.veProvince, perBand: true)],
                                  waeList: true, verified: true, source: "https://www.cqwwrtty.com/rules.htm",
                                  note: L("CQ zóny, země DXCC + seznam WAE a W/VE QTH (48 států + DC, 14 kanadských oblastí) na každém pásmu. KH6 a KL7 jsou jen země."))
        case .makrothen:
            return MultiplierRule(preset: p, components: [], verified: true, source: "https://www.pl259.org/makrothen/makrothen-rules/",
                                  note: L("Makrothen nemá násobiče – body podle vzdálenosti mezi lokátory a váhy pásma."))
        case .jartsRTTY:
            return MultiplierRule(preset: p, components: [.init(.dxcc, perBand: true), .init(.callArea, perBand: true)],
                                  excludedCountries: Set(jwvv), callAreaCountries: jwvv, verified: true,
                                  source: "https://jarl.org/English/4_Library/A-4-3_Contests/rtty_rules_en.html",
                                  note: L("Země DXCC kromě JA/W/VE/VK a místo nich jejich číselné oblasti, na každém pásmu (portable bez číslice = oblast 0)."))
        case .waeRTTY:
            return MultiplierRule(preset: p, components: [.init(.waeCountry, perBand: true)], waeList: true,
                                  callAreaCountries: ["K", "VE", "VK", "ZL", "ZS", "JA", "BY", "PY", "UA9"],
                                  bandWeights: ["80m": 4, "40m": 3, "20m": 2, "15m": 2, "10m": 2], verified: true,
                                  source: "https://www.darc.de/der-club/referate/conteste/wae-dx-contest/en/wae-rules/",
                                  note: L("RTTY: evropské i mimoevropské násobiče platí pro všechny stanice. Země WAE na každém pásmu, u W/VE/VK/ZL/ZS/JA/BY/PY a RA8/RA9/RA0 číselné oblasti. Váhy pásem: 80 m × 4, 40 m × 3, ostatní × 2."))
        case .okDXRTTY:
            let ok = ownCountry == "OK"
            return MultiplierRule(preset: p, components: ok ? [.init(.dxcc, perBand: true)]
                                                            : [.init(.dxcc, perBand: true), .init(.okStation, perBand: true)],
                                  verified: true,
                                  unverifiedNote: ok ? "" : L("Zda se země OK počítá i jako země DXCC vedle stanic OK/OL – pravidla výslovně neuvádějí, počítá se obojí."),
                                  source: "http://okrtty.crk.cz/index.php?page=english",
                                  note: ok ? L("Stanice OK/OL: země DXCC na každém pásmu.")
                                           : L("Země DXCC a každá stanice OK/OL na každém pásmu."))
        }
    }
}

/// Jeden násobič spojení (druh + hodnota).
public struct MultiplierHit: Sendable, Hashable, Codable {
    public var kind: MultiplierKind
    public var value: String
    public init(_ kind: MultiplierKind, _ value: String) { self.kind = kind; self.value = value }
    public var label: String { kind.label(value) }
}

/// Násobiče, které by spojení přineslo (pro štítek NEW MULT).
public struct NewMultiplier: Sendable, Equatable {
    public var hits: [MultiplierHit]
    /// Pásmo, na kterém jsou nové (nil = pásmo neznámé, nové jen násobiče „jednou za závod“).
    public var band: String?
    public init(hits: [MultiplierHit] = [], band: String? = nil) { self.hits = hits; self.band = band }
    public var isEmpty: Bool { hits.isEmpty }
    public var text: String {
        let l = hits.map(\.label).joined(separator: ", ")
        return band.map { "\($0): \(l)" } ?? l
    }
}

/// Odpracované násobiče závodu: pro každé pásmo a pro násobiče „jednou za závod“.
public struct MultiplierTally: Sendable, Equatable {
    public let rule: MultiplierRule
    public private(set) var perBand: [String: [MultiplierKind: Set<String>]] = [:]
    public private(set) var once: [MultiplierKind: Set<String>] = [:]
    public private(set) var qsoCount = 0

    public init(rule: MultiplierRule) { self.rule = rule }

    public mutating func add(_ hits: [MultiplierHit], band: String?) {
        qsoCount += 1
        for h in hits {
            guard let c = rule.component(h.kind) else { continue }
            if c.perBand {
                guard let band else { continue }
                perBand[band, default: [:]][h.kind, default: []].insert(h.value)
            } else {
                once[h.kind, default: []].insert(h.value)
            }
        }
    }

    /// Odpracované hodnoty; `band` se použije jen u násobičů po pásmech.
    public func worked(_ kind: MultiplierKind, band: String?) -> Set<String> {
        guard let c = rule.component(kind) else { return [] }
        if c.perBand { return band.flatMap { perBand[$0]?[kind] } ?? [] }
        return once[kind] ?? []
    }

    /// Chybějící hodnoty (jen konečné množiny), seřazené.
    public func missing(_ kind: MultiplierKind, band: String?) -> [String]? {
        guard let u = kind.universe else { return nil }
        let w = worked(kind, band: band)
        return u.filter { !w.contains($0) }
    }

    /// Pásma s aspoň jedním násobičem po pásmech, v pořadí od nejdelšího.
    public var bands: [String] { Multipliers.sortBands(Array(perBand.keys)) }

    /// Násobiče po pásmech na daném pásmu (všechny druhy).
    public func count(band: String) -> Int { perBand[band]?.values.reduce(0) { $0 + $1.count } ?? 0 }
    /// Násobiče jednou za závod.
    public var onceCount: Int { once.values.reduce(0) { $0 + $1.count } }
    /// Celkový počet druhu (po pásmech sečteno přes pásma).
    public func total(_ kind: MultiplierKind) -> Int {
        guard let c = rule.component(kind) else { return 0 }
        if c.perBand { return perBand.values.reduce(0) { $0 + ($1[kind]?.count ?? 0) } }
        return once[kind]?.count ?? 0
    }
    /// Násobičů celkem (bez vah pásem).
    public var total: Int { perBand.keys.reduce(0) { $0 + count(band: $1) } + onceCount }
    /// Násobičů celkem s váhou pásem (WAE); bez vah = `total`.
    public var weightedTotal: Int {
        perBand.keys.reduce(0) { $0 + count(band: $1) * (rule.bandWeights[$1] ?? 1) } + onceCount
    }

    /// Které z násobičů spojení jsou nové (na daném pásmu / v závodě).
    public func newHits(_ hits: [MultiplierHit], band: String?) -> NewMultiplier {
        var out: [MultiplierHit] = []
        for h in hits where !out.contains(h) {
            guard let c = rule.component(h.kind) else { continue }
            if c.perBand, band == nil { continue }
            if !worked(h.kind, band: band).contains(h.value) { out.append(h) }
        }
        let anyPerBand = out.contains { rule.component($0.kind)?.perBand == true }
        return NewMultiplier(hits: out, band: anyPerBand ? band : nil)
    }
}

/// Výpočet násobičů spojení podle pravidel závodu.
public struct MultiplierCalculator: Sendable {
    public let rule: MultiplierRule
    let lookup: @Sendable (String, Bool) -> CountryInfo?

    public init(rule: MultiplierRule, lookup: @escaping @Sendable (String, Bool) -> CountryInfo?) {
        self.rule = rule; self.lookup = lookup
    }
    public init(rule: MultiplierRule, countries: CountryDB?) {
        self.init(rule: rule) { call, wae in countries?.lookup(call, wae: wae) }
    }

    /// Násobiče jednoho spojení. `exchange` = přijatá výměna (zóna, stát …), `zone` = CQ zóna uložená v logu.
    public func hits(call: String, exchange: String?, zone: Int? = nil) -> [MultiplierHit] {
        let c = QSORecord.normalizeCall(call)
        guard !c.isEmpty, rule.hasMultipliers else { return [] }
        let dx = lookup(c, false)
        var out: [MultiplierHit] = []
        for comp in rule.components {
            switch comp.kind {
            case .dxcc:
                let ci = rule.waeList ? lookup(c, true) : dx
                if let ci, !rule.excludedCountries.contains(ci.primaryPrefix) { out.append(.init(.dxcc, ci.primaryPrefix)) }
            case .cqZone:
                if let z = Multipliers.zone(in: exchange) ?? zone ?? dx?.cqZone, (1...40).contains(z) {
                    out.append(.init(.cqZone, String(z)))
                }
            case .wpxPrefix:
                if let p = WPX.prefix(c) { out.append(.init(.wpxPrefix, p)) }
            case .usState:
                if dx == nil || dx?.primaryPrefix == "K", let s = Multipliers.state(in: exchange) { out.append(.init(.usState, s)) }
            case .veProvince:
                if dx == nil || dx?.primaryPrefix == "VE", let s = Multipliers.province(in: exchange) {
                    out.append(.init(.veProvince, s))
                }
            case .callArea:
                if let a = callArea(c, country: dx) { out.append(.init(.callArea, a)) }
            case .waeCountry:
                if let a = callArea(c, country: dx) { out.append(.init(.waeCountry, a)) }
                else if let ci = lookup(c, true) { out.append(.init(.waeCountry, ci.primaryPrefix)) }
            case .continent:
                if let k = dx?.continent, !k.isEmpty { out.append(.init(.continent, k)) }
            case .okStation:
                if dx?.primaryPrefix == "OK" { out.append(.init(.okStation, QSORecord.baseCall(c))) }
            }
        }
        return out
    }

    /// Číselná oblast (W1, VE3, JA0, RA9 …) pro země s oblastmi; číslice = poslední číslice prefixu WPX
    /// (portable prefix bez číslice = 0, /číslice mění oblast).
    func callArea(_ call: String, country: CountryInfo?) -> String? {
        guard let country, rule.callAreaCountries.contains(country.primaryPrefix),
              let p = WPX.prefix(call), let d = p.last, d.isNumber else { return nil }
        let name: String
        switch country.primaryPrefix {
        case "K": name = "W"
        case "UA9": name = "RA"
        default: name = country.primaryPrefix
        }
        return name + String(d)
    }

    public func hits(_ r: QSORecord) -> [MultiplierHit] { hits(call: r.call, exchange: r.exchangeRcvd, zone: r.cqZone) }

    /// Násobiče ze spojení od začátku závodu.
    public func tally(records: [QSORecord], since: Date) -> MultiplierTally {
        var t = MultiplierTally(rule: rule)
        guard rule.hasMultipliers else { return t }
        for r in records.sorted(by: { $0.timeOn < $1.timeOn }) where r.timeOn >= since {
            t.add(hits(r), band: r.band)
        }
        return t
    }
}

/// Pomocné tabulky a rozbor výměny.
public enum Multipliers {
    /// 48 kontinentálních států USA + DC (KH6 a KL7 jsou země DXCC, ne státy).
    public static let usStates = ["AL", "AR", "AZ", "CA", "CO", "CT", "DC", "DE", "FL", "GA", "IA", "ID", "IL", "IN", "KS", "KY",
                                  "LA", "MA", "MD", "ME", "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NE", "NH", "NJ", "NM", "NV",
                                  "NY", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VA", "VT", "WA", "WI", "WV", "WY"]
    /// 14 kanadských oblastí (CQ WW RTTY; ARRL: provincie a teritoria + Labrador).
    public static let veProvinces = ["AB", "BC", "LB", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT"]
    static let aliases: [String: String] = ["NWT": "NT", "NF": "NL", "NFL": "NL", "NFLD": "NL", "PEI": "PE", "PQ": "QC",
                                            "YK": "YT", "LAB": "LB"]
    private static let stateSet = Set(usStates), provinceSet = Set(veProvinces)

    static func tokens(_ s: String?) -> [String] {
        (s ?? "").uppercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    /// CQ zóna z výměny („14“, „05 NY“, „599 14“ → první číslo 1–40 po vynechání RST 5NN).
    static func zone(in exchange: String?) -> Int? {
        for t in tokens(exchange) where t.allSatisfy(\.isNumber) && t.count <= 2 {
            if let z = Int(t), (1...40).contains(z) { return z }
        }
        return nil
    }
    static func state(in exchange: String?) -> String? {
        tokens(exchange).lazy.map { aliases[$0] ?? $0 }.first { stateSet.contains($0) }
    }
    static func province(in exchange: String?) -> String? {
        tokens(exchange).lazy.map { aliases[$0] ?? $0 }.first { provinceSet.contains($0) }
    }

    static let bandOrder = ["2190m", "630m", "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m",
                            "6m", "4m", "2m", "1.25m", "70cm"]
    public static func sortBands(_ b: [String]) -> [String] {
        b.sorted { (bandOrder.firstIndex(of: $0) ?? 99, $0) < (bandOrder.firstIndex(of: $1) ?? 99, $1) }
    }
    /// Pásma závodu (RTTY závody na KV bez WARC) – řádky mřížky i bez spojení.
    public static let contestBands = ["80m", "40m", "20m", "15m", "10m"]
}

/// Prefix podle pravidel CQ WPX.
///
/// Prefix = písmena a číslice první části značky až po číslici před sufixem (N8, WD8, OE25, LY1000).
/// Portable designátor se stává prefixem; designátor bez číslice dostane 0 (PA/N8BJQ = PA0),
/// značka bez číslice dostane 0 za první dvě písmena (XEFTJW = XE0). /P, /M, /MM, /AM, /QRP, /A, /E, /J
/// se ignorují. /číslice mění číslo prefixu (W1ABC/3 = W3) – v pravidlech neuvedeno, obvyklá praxe.
public enum WPX {
    static let ignored: Set<String> = ["P", "M", "MM", "AM", "QRP", "QRPP", "A", "E", "J", "LH", "R", "B", "N", "T", "X"]

    public static func prefix(_ call: String) -> String? {
        var parts = QSORecord.normalizeCall(call).split(separator: "/").map(String.init)
            .filter { !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } }
        guard !parts.isEmpty else { return nil }
        var digit: Character?
        while parts.count > 1, let last = parts.last {
            if ignored.contains(last) { parts.removeLast(); continue }
            if last.count == 1, let d = last.first, d.isNumber { digit = digit ?? d; parts.removeLast(); continue }
            break
        }
        var p: String
        if parts.count == 1 {
            p = callPrefix(parts[0])
        } else {
            p = prefixOfDesignator(designator(parts))
        }
        if let digit {
            while let l = p.last, l.isNumber { p.removeLast() }
            p.append(digit)
        }
        return p.isEmpty ? nil : p
    }

    /// Portable designátor: část, která není celá značka (končí číslicí nebo nemá číslici); jinak nejkratší.
    static func designator(_ parts: [String]) -> String {
        let looksLikeCall: (String) -> Bool = { s in s.contains(where: \.isNumber) && s.last?.isLetter == true }
        let cands = parts.filter { !looksLikeCall($0) }
        let pool = cands.isEmpty || cands.count == parts.count ? parts : cands
        return pool.enumerated().min { ($0.element.count, $0.offset) < ($1.element.count, $1.offset) }!.element
    }

    static func prefixOfDesignator(_ d: String) -> String {
        if d.last?.isNumber == true { return d }                            // KH6, VE3, 3D2
        if !d.contains(where: \.isNumber) { return String(d.prefix(2)) + "0" }   // PA → PA0
        return callPrefix(d)                                                // VP2E → VP2
    }

    /// Prefix celé značky: vše až po poslední číslici, za kterou následuje písmeno.
    static func callPrefix(_ c: String) -> String {
        let a = Array(c)
        var end: Int?
        for i in a.indices.dropLast() where a[i].isNumber && a[i + 1].isLetter { end = i }
        if let end { return String(a[...end]) }
        if !a.contains(where: \.isNumber) { return String(c.prefix(2)) + "0" }       // XEFTJW → XE0
        return c                                                                     // jen číslice na konci
    }
}
