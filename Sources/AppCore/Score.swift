// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import DXCC
import Localization
import QSOLog
import Settings

// Contest scoring and score. Rules and sources: docs/rulings.md, "Scoring and score".

/// How the resulting score is computed from points and multipliers.
public enum ScoreFormula: Sendable, Equatable {
    /// Points × multipliers (CQ WW, WPX, ARRL RU, SARTG, JARTS, OK DX).
    case pointsTimesMultipliers
    /// Points × per-band multipliers × continents (BARTG HF).
    case pointsTimesMultipliersTimesContinents
    /// (QSO + QTC) × band-weighted multipliers (WAE).
    case qsoPlusQTCTimesWeightedMultipliers
    /// Sum of points (Makrothen – without multipliers).
    case pointsSum
    /// QSOs × points × multipliers (VOLTA).
    case qsosTimesPointsTimesMultipliers
}

/// Everything the scoring of one QSO may need (the relation, the band, both countries and both exchanges).
public struct QSOPointsInput: Sendable {
    public var relation: ScoreRelation?
    public var band: String?
    public var call = ""
    public var own: CountryInfo?, dx: CountryInfo?
    public var exchangeSent: String?, exchangeRcvd: String?
    /// My own CQ zone (VOLTA).
    public var ownZone: Int?
    /// The same call area of JA/W/VE/VK/ZL (VOLTA: 0 points).
    public var sameCallArea = false
    /// The year of the QSO (Rookie Roundup: a rookie = licensed in the last 3 years).
    public var year: Int?
    public init(relation: ScoreRelation? = nil, band: String? = nil) { self.relation = relation; self.band = band }
}

/// Relation of the other station to my own station (for points by country and continent).
public enum ScoreRelation: Sendable, Equatable {
    case sameCountry, sameContinent, otherContinent
}

/// Scoring rules of a single contest.
public struct ScoreRule: Sendable, Equatable {
    public var preset: ContestPreset
    public var formula: ScoreFormula
    /// A rule verified in the official contest rules (the source is in `source`).
    public var verified: Bool
    public var source: String

    /// Bands with higher scoring (WPX, OK DX: 80 and 40 m).
    static let lowBands: Set<String> = ["80m", "40m"]

    /// Rules for the contest settings; nil = outside a contest or a custom (unrecognized) contest.
    public static func rule(for contest: ContestSettings) -> ScoreRule? {
        guard contest.enabled, let p = contest.selectedPreset else { return nil }
        return rule(for: p)
    }

    public static func rule(for p: ContestPreset) -> ScoreRule {
        let formula: ScoreFormula
        switch p {
        case .bartgHF, .bartgSprint, .bartgSprint75, .spDX: formula = .pointsTimesMultipliersTimesContinents
        case .makrothen: formula = .pointsSum
        case .waeRTTY: formula = .qsoPlusQTCTimesWeightedMultipliers
        case .voltaRTTY: formula = .qsosTimesPointsTimesMultipliers
        default: formula = .pointsTimesMultipliers
        }
        return ScoreRule(preset: p, formula: formula, verified: true, source: MultiplierRule.rule(for: p).source)
    }

