// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import DXCC
import Localization
import QSOLog
import Settings

// Bodování a skóre závodů. Pravidla a zdroje: docs/rulings.md, „Bodování a skóre“.

/// Jak se z bodů a násobičů spočítá výsledné skóre.
public enum ScoreFormula: Sendable, Equatable {
    /// Body × násobiče (CQ WW, WPX, ARRL RU, SARTG, JARTS, OK DX).
    case pointsTimesMultipliers
    /// Body × násobiče po pásmech × kontinenty (BARTG HF).
    case pointsTimesMultipliersTimesContinents
    /// (QSO + QTC) × násobiče s váhou pásem (WAE).
    case qsoPlusQTCTimesWeightedMultipliers
    /// Součet bodů (Makrothen – bez násobičů).
    case pointsSum
}

/// Vztah protistanice k vlastní stanici (pro body podle země a kontinentu).
public enum ScoreRelation: Sendable, Equatable {
    case sameCountry, sameContinent, otherContinent
}

/// Pravidla bodování jednoho závodu.
public struct ScoreRule: Sendable, Equatable {
    public var preset: ContestPreset
    public var formula: ScoreFormula
    /// Pravidlo ověřené v oficiálních pravidlech závodu (zdroj v `source`).
    public var verified: Bool
    public var source: String

    /// Pásma s vyšším bodováním (WPX, OK DX: 80 a 40 m).
    static let lowBands: Set<String> = ["80m", "40m"]

    /// Pravidla pro závodní nastavení; nil = mimo závod nebo vlastní (nerozpoznaný) závod.
    public static func rule(for contest: ContestSettings) -> ScoreRule? {
        guard contest.enabled, let p = contest.selectedPreset else { return nil }
        return rule(for: p)
    }

    public static func rule(for p: ContestPreset) -> ScoreRule {
        let formula: ScoreFormula
        switch p {
        case .bartgHF: formula = .pointsTimesMultipliersTimesContinents
        case .makrothen: formula = .pointsSum
        case .waeRTTY: formula = .qsoPlusQTCTimesWeightedMultipliers
        case .arrlRoundup, .cqwpxRTTY, .sartgRTTY, .cqwwRTTY, .jartsRTTY, .okDXRTTY: formula = .pointsTimesMultipliers
        }
        return ScoreRule(preset: p, formula: formula, verified: true, source: MultiplierRule.rule(for: p).source)
    }

    /// Popis bodování pro okno Skóre (překládá se při zobrazení – sleduje přepnutí jazyka).
    public var pointsNote: String {
        switch preset {
        case .arrlRoundup: L("1 bod za spojení; stejnou stanici jen jednou na pásmu. Skóre = body × násobiče.")
        case .cqwpxRTTY: L("Jiný kontinent 3 body (80 a 40 m: 6), stejný kontinent a jiná země 2 (4), stejná země 1 (2). Skóre = body × prefixy.")
        case .bartgHF: L("1 bod za spojení. Skóre = body × násobiče (země a oblasti po pásmech) × kontinenty.")
        case .sartgRTTY: L("Vlastní země 5 bodů, jiná země na vlastním kontinentu 10, jiný kontinent 15. Skóre = body × násobiče.")
        case .cqwwRTTY: L("Jiný kontinent 3 body, stejný kontinent a jiná země 2, stejná země 1. Skóre = body × (zóny + země + W/VE QTH).")
        case .makrothen: L("Body = vzdálenost středů čtverců lokátorů v km (zaokrouhleno dolů) × váha pásma (80 m × 2, 40 m × 1,5, ostatní × 1, znovu dolů); stejný čtverec 100 bodů bez váhy. Skóre = součet bodů.")
        case .jartsRTTY: L("Stejný kontinent (i vlastní země) 2 body, jiný kontinent 3. Skóre = body × násobiče.")
        case .waeRTTY: L("1 bod za spojení a 1 za každé odeslané i přijaté QTC. Skóre = (QSO + QTC) × násobiče s váhou pásem.")
        case .okDXRTTY: L("20, 15 a 10 m: vlastní kontinent 1 bod, jiný kontinent 2; 80 a 40 m: 3 a 6. Skóre = body × násobiče.")
        }
    }

    /// Neověřené nebo nejednoznačné části (prázdné = vše ověřeno); překládá se při zobrazení.
    public var unverifiedNote: String {
        switch preset {
        case .cqwpxRTTY, .sartgRTTY, .cqwwRTTY, .okDXRTTY:
            L("Spojení se značkou bez známé země/kontinentu dostane nejnižší bodovou hodnotu.")
        case .jartsRTTY:
            L("Pravidla píší „body na každém pásmu × násobiče na každém pásmu“ – počítá se součet bodů × součet násobičů (obvyklý výklad).")
        case .arrlRoundup, .bartgHF, .makrothen, .waeRTTY: ""
        }
    }

    /// Body závisí na vlastní zemi/kontinentu (nebo násobiče na vlastní zemi) – bez ní je výsledek chybný.
    var needsOwnCountry: Bool { preset != .makrothen }

    /// Body za spojení podle vztahu k vlastní stanici a pásma (Makrothen se počítá zvlášť); nil vztah = nejnižší hodnota.
    public func points(relation: ScoreRelation?, band: String?) -> Int {
        let low = band.map(Self.lowBands.contains) ?? false
        let v: (Int, Int, Int)                         // stejná země, stejný kontinent, jiný kontinent
        switch preset {
        case .arrlRoundup, .bartgHF, .waeRTTY, .makrothen: return 1
        case .cqwpxRTTY: v = low ? (2, 4, 6) : (1, 2, 3)
        case .cqwwRTTY: v = (1, 2, 3)
        case .sartgRTTY: v = (5, 10, 15)
        case .jartsRTTY: v = (2, 2, 3)
        case .okDXRTTY: v = low ? (3, 3, 6) : (1, 1, 2)
        }
        switch relation {
        case .sameCountry, nil: return v.0
        case .sameContinent: return v.1
        case .otherContinent: return v.2
        }
    }

    /// Váha pásma Makrothenu.
    static func makrothenFactor(_ band: String?) -> Double {
        switch band {
        case "80m": return 2
        case "40m": return 1.5
        default: return 1
        }
    }
}

/// Součty jednoho pásma.
public struct BandScore: Sendable, Equatable {
    /// Spojení včetně duplicit.
    public var qsos = 0
    public var dupes = 0
    public var points = 0
    /// QTC (WAE) podle kmitočtu série.
    public var qtc = 0
    public init(qsos: Int = 0, dupes: Int = 0, points: Int = 0, qtc: Int = 0) {
        self.qsos = qsos; self.dupes = dupes; self.points = points; self.qtc = qtc
    }
}

/// Průběžné skóre závodu: po pásmech QSO, duplicity, body, QTC; násobiče; výsledné skóre.
public struct ScoreTally: Sendable, Equatable {
    /// Pásmo neznámé (spojení bez kmitočtu).
    public static let unknownBand = "?"
    public let rule: ScoreRule
    public private(set) var multipliers: MultiplierTally
    public private(set) var perBand: [String: BandScore] = [:]
    /// Okno závodu zafixované při úplném výpočtu: počítají se spojení a QTC v [since, until); until nil = bez konce.
    /// Přírůstek (`ScoreCalculator.add`) používá totéž okno – výsledek je stejný jako úplný přepočet.
    public let since: Date
    public let until: Date?
    /// Vlastní země neznámá (chybí značka stanice nebo cty.dat) – body podle země/kontinentu nejsou správné.
    public internal(set) var ownCountryUnknown = false
    /// Makrothen: chybí vlastní lokátor – všechna spojení mají 0 bodů.
    public internal(set) var ownLocatorMissing = false
    /// Odpracované stanice (`DupeCheck.key`) pro duplicity.
    private var worked: Set<String> = []

    public init(rule: ScoreRule, multiplierRule: MultiplierRule, since: Date = .distantPast, until: Date? = nil) {
        self.rule = rule; multipliers = MultiplierTally(rule: multiplierRule); self.since = since; self.until = until
    }

    /// Spojení/QTC v čase `t` patří do závodu.
    public func inWindow(_ t: Date) -> Bool { t >= since && (until.map { t < $0 } ?? true) }

    public func band(_ b: String) -> BandScore { perBand[b] ?? BandScore() }
    /// Pásma se spojením nebo QTC, od nejdelšího; neznámé pásmo na konci.
    public var bands: [String] { Multipliers.sortBands(Array(perBand.keys)) }