    /// Description of the scoring for the Score window (translated at display time – follows a language switch).
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
        case .sartgNewYear, .igryWW, .darcSprint: L("1 bod za spojení. Skóre = body × násobiče.")
        case .bartgSprint, .bartgSprint75: L("1 bod za spojení. Skóre = body × (země + oblasti) × kontinenty.")
        case .proDigi: L("Vlastní země 1 bod, jiná země 2; nečlen se členem +2, člen se členem +6. Skóre = body × prefixy.")
        case .mexicoRTTY: L("Stejná země 2 body, jiná země 3, spojení se stanicí XE 4. Skóre = body × násobiče.")
        case .naqpRTTY, .naSprintRTTY: L("1 bod za spojení; aspoň jedna stanice musí být ze Severní Ameriky (DX–DX 0). Skóre = body × násobiče.")
        case .ybDX: L("Vlastní země 1 bod, stejný kontinent 2, jiný kontinent 3, stanice YB 10 (pro YB: Oceánie 5, jinde 10). Skóre = body × (prefixy + země).")
        case .eaRTTY: L("Stanice EA: s EA 2 body, s ostatními 1. Ostatní: s EA 3 body, s ostatními 1. Skóre = body × násobiče.")
        case .spDX: L("Stejná země 2 body, stejný kontinent 5, jiný kontinent 10; UA a EW 0. Skóre = body × (země + powiaty) × kontinenty.")
        case .voltaRTTY: L("Body podle tabulky CQ zón (vlastní × protistanice), jiný kontinent na 80 a 10 m dvojnásob; vlastní země (u JA/W/VE/VK/ZL oblast) 0. Skóre = QSO × body × násobiče.")
        case .rookieRoundup: L("Spojení s nováčkem (rok licence v posledních 3 letech) 2 body, jinak 1. Skóre = body × násobiče.")
        case .russianRTTY: L("Ruská stanice 10 bodů, vlastní země 2, stejný kontinent 3, jiný kontinent 5, /MM 5 (pro RU stanice: Rusko na vlastním kontinentu 2, jinak 5). Skóre = body × (oblasti + země).")
        case .russianDigi: L("Vlastní země 1 bod, jiná země 3, jiný kontinent a /QRP 5; na 160, 80 a 40 m dvojnásob. Skóre = body × (země + oblasti).")
        case .urcDX: L("Stejné teritorium 1 bod; stejný kontinent 2 (10 a 80 m: 3, 160 m: 5); jiný kontinent 4 (10 m: 5, 80 m: 6, 160 m: 10); MMS 3. Skóre = body × teritoria.")
        case .trcDigi: L("Stejný kontinent 1 bod, jiný kontinent 2, stanice TRC 10 (člen TRC s členem 1). Skóre = body × (země + země členů).")
        case .wrt: L("1 bod za spojení. Skóre = body × různé značky.")
        }
    }

    /// Unverified or ambiguous parts (empty = everything verified); translated at display time.
    public var unverifiedNote: String {
        switch preset {
        case .cqwpxRTTY, .sartgRTTY, .cqwwRTTY, .okDXRTTY, .proDigi, .mexicoRTTY, .ybDX, .spDX, .russianRTTY, .russianDigi, .trcDigi:
            L("Spojení se značkou bez známé země/kontinentu dostane nejnižší bodovou hodnotu.")
        case .jartsRTTY:
            L("Pravidla píší „body na každém pásmu × násobiče na každém pásmu“ – počítá se součet bodů × součet násobičů (obvyklý výklad).")
        case .urcDX:
            L("Kontinent podle DXCC; vlastní teritorium = kód v mé odesílané výměně.")
        case .voltaRTTY:
            L("Zóna protistanice z výměny, jinak podle DXCC; kontinent podle DXCC.")
        case .arrlRoundup, .bartgHF, .makrothen, .waeRTTY, .sartgNewYear, .igryWW, .darcSprint, .bartgSprint, .bartgSprint75,
             .naqpRTTY, .naSprintRTTY, .eaRTTY, .rookieRoundup, .wrt: ""
        }
    }

    /// The points depend on my own country/continent (or the multipliers on my own country) – without it the result is wrong.
    var needsOwnCountry: Bool { ![.makrothen, .sartgNewYear, .igryWW, .darcSprint, .bartgSprint, .bartgSprint75, .wrt].contains(preset) }

    /// Points for a QSO by the relation to my own station and the band (Makrothen and the contests with exchange-dependent
    /// points separately – `points(_:)`); nil relation = the lowest value.
    public func points(relation: ScoreRelation?, band: String?) -> Int {
        points(QSOPointsInput(relation: relation, band: band))
    }

    static let russia: Set<String> = ["UA", "UA2", "UA9", "R1FJ"]
    static let northAmericaExtra: Set<String> = ["KH6"]

    /// Points for a QSO from everything the rules need (relation, band, countries, exchanges).
    public func points(_ q: QSOPointsInput) -> Int {
        let low = q.band.map(Self.lowBands.contains) ?? false
        let dxPrefix = q.dx?.primaryPrefix, ownPrefix = q.own?.primaryPrefix
        let v: (Int, Int, Int)                         // same country, same continent, other continent
        switch preset {
        case .arrlRoundup, .bartgHF, .waeRTTY, .makrothen, .sartgNewYear, .igryWW, .darcSprint, .bartgSprint, .bartgSprint75, .wrt:
            return 1
        case .cqwpxRTTY: v = low ? (2, 4, 6) : (1, 2, 3)
        case .cqwwRTTY: v = (1, 2, 3)
        case .sartgRTTY: v = (5, 10, 15)
        case .jartsRTTY: v = (2, 2, 3)
        case .okDXRTTY: v = low ? (3, 3, 6) : (1, 1, 2)
        case .proDigi:
            let base = q.relation == .sameCountry || q.relation == nil ? 1 : 2
            let dxM = Multipliers.hasMark("M", in: q.exchangeRcvd), myM = Multipliers.hasMark("M", in: q.exchangeSent)
            return base + (dxM ? (myM ? 6 : 2) : 0)
        case .mexicoRTTY:
            if dxPrefix == "XE" { return 4 }
            v = (2, 3, 3)
        case .naqpRTTY, .naSprintRTTY:
            func na(_ c: CountryInfo?) -> Bool { c.map { $0.continent == "NA" || Self.northAmericaExtra.contains($0.primaryPrefix) } ?? false }
            return q.own == nil || q.dx == nil || na(q.own) || na(q.dx) ? 1 : 0
        case .ybDX:
            if ownPrefix == "YB" {
                if dxPrefix == "YB" { return 0 }
                return q.relation == .otherContinent ? 10 : 5
            }
            if dxPrefix == "YB" { return 10 }
            v = (1, 2, 3)
        case .eaRTTY:
            let ea: Set<String> = ["EA", "EA6", "EA8", "EA9"]
            let dxEA = dxPrefix.map(ea.contains) ?? false
            if ownPrefix.map(ea.contains) ?? false { return dxEA ? 2 : 1 }
            return dxEA ? 3 : 1
        case .spDX:
            if let d = dxPrefix, ["UA", "UA2", "UA9", "EU"].contains(d) { return 0 }
            v = (2, 5, 10)
        case .voltaRTTY:
            if q.sameCallArea || q.relation == .sameCountry { return 0 }
            guard let a = q.ownZone, let b = Multipliers.zone(in: q.exchangeRcvd) ?? q.dx?.cqZone,
                  (1...40).contains(a), (1...40).contains(b) else { return 0 }
            let base = ContestCodes.voltaZonePoints[a - 1][b - 1]
            return q.relation == .otherContinent && (q.band == "80m" || q.band == "10m") ? base * 2 : base
        case .rookieRoundup:
            guard let y = q.year, let yy = Multipliers.tokens(q.exchangeRcvd).compactMap({ $0.count == 2 ? Int($0) : nil }).first
            else { return 1 }
            return (0...3).contains((y - yy + 100) % 100) ? 2 : 1
        case .russianRTTY:
            if QSORecord.normalizeCall(q.call).hasSuffix("/MM") { return 5 }
            let dxRU = dxPrefix.map(Self.russia.contains) ?? false
            if ownPrefix.map(Self.russia.contains) ?? false {
                if dxRU { return q.own?.continent == q.dx?.continent ? 2 : 5 }
                return q.relation == .otherContinent ? 5 : 3
            }
            if dxRU { return 10 }
            v = (2, 3, 5)
        case .russianDigi:
            let call = QSORecord.normalizeCall(q.call)
            let base: Int
            if call.hasSuffix("/QRP") { base = 5 }
            else {
                switch q.relation {
                case .sameCountry, nil: base = 1
                case .sameContinent: base = 3
                case .otherContinent: base = 5
                }
            }
            return q.band == "160m" || low ? base * 2 : base
        case .urcDX:
            let words = Multipliers.tokens(q.exchangeRcvd)
            if words.contains("MMS") || QSORecord.normalizeCall(q.call).hasSuffix("/MM") { return 3 }
            let mine = Multipliers.tokens(q.exchangeSent).first { ContestCodes.urcTerritorySet.contains($0) }
            let his = words.first { ContestCodes.urcTerritorySet.contains($0) }
            if let mine, mine == his { return 1 }
            let b = q.band ?? ""
            if q.relation == .otherContinent {
                return ["160m": 10, "80m": 6, "10m": 5][b] ?? 4
            }
            return ["160m": 5, "80m": 3, "10m": 3][b] ?? 2
        case .trcDigi:
            let dxM = Multipliers.hasMark("TRC", in: q.exchangeRcvd), myM = Multipliers.hasMark("TRC", in: q.exchangeSent)
            if dxM { return myM ? 1 : 10 }
            return q.relation == .otherContinent ? 2 : 1
        }
        switch q.relation {
        case .sameCountry, nil: return v.0
        case .sameContinent: return v.1
        case .otherContinent: return v.2
        }
    }

    /// Makrothen band weight.
    static func makrothenFactor(_ band: String?) -> Double {
        switch band {
        case "80m": return 2
        case "40m": return 1.5
        default: return 1
        }
    }
}