    public var qsos: Int { perBand.values.reduce(0) { $0 + $1.qsos } }
    public var dupes: Int { perBand.values.reduce(0) { $0 + $1.dupes } }
    public var points: Int { perBand.values.reduce(0) { $0 + $1.points } }
    public var qtc: Int { perBand.values.reduce(0) { $0 + $1.qtc } }
    /// Násobiče po pásmech (bez „jednou za závod“) – BARTG: země a oblasti.
    public var bandMultipliers: Int { multipliers.total - multipliers.onceCount }
    /// Kontinenty (BARTG).
    public var continents: Int { multipliers.worked(.continent, band: nil).count }
    /// Násobiče v řádku Celkem tabulky okna Skóre: u BARTG jen po pásmech (kontinenty jsou ve vzorci zvlášť).
    public var tableMultiplierTotal: Int {
        rule.formula == .pointsTimesMultipliersTimesContinents ? bandMultipliers : multipliers.total
    }
    /// Řádek „Za závod“ v tabulce: násobiče jednou za závod, které jsou součástí součtu (u BARTG ne – kontinenty zvlášť).
    public var showsOnceMultiplierRow: Bool {
        rule.formula != .pointsTimesMultipliersTimesContinents && multipliers.rule.components.contains { !$0.perBand }
    }

    /// Násobitel ve vzorci skóre.
    public var multiplierFactor: Int {
        switch rule.formula {
        case .pointsTimesMultipliers: return multipliers.total
        case .pointsTimesMultipliersTimesContinents: return bandMultipliers * continents
        case .qsoPlusQTCTimesWeightedMultipliers: return multipliers.weightedTotal
        case .pointsSum: return 1
        }
    }

    public var score: Int {
        switch rule.formula {
        case .qsoPlusQTCTimesWeightedMultipliers: return (points + qtc) * multiplierFactor
        case .pointsSum: return points
        default: return points * multiplierFactor
        }
    }

    /// Vzorec výsledného skóre s čísly („Body 123 × násobiče 45 = 5 535“).
    public var formulaText: String {
        let f = Self.format
        switch rule.formula {
        case .pointsTimesMultipliers:
            return L("Body %@ × násobiče %@ = %@", f(points), f(multipliers.total), f(score))
        case .pointsTimesMultipliersTimesContinents:
            return L("Body %@ × násobiče %@ × kontinenty %@ = %@", f(points), f(bandMultipliers), f(continents), f(score))
        case .qsoPlusQTCTimesWeightedMultipliers:
            return L("(QSO %@ + QTC %@) × násobiče s váhou pásem %@ = %@", f(points), f(qtc), f(multipliers.weightedTotal), f(score))
        case .pointsSum:
            return L("Součet bodů = %@", f(score))
        }
    }

    /// Celé číslo s mezerou (nezlomitelnou) po tisících: 5 535.
    public static func format(_ n: Int) -> String {
        let s = String(n.magnitude)
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0, (s.count - i) % 3 == 0 { out.append("\u{00A0}") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + out
    }

    mutating func add(record r: QSORecord, points: Int, hits: [MultiplierHit]) {
        let b = r.band ?? Self.unknownBand
        let key = DupeCheck.key(call: r.call, band: b, mode: r.mode, perMode: DupeCheck.perMode(preset: rule.preset))
        var s = perBand[b] ?? BandScore()
        s.qsos += 1
        if worked.insert(key).inserted { s.points += points } else { s.dupes += 1 }
        perBand[b] = s
        // závod bez násobičů (Makrothen): tally násobičů zůstává prázdný jako dřív (okno Násobiče: 0 spojení)
        if multipliers.rule.hasMultipliers { multipliers.add(hits, band: r.band) }
    }

    /// QTC série v okně závodu (WAE); ostatní závody QTC nepočítají.
    public mutating func setQTC(_ series: [QTCSeries]) {
        for k in perBand.keys { perBand[k]?.qtc = 0 }
        guard rule.formula == .qsoPlusQTCTimesWeightedMultipliers else { return }
        for s in series where inWindow(s.time) && s.count > 0 {
            perBand[Bands.band(forHz: s.frequency) ?? Self.unknownBand, default: BandScore()].qtc += s.count
        }
    }
}

/// Výpočet bodů a skóre podle pravidel závodu.
public struct ScoreCalculator: Sendable {
    public let rule: ScoreRule
    public let multipliers: MultiplierCalculator
    let lookup: @Sendable (String, Bool) -> CountryInfo?
    /// Vlastní země (pro body podle země a kontinentu).
    let own: CountryInfo?
    /// Vlastní čtverec lokátoru (4 znaky) pro Makrothen.
    let ownSquare: String?