/// Totals of a single band.
public struct BandScore: Sendable, Equatable {
    /// QSOs including dupes.
    public var qsos = 0
    public var dupes = 0
    public var points = 0
    /// QTC (WAE) by the frequency of the series.
    public var qtc = 0
    public init(qsos: Int = 0, dupes: Int = 0, points: Int = 0, qtc: Int = 0) {
        self.qsos = qsos; self.dupes = dupes; self.points = points; self.qtc = qtc
    }
}

/// Running contest score: QSOs, dupes, points, QTC per band; multipliers; the resulting score.
public struct ScoreTally: Sendable, Equatable {
    /// Band unknown (a QSO without a frequency).
    public static let unknownBand = "?"
    public let rule: ScoreRule
    public private(set) var multipliers: MultiplierTally
    public private(set) var perBand: [String: BandScore] = [:]
    /// The contest window fixed at the full computation: QSOs and QTC in [since, until) are counted; until nil = no end.
    /// The incremental path (`ScoreCalculator.add`) uses the same window – the result is the same as a full recomputation.
    public let since: Date
    public let until: Date?
    /// My own country is unknown (the station call or cty.dat is missing) – the points by country/continent are not correct.
    public internal(set) var ownCountryUnknown = false
    /// Makrothen: my own locator is missing – all QSOs have 0 points.
    public internal(set) var ownLocatorMissing = false
    /// Worked stations (`DupeCheck.key`) for dupes.
    private var worked: Set<String> = []

    public init(rule: ScoreRule, multiplierRule: MultiplierRule, since: Date = .distantPast, until: Date? = nil) {
        self.rule = rule; multipliers = MultiplierTally(rule: multiplierRule); self.since = since; self.until = until
    }

    /// A QSO/QTC at time `t` belongs to the contest.
    public func inWindow(_ t: Date) -> Bool { t >= since && (until.map { t < $0 } ?? true) }

    public func band(_ b: String) -> BandScore { perBand[b] ?? BandScore() }
    /// Bands with QSOs or QTC, from the longest one; the unknown band at the end.
    public var bands: [String] { Multipliers.sortBands(Array(perBand.keys)) }

    public var qsos: Int { perBand.values.reduce(0) { $0 + $1.qsos } }
    public var dupes: Int { perBand.values.reduce(0) { $0 + $1.dupes } }
    public var points: Int { perBand.values.reduce(0) { $0 + $1.points } }
    public var qtc: Int { perBand.values.reduce(0) { $0 + $1.qtc } }
    /// Multipliers without the continents (BARTG, SP DX: countries and areas; the continents are a separate factor).
    public var bandMultipliers: Int { multipliers.total - multipliers.total(.continent) }
    /// Continents (BARTG).
    public var continents: Int { multipliers.worked(.continent, band: nil).count }
    /// Multipliers in the Total row of the Score table: with BARTG only per-band ones (continents are separate in the formula).
    public var tableMultiplierTotal: Int {
        rule.formula == .pointsTimesMultipliersTimesContinents ? bandMultipliers : multipliers.total
    }
    /// Multipliers once per contest in the Score table (without the continents of the continent formula).
    public var onceTableCount: Int {
        multipliers.onceCount - (rule.formula == .pointsTimesMultipliersTimesContinents ? multipliers.total(.continent) : 0)
    }
    /// The "Per contest" table row: multipliers once per contest that are part of the total (not BARTG – continents separately).
    public var showsOnceMultiplierRow: Bool {
        multipliers.rule.components.contains { !$0.perBand && !(rule.formula == .pointsTimesMultipliersTimesContinents && $0.kind == .continent) }
    }