    public init(rule: ScoreRule, multiplierRule: MultiplierRule, ownCall: String, ownLocator: String,
                lookup: @escaping @Sendable (String, Bool) -> CountryInfo?) {
        self.rule = rule; self.lookup = lookup
        multipliers = MultiplierCalculator(rule: multiplierRule, lookup: lookup)
        own = lookup(QSORecord.normalizeCall(ownCall), multiplierRule.waeList)
        ownSquare = Self.square(ownLocator)
    }

    /// Kalkulátor pro předvolbu; vlastní země se určí z vlastní značky.
    public init(preset: ContestPreset, ownCall: String, ownLocator: String, countries: CountryDB?) {
        let lookup: @Sendable (String, Bool) -> CountryInfo? = { call, wae in countries?.lookup(call, wae: wae) }
        let own = countries?.lookup(ownCall)?.primaryPrefix
        self.init(rule: .rule(for: preset), multiplierRule: .rule(for: preset, ownCountry: own),
                  ownCall: ownCall, ownLocator: ownLocator, lookup: lookup)
    }

    /// Vztah protistanice k vlastní stanici; nil = země jedné ze stanic neznámá.
    public func relation(_ call: String) -> ScoreRelation? {
        guard let a = own, let b = lookup(QSORecord.normalizeCall(call), multipliers.rule.waeList) else { return nil }
        if a.primaryPrefix == b.primaryPrefix { return .sameCountry }
        return a.continent == b.continent ? .sameContinent : .otherContinent
    }

    /// Body za spojení (bez ohledu na duplicitu).
    public func points(_ r: QSORecord) -> Int {
        if rule.preset == .makrothen {
            guard let own = ownSquare, let dx = Self.square(in: r.exchangeRcvd) ?? Self.square(r.grid ?? "") else { return 0 }
            if own == dx { return 100 }
            guard let km = Self.makrothenKm(own, dx) else { return 0 }
            return Int((Double(km) * ScoreRule.makrothenFactor(r.band)).rounded(.down))
        }
        return rule.points(relation: relation(r.call), band: r.band)
    }

    /// Úplný výpočet ze spojení v okně závodu [since, until) (a QTC série u WAE); okno se v tally zafixuje.
    public func tally(records: [QSORecord], qtc: [QTCSeries], since: Date, until: Date? = nil) -> ScoreTally {
        var t = ScoreTally(rule: rule, multiplierRule: multipliers.rule, since: since, until: until)
        t.ownCountryUnknown = rule.needsOwnCountry && own == nil
        t.ownLocatorMissing = rule.preset == .makrothen && ownSquare == nil
        for r in records.sorted(by: { $0.timeOn < $1.timeOn }) { add(r, to: &t) }
        t.setQTC(qtc)
        return t
    }

    /// Přidá jedno zalogované spojení (bez přepočtu celého logu) – v okně závodu zafixovaném v `t`.
    public func add(_ r: QSORecord, to t: inout ScoreTally) {
        guard t.inWindow(r.timeOn) else { return }
        t.add(record: r, points: points(r), hits: multipliers.rule.hasMultipliers ? multipliers.hits(r) : [])
    }

    // MARK: Makrothen

    /// Poloměr Země podle pravidel Makrothenu (km).
    static let makrothenRadiusKm = 6378.16

    /// Vzdálenost středů čtverců (4 znaky) v celých km (dolů) podle pravidel Makrothenu.
    public static func makrothenKm(_ a: String, _ b: String) -> Int? {
        guard let sa = square(a), let sb = square(b), let p = Geo.maidenhead(sa), let q = Geo.maidenhead(sb) else { return nil }
        let km = Geo.distanceKm(p, q) / Geo.earthRadiusKm * makrothenRadiusKm
        return Int(km.rounded(.down))
    }

    /// Čtverec lokátoru (první 4 znaky platného lokátoru 4/6/8 znaků).
    static func square(_ locator: String) -> String? {
        let l = locator.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Geo.maidenhead(l) != nil else { return nil }
        return String(l.prefix(4))
    }

    /// První platný lokátor ve výměně („599 JO70“ → JO70).
    static func square(in exchange: String?) -> String? {
        (exchange ?? "").split { !$0.isLetter && !$0.isNumber }.lazy.compactMap { square(String($0)) }.first
    }
}