    /// The multiplier factor in the score formula.
    public var multiplierFactor: Int {
        switch rule.formula {
        case .pointsTimesMultipliers: return multipliers.total
        case .pointsTimesMultipliersTimesContinents: return bandMultipliers * continents
        case .qsoPlusQTCTimesWeightedMultipliers: return multipliers.weightedTotal
        case .pointsSum: return 1
        case .qsosTimesPointsTimesMultipliers: return multipliers.total
        }
    }

    public var score: Int {
        switch rule.formula {
        case .qsoPlusQTCTimesWeightedMultipliers: return (points + qtc) * multiplierFactor
        case .pointsSum: return points
        case .qsosTimesPointsTimesMultipliers: return (qsos - dupes) * points * multiplierFactor
        default: return points * multiplierFactor
        }
    }

    /// The resulting score formula with numbers ("Points 123 × multipliers 45 = 5 535").
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
        case .qsosTimesPointsTimesMultipliers:
            return L("QSO %@ × body %@ × násobiče %@ = %@", f(qsos - dupes), f(points), f(multipliers.total), f(score))
        }
    }

    /// A whole number with a (non-breaking) space between thousands: 5 535.
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
        // a contest without multipliers (Makrothen): the multiplier tally stays empty as before (Multipliers window: 0 QSOs)
        if multipliers.rule.hasMultipliers { multipliers.add(hits, band: r.band) }
    }

    /// QTC series in the contest window (WAE); other contests do not count QTC.
    public mutating func setQTC(_ series: [QTCSeries]) {
        for k in perBand.keys { perBand[k]?.qtc = 0 }
        guard rule.formula == .qsoPlusQTCTimesWeightedMultipliers else { return }
        for s in series where inWindow(s.time) && s.count > 0 {
            perBand[Bands.band(forHz: s.frequency) ?? Self.unknownBand, default: BandScore()].qtc += s.count
        }
    }
}

/// Computation of points and score according to the contest rules.
public struct ScoreCalculator: Sendable {
    public let rule: ScoreRule
    public let multipliers: MultiplierCalculator
    let lookup: @Sendable (String, Bool) -> CountryInfo?
    /// My own country (for points by country and continent).
    let own: CountryInfo?
    /// My own locator square (4 characters) for Makrothen.
    let ownSquare: String?
    /// My own call (VOLTA: the same call area).
    let ownCall: String

    public init(rule: ScoreRule, multiplierRule: MultiplierRule, ownCall: String, ownLocator: String,
                lookup: @escaping @Sendable (String, Bool) -> CountryInfo?) {
        self.rule = rule; self.lookup = lookup
        multipliers = MultiplierCalculator(rule: multiplierRule, lookup: lookup)
        own = lookup(QSORecord.normalizeCall(ownCall), multiplierRule.waeList)
        ownSquare = Self.square(ownLocator)
        self.ownCall = QSORecord.normalizeCall(ownCall)
    }

    /// Calculator for a preset; my own country is determined from my own call.
    public init(preset: ContestPreset, ownCall: String, ownLocator: String, countries: CountryDB?) {
        let lookup: @Sendable (String, Bool) -> CountryInfo? = { call, wae in countries?.lookup(call, wae: wae) }
        let own = countries?.lookup(ownCall)?.primaryPrefix
        self.init(rule: .rule(for: preset), multiplierRule: .rule(for: preset, ownCountry: own),
                  ownCall: ownCall, ownLocator: ownLocator, lookup: lookup)
    }

    /// Relation of the other station to my own station; nil = the country of one of the stations is unknown.
    public func relation(_ call: String) -> ScoreRelation? {
        guard let a = own, let b = lookup(QSORecord.normalizeCall(call), multipliers.rule.waeList) else { return nil }
        if a.primaryPrefix == b.primaryPrefix { return .sameCountry }
        return a.continent == b.continent ? .sameContinent : .otherContinent
    }

    /// Points for a QSO (regardless of dupe status).
    public func points(_ r: QSORecord) -> Int {
        if rule.preset == .makrothen {
            guard let own = ownSquare, let dx = Self.square(in: r.exchangeRcvd) ?? Self.square(r.grid ?? "") else { return 0 }
            if own == dx { return 100 }
            guard let km = Self.makrothenKm(own, dx) else { return 0 }
            return Int((Double(km) * ScoreRule.makrothenFactor(r.band)).rounded(.down))
        }
        let wae = multipliers.rule.waeList
        var q = QSOPointsInput(relation: relation(r.call), band: r.band)
        q.call = r.call; q.own = own; q.dx = lookup(QSORecord.normalizeCall(r.call), wae)
        q.exchangeSent = [r.serialSent.map(String.init), r.exchangeSent].compactMap { $0 }.joined(separator: " ")
        q.exchangeRcvd = r.exchangeRcvd
        q.ownZone = own?.cqZone
        if rule.preset == .voltaRTTY, let a = multipliers.callArea(r.call, country: q.dx),
           let b = multipliers.callArea(ownCall, country: own) { q.sameCallArea = a == b }
        q.year = Self.utc.component(.year, from: r.timeOn)
        return rule.points(q)
    }

    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()

    /// Full computation from the QSOs in the contest window [since, until) (and WAE QTC series); the tally fixes the window.
    public func tally(records: [QSORecord], qtc: [QTCSeries], since: Date, until: Date? = nil) -> ScoreTally {
        var t = ScoreTally(rule: rule, multiplierRule: multipliers.rule, since: since, until: until)
        t.ownCountryUnknown = rule.needsOwnCountry && own == nil
        t.ownLocatorMissing = rule.preset == .makrothen && ownSquare == nil
        for r in records.sorted(by: { $0.timeOn < $1.timeOn }) { add(r, to: &t) }
        t.setQTC(qtc)
        return t
    }

    /// Adds one logged QSO (without recomputing the whole log) – within the contest window fixed in `t`.
    public func add(_ r: QSORecord, to t: inout ScoreTally) {
        guard t.inWindow(r.timeOn) else { return }
        t.add(record: r, points: points(r), hits: multipliers.rule.hasMultipliers ? multipliers.hits(r) : [])
    }

    // MARK: Makrothen

    /// Earth radius per the Makrothen rules (km).
    static let makrothenRadiusKm = 6378.16

    /// Distance between square centers (4 characters) in whole km (rounded down) per the Makrothen rules.
    public static func makrothenKm(_ a: String, _ b: String) -> Int? {
        guard let sa = square(a), let sb = square(b), let p = Geo.maidenhead(sa), let q = Geo.maidenhead(sb) else { return nil }
        let km = Geo.distanceKm(p, q) / Geo.earthRadiusKm * makrothenRadiusKm
        return Int(km.rounded(.down))
    }

    /// Locator square (the first 4 characters of a valid 4/6/8-character locator).
    static func square(_ locator: String) -> String? {
        let l = locator.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Geo.maidenhead(l) != nil else { return nil }
        return String(l.prefix(4))
    }

    /// The first valid locator in the exchange ("599 JO70" → JO70).
    static func square(in exchange: String?) -> String? {
        (exchange ?? "").split { !$0.isLetter && !$0.isNumber }.lazy.compactMap { square(String($0)) }.first
    }
}
