// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import DXCC
import Localization
import QSOLog
import Settings

// Contest multipliers (multipliers only, not points or score). Rules and sources: docs/rulings.md, "Multipliers in contests".

/// Kind of multiplier.
public enum MultiplierKind: String, Sendable, CaseIterable, Hashable, Codable {
    /// DXCC country (with CQ WW also the WAE list).
    case dxcc
    /// CQ zone 1–40 (from the received exchange, otherwise from DXCC).
    case cqZone
    /// Prefix per the CQ WPX rules.
    case wpxPrefix
    /// US state from the received exchange (48 continental + DC).
    case usState
    /// Canadian province/area from the received exchange (14 including LB).
    case veProvince
    /// JA/W/VE/VK call area (W1, VE3, JA7, VK2 …).
    case callArea
    /// WAE DX Contest: countries of the WAE list, with W/VE/VK/ZL/ZS/JA/BY/PY/UA9 the call areas.
    case waeCountry
    /// Continent (BARTG, once per contest).
    case continent
    /// OK DX RTTY: every OK/OL station.
    case okStation
    /// A code from the received exchange (oblast, territory, province, DOK, year …) – the list or pattern is in the rule.
    case region
    /// Each station (base call) – WRT.
    case station
    /// The country of a club member (the received exchange carries the member mark) – TRC DIGI.
    case memberCountry

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
        case .region: return L("Oblasti")
        case .station: return L("Stanice")
        case .memberCountry: return L("Země členů")
        }
    }

    /// A finite set of values (for the list of missing ones); nil = an open set.
    public var universe: [String]? {
        switch self {
        case .cqZone: return (1...40).map(String.init)
        case .usState: return Multipliers.usStates
        case .veProvince: return Multipliers.veProvinces
        case .continent: return ["AF", "AS", "EU", "NA", "OC", "SA"]
        default: return nil
        }
    }

    /// Value for the label (a zone as "Z14", the rest unchanged).
    public func label(_ value: String) -> String { self == .cqZone ? "Z\(value)" : value }
}

/// One kind of multiplier in the contest rules.
public struct MultiplierComponent: Sendable, Equatable, Hashable {
    public var kind: MultiplierKind
    /// true = counted separately on every band, false = once per contest.
    public var perBand: Bool
    /// Only stations of these countries count (cty.dat primary prefix); nil = all.
    public var onlyCountries: Set<String>?
    /// Stations of these countries do not count.
    public var exceptCountries: Set<String>
    /// Only stations on this continent count (NAQP: North American countries); nil = all.
    public var continent: String?
    public init(_ kind: MultiplierKind, perBand: Bool, only: Set<String>? = nil, except: Set<String> = [],
                continent: String? = nil) {
        self.kind = kind; self.perBand = perBand; onlyCountries = only; exceptCountries = except; self.continent = continent
    }

    /// The station's country passes the filters (an unknown country passes only without a filter).
    func accepts(_ ci: CountryInfo?) -> Bool {
        if onlyCountries == nil, exceptCountries.isEmpty, continent == nil { return true }
        guard let ci else { return false }
        if let o = onlyCountries, !o.contains(ci.primaryPrefix) { return false }
        if exceptCountries.contains(ci.primaryPrefix) { return false }
        if let k = continent, ci.continent != k { return false }
        return true
    }
}

/// Multiplier rules of a single contest.
public struct MultiplierRule: Sendable, Equatable {
    public var preset: ContestPreset
    public var components: [MultiplierComponent]
    /// Countries (cty.dat primary prefix) that do not count as DXCC countries.
    public var excludedCountries: Set<String> = []
    /// Countries are looked up in the WAE list as well (Sicily, Shetland, European Turkey, …).
    public var waeList = false
    /// Countries (cty.dat primary prefix) for which call areas are counted.
    public var callAreaCountries: [String] = []
    /// Band weight (WAE: 80 m × 4, 40 m × 3, the rest × 2); a missing band = 1.
    public var bandWeights: [String: Int] = [:]
    /// A rule verified in the official contest rules (the source is in `source`).
    public var verified: Bool
    /// Unverified parts of the rule (empty = everything verified).
    public var unverifiedNote: String = ""
    public var source: String
    /// Note about the contest for the Multipliers window.
    public var note: String = ""
    /// `.region`: the valid codes (also the list of missing ones); nil = any code matching `regionPattern`.
    public var regionCodes: [String]?
    /// `.region` without a list: a regular expression for one word of the exchange (e.g. a year "^(19|20)[0-9]{2}$").
    public var regionPattern: String?
    /// Contest-specific names of the multiplier kinds ("Oblasti" → "Ruské oblasti").
    public var titles: [MultiplierKind: String] = [:]
    /// `.memberCountry`: the member mark in the received exchange ("TRC").
    public var memberMark: String?

    public var hasMultipliers: Bool { !components.isEmpty }
    public func title(_ k: MultiplierKind) -> String { titles[k] ?? k.title }
    /// A finite set of values of a kind (the list of missing ones); nil = an open set.
    public func universe(_ k: MultiplierKind) -> [String]? { k == .region ? regionCodes : k.universe }
    public func component(_ k: MultiplierKind) -> MultiplierComponent? { components.first { $0.kind == k } }

    /// Rules for the contest settings; nil = outside a contest or a custom (unrecognized) contest.
    /// `ownCountry` = the primary prefix of my own country (OK DX RTTY: OK/OL stations have different multipliers).
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
        case .sartgNewYear:
            let scandinavia = ["JW", "JX", "LA", "OH", "OH0", "OJ0", "OX", "OY", "OZ", "SM", "TF"]
            return MultiplierRule(preset: p, components: [.init(.dxcc, perBand: true, except: Set(scandinavia)),
                                                          .init(.callArea, perBand: true)],
                                  callAreaCountries: scandinavia, verified: true,
                                  unverifiedNote: L("Značka JW/JX/OX/OY/TF bez číslice – počítá se jako oblast 0."),
                                  source: "http://www.sartg.com/contest/nyrules.htm",
                                  note: L("Země DXCC kromě Skandinávie a skandinávské číselné oblasti (SM3, OH0 …) na každém pásmu."),
                                  titles: [.callArea: L("Skandinávské oblasti")])
        case .proDigi:
            return MultiplierRule(preset: p, components: [.init(.wpxPrefix, perBand: true, except: ownCountry.map { [$0] } ?? [])],
                                  verified: true,
                                  unverifiedNote: L("Pravidla si odporují, zda se duplicita počítá na pásmu, nebo na pásmu a módu – počítá se pásmo a mód."),
                                  source: "https://proradiocontestclub.com/PDC%20Rules.html",
                                  note: L("Prefixy WPX na každém pásmu; prefixy vlastní země se nepočítají."))
        case .bartgSprint, .bartgSprint75:
            return MultiplierRule(preset: p, components: [.init(.dxcc, perBand: false), .init(.callArea, perBand: false),
                                                          .init(.continent, perBand: false)],
                                  callAreaCountries: jwvv, verified: true,
                                  source: p == .bartgSprint ? "https://bartg.org.uk/bartg-sprint-contest/"
                                                            : "https://bartg.org.uk/bartg-sprint75-contests/",
                                  note: L("Země DXCC a oblasti JA/W/VE/VK jednou za závod; kontinenty jednou za závod (max. 6), ve skóre se násobí zvlášť."))
        case .mexicoRTTY:
            return MultiplierRule(preset: p, components: [.init(.region, perBand: true, only: ["XE"]), .init(.dxcc, perBand: true)],
                                  verified: true,
                                  unverifiedNote: L("Anglická a španělská pravidla se liší v bodech i v tom, zda země DXCC platí na každém pásmu – použita anglická verze, země na každém pásmu."),
                                  source: "https://rtty.fmre.mx/reglas.html",
                                  note: L("Mexické státy (z výměny XE stanic) a země DXCC na každém pásmu."),
                                  regionCodes: ContestCodes.xeStates, titles: [.region: L("Mexické státy")])
        case .naqpRTTY, .naSprintRTTY:
            let perBand = p == .naqpRTTY
            return MultiplierRule(preset: p, components: [.init(.region, perBand: perBand, only: ["K", "VE", "KH6", "KL"]),
                                                          .init(.dxcc, perBand: perBand, except: ["K", "VE", "KL"], continent: "NA")],
                                  verified: true,
                                  source: perBand ? "https://www.ncjweb.com/NAQP-Rules.pdf" : "https://ncjweb.com/Sprint-Rules.pdf",
                                  note: perBand ? L("Státy USA + DC, kanadské provincie a ostatní země Severní Ameriky na každém pásmu. Stanice mimo Severní Ameriku násobiče nedávají.")
                                                : L("Státy USA + DC, kanadské provincie a ostatní země Severní Ameriky jednou za závod. Spojení DX–DX neplatí."),
                                  regionCodes: ContestCodes.usStates50 + ContestCodes.veProvinces13,
                                  titles: [.region: L("Státy a provincie"), .dxcc: L("Země Severní Ameriky")])
        case .ybDX:
            let yb = ownCountry == "YB"
            return MultiplierRule(preset: p, components: [.init(.wpxPrefix, perBand: true, only: yb ? nil : ["YB"]),
                                                          .init(.dxcc, perBand: true)],
                                  verified: true,
                                  unverifiedNote: L("Prefixy 7A–7I a 8A–8I se počítají jako prefixy WPX (7A1 …)."),
                                  source: "https://rtty.ybdxcontest.com/",
                                  note: yb ? L("Prefixy WPX a země DXCC na každém pásmu.")
                                           : L("Indonéské prefixy (YB0–9, YC … , 7A–8I) a země DXCC na každém pásmu."),
                                  titles: yb ? [:] : [.wpxPrefix: L("Prefixy YB")])
        case .eaRTTY:
            return MultiplierRule(preset: p, components: [.init(.dxcc, perBand: true),
                                                          .init(.region, perBand: true, only: ["EA", "EA6", "EA8", "EA9"]),
                                                          .init(.callArea, perBand: true)],
                                  waeList: true, callAreaCountries: jwvv, verified: true,
                                  unverifiedNote: L("Zda VO/VY patří do oblastí VE – pravidla neuvádějí, počítají se podle číslice prefixu."),
                                  source: "https://concursos.ure.es/en/eartty/bases/",
                                  note: L("Země EADX100 (DXCC + Shetlandy, Sicílie …), španělské provincie (a HQ = EA4URE) a oblasti W/VE/JA/VK na každém pásmu."),
                                  regionCodes: ContestCodes.eaProvinces, titles: [.dxcc: L("Země EADX100"), .region: L("Provincie EA")])
        case .igryWW:
            return MultiplierRule(preset: p, components: [.init(.region, perBand: true)], verified: true,
                                  source: "https://www.ig-ry.de/ig-ry-ww-contest",
                                  note: L("Každý rok první licence (z výměny) na každém pásmu."),
                                  regionPattern: "^(19|20)[0-9]{2}$", titles: [.region: L("Roky licence")])
        case .spDX:
            let ruBy: Set<String> = ["UA", "UA2", "UA9", "EU"]
            return MultiplierRule(preset: p, components: [.init(.dxcc, perBand: true, except: ruBy),
                                                          .init(.region, perBand: true, only: ["SP"]),
                                                          .init(.continent, perBand: false, except: ruBy)],
                                  verified: true,
                                  unverifiedNote: L("Spojení s UA a EW se nepočítají (body ani násobiče); duplicita na pásmu z pravidel pro SWL."),
                                  source: "https://pkrvg.org/strona,spdxrttyen.html",
                                  note: L("Země DXCC (bez UA a EW) a polské powiaty na každém pásmu; kontinenty jednou za závod, ve skóre se násobí zvlášť."),
                                  regionCodes: ContestCodes.spPowiats, titles: [.region: L("Powiaty SP")])
        case .voltaRTTY:
            let areas = ["K", "VE", "JA", "VK", "ZL"]
            return MultiplierRule(preset: p, components: [.init(.dxcc, perBand: true, except: Set(areas + (ownCountry.map { [$0] } ?? []))),
                                                          .init(.callArea, perBand: true)],
                                  callAreaCountries: areas, verified: true,
                                  unverifiedNote: L("Bonusový násobič za zemi jiného kontinentu na 4 pásmech se nepočítá."),
                                  source: "https://www.contestvolta.it/rules.pdf",
                                  note: L("Země DXCC na každém pásmu; u JA/W/VE/VK/ZL místo země číselné oblasti. Vlastní země násobič nedává."))
        case .rookieRoundup:
            return MultiplierRule(preset: p, components: [.init(.region, perBand: false)], verified: true,
                                  unverifiedNote: L("Vzorec skóre pravidla výslovně neuvádějí – body × násobiče."),
                                  source: "https://www.arrl.org/rookie-roundup",
                                  note: L("Státy USA + DC, kanadské provincie, mexické oblasti XE1/XE2/XE3/XF1/XF4 a jednou „DX“ – vše jednou za závod."),
                                  regionCodes: ContestCodes.usStates50 + ContestCodes.veProvinces13 + ["XE1", "XE2", "XE3", "XF1", "XF4", "DX"],
                                  titles: [.region: L("QTH")])
        case .russianRTTY, .russianDigi:
            return MultiplierRule(preset: p, components: [.init(.region, perBand: true), .init(.dxcc, perBand: true)],
                                  waeList: p == .russianRTTY, verified: true,
                                  unverifiedNote: p == .russianDigi ? L("Aplikace jede jen RTTY – násobiče a duplicity „na pásmu a módu“ se počítají pro RTTY.") : "",
                                  source: p == .russianRTTY ? "https://www.contest.ru/russian-ww-rtty-contest-rules-en/"
                                                            : "http://www.rdrclub.ru/rdrc-news/russian-ww-digital-contest/51-rus-ww-digi-rules",
                                  note: p == .russianRTTY ? L("Ruské oblasti (z výměny) a země DXCC + WAE na každém pásmu.")
                                                          : L("Ruské oblasti (z výměny) a země DXCC na každém pásmu."),
                                  regionCodes: ContestCodes.russianOblasts, titles: [.region: L("Ruské oblasti")])
        case .urcDX:
            return MultiplierRule(preset: p, components: [.init(.region, perBand: true)], verified: true,
                                  unverifiedNote: L("Pravidla neuvádějí duplicitu – počítá se jednou na pásmu."),
                                  source: "https://unicomradio.com/urc-dx-rtty-contest/",
                                  note: L("Každé teritorium URC (z výměny, např. BHE, MOR, SLA) na každém pásmu; MMS se nepočítá."),
                                  regionCodes: ContestCodes.urcTerritories, titles: [.region: L("Teritoria URC")])
        case .darcSprint:
            return MultiplierRule(preset: p, components: [.init(.region, perBand: true, only: ["DL"]), .init(.wpxPrefix, perBand: true)],
                                  verified: true,
                                  unverifiedNote: L("DOK se rozpoznává ve tvaru písmeno + 2 číslice (B01); zvláštní DOKy jinak. „Prefix“ podle WPX."),
                                  source: "https://www.darc.de/der-club/referate/conteste/rtty-kurz/darc-rtty-contest-english-version/darc-rtty-rules/",
                                  note: L("DOKy (z výměny DL stanic, NM se nepočítá) a prefixy na každém pásmu."),
                                  regionPattern: "^[A-Z][0-9]{2}$", titles: [.region: "DOK"])
        case .trcDigi:
            return MultiplierRule(preset: p, components: [.init(.dxcc, perBand: true), .init(.memberCountry, perBand: true)],
                                  verified: true,
                                  unverifiedNote: L("Pravidla neuvádějí duplicitu – počítá se jednou na pásmu."),
                                  source: "https://trcdx.org/rules-trc-digi/",
                                  note: L("Země DXCC a země stanic TRC (výměna s „TRC“) na každém pásmu."),
                                  titles: [.memberCountry: L("Země členů TRC")], memberMark: "TRC")
        case .wrt:
            return MultiplierRule(preset: p, components: [.init(.station, perBand: false)], verified: true,
                                  unverifiedNote: L("Vzorec skóre a duplicita nejsou v pravidlech výslovně – body × různé značky, jednou na pásmu (modul N1MM)."),
                                  source: "https://radiosport.world/wrt.html",
                                  note: L("Každá značka jednou za závod."))
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

/// One multiplier of a QSO (kind + value).
public struct MultiplierHit: Sendable, Hashable, Codable {
    public var kind: MultiplierKind
    public var value: String
    public init(_ kind: MultiplierKind, _ value: String) { self.kind = kind; self.value = value }
    public var label: String { kind.label(value) }
}

/// Multipliers a QSO would bring (for the NEW MULT label).
public struct NewMultiplier: Sendable, Equatable {
    public var hits: [MultiplierHit]
    /// The band on which they are new (nil = band unknown, only "once per contest" multipliers are new).
    public var band: String?
    public init(hits: [MultiplierHit] = [], band: String? = nil) { self.hits = hits; self.band = band }
    public var isEmpty: Bool { hits.isEmpty }
    public var text: String {
        let l = hits.map(\.label).joined(separator: ", ")
        return band.map { "\($0): \(l)" } ?? l
    }
}

/// Worked multipliers of a contest: for every band and for the "once per contest" multipliers.
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

    /// Worked values; `band` is used only for per-band multipliers.
    public func worked(_ kind: MultiplierKind, band: String?) -> Set<String> {
        guard let c = rule.component(kind) else { return [] }
        if c.perBand { return band.flatMap { perBand[$0]?[kind] } ?? [] }
        return once[kind] ?? []
    }

    /// Missing values (finite sets only), sorted.
    public func missing(_ kind: MultiplierKind, band: String?) -> [String]? {
        guard let u = rule.universe(kind) else { return nil }
        let w = worked(kind, band: band)
        return u.filter { !w.contains($0) }
    }

    /// Bands with at least one per-band multiplier, in order from the longest one.
    public var bands: [String] { Multipliers.sortBands(Array(perBand.keys)) }

    /// Per-band multipliers on the given band (all kinds).
    public func count(band: String) -> Int { perBand[band]?.values.reduce(0) { $0 + $1.count } ?? 0 }
    /// Multipliers counted once per contest.
    public var onceCount: Int { once.values.reduce(0) { $0 + $1.count } }
    /// Total count of a kind (the per-band ones summed across bands).
    public func total(_ kind: MultiplierKind) -> Int {
        guard let c = rule.component(kind) else { return 0 }
        if c.perBand { return perBand.values.reduce(0) { $0 + ($1[kind]?.count ?? 0) } }
        return once[kind]?.count ?? 0
    }
    /// Total multipliers (without band weights).
    public var total: Int { perBand.keys.reduce(0) { $0 + count(band: $1) } + onceCount }
    /// Total multipliers with band weights (WAE); without weights = `total`.
    public var weightedTotal: Int {
        perBand.keys.reduce(0) { $0 + count(band: $1) * (rule.bandWeights[$1] ?? 1) } + onceCount
    }

    /// Which of a QSO's multipliers are new (on the given band / in the contest).
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

/// Computation of a QSO's multipliers according to the contest rules.
public struct MultiplierCalculator: Sendable {
    public let rule: MultiplierRule
    let lookup: @Sendable (String, Bool) -> CountryInfo?

    public init(rule: MultiplierRule, lookup: @escaping @Sendable (String, Bool) -> CountryInfo?) {
        self.rule = rule; self.lookup = lookup
    }
    public init(rule: MultiplierRule, countries: CountryDB?) {
        self.init(rule: rule) { call, wae in countries?.lookup(call, wae: wae) }
    }

    /// Multipliers of a single QSO. `exchange` = the received exchange (zone, state …), `zone` = the CQ zone from the log.
    public func hits(call: String, exchange: String?, zone: Int? = nil) -> [MultiplierHit] {
        let c = QSORecord.normalizeCall(call)
        guard !c.isEmpty, rule.hasMultipliers else { return [] }
        let dx = lookup(c, false)
        var out: [MultiplierHit] = []
        for comp in rule.components where comp.accepts(comp.kind == .dxcc && rule.waeList ? lookup(c, true) : dx) {
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
            case .region:
                if let r = region(in: exchange) { out.append(.init(.region, r)) }
            case .station:
                out.append(.init(.station, QSORecord.baseCall(c)))
            case .memberCountry:
                if let m = rule.memberMark, Multipliers.hasMark(m, in: exchange), let dx { out.append(.init(.memberCountry, dx.primaryPrefix)) }
            }
        }
        return out
    }

    /// Call area (W1, VE3, JA0, RA9 …) for countries with areas; the digit = the last digit of the WPX prefix
    /// (a portable prefix without a digit = 0, /digit changes the area).
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

    /// The first word of the exchange that is a valid region code (from the list, otherwise by the pattern).
    func region(in exchange: String?) -> String? {
        let words = Multipliers.tokens(exchange)
        if let codes = rule.regionCodes {
            let set = Set(codes)
            return words.first { set.contains($0) }
        }
        guard let p = rule.regionPattern, let re = try? NSRegularExpression(pattern: p) else { return nil }
        return words.first { re.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
    }

    public func hits(_ r: QSORecord) -> [MultiplierHit] { hits(call: r.call, exchange: r.exchangeRcvd, zone: r.cqZone) }

    /// Multipliers from the QSOs since the contest start.
    public func tally(records: [QSORecord], since: Date) -> MultiplierTally {
        var t = MultiplierTally(rule: rule)
        for r in records.sorted(by: { $0.timeOn < $1.timeOn }) { add(r, to: &t, since: since) }
        return t
    }

    /// Adds one QSO to the running total (after logging; without recomputing the whole log).
    public func add(_ r: QSORecord, to t: inout MultiplierTally, since: Date) {
        guard rule.hasMultipliers, r.timeOn >= since else { return }
        t.add(hits(r), band: r.band)
    }
}

/// Helper tables and exchange parsing.
public enum Multipliers {
    /// 48 continental US states + DC (KH6 and KL7 are DXCC countries, not states).
    public static let usStates = ["AL", "AR", "AZ", "CA", "CO", "CT", "DC", "DE", "FL", "GA", "IA", "ID", "IL", "IN", "KS", "KY",
                                  "LA", "MA", "MD", "ME", "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NE", "NH", "NJ", "NM", "NV",
                                  "NY", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VA", "VT", "WA", "WI", "WV", "WY"]
    /// 14 Canadian areas (CQ WW RTTY; ARRL: provinces and territories + Labrador).
    public static let veProvinces = ["AB", "BC", "LB", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT"]
    static let aliases: [String: String] = ["NWT": "NT", "NF": "NL", "NFL": "NL", "NFLD": "NL", "PEI": "PE", "PQ": "QC",
                                            "YK": "YT", "LAB": "LB"]
    private static let stateSet = Set(usStates), provinceSet = Set(veProvinces)

    /// The exchange carries the mark ("TRC", "M") as a word or right after the number ("001TRC", "001M").
    public static func hasMark(_ mark: String, in exchange: String?) -> Bool {
        tokens(exchange).contains { t in
            t == mark || (t.hasSuffix(mark) && t.dropLast(mark.count).allSatisfy(\.isNumber) && t.count > mark.count)
        }
    }

    static func tokens(_ s: String?) -> [String] {
        (s ?? "").uppercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    /// CQ zone from the exchange ("14", "05 NY", "599 14" → the first number 1–40 after skipping the RST 5NN).
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
    /// A single word as a US state (48 + DC) or a Canadian area (including the abbreviations NWT, PEI …); otherwise nil.
    public static func stateOrProvince(_ word: String) -> String? {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let n = aliases[w] ?? w
        return stateSet.contains(n) || provinceSet.contains(n) ? n : nil
    }

    static let bandOrder = ["2190m", "630m", "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m",
                            "6m", "4m", "2m", "1.25m", "70cm"]
    public static func sortBands(_ b: [String]) -> [String] {
        b.sorted { (bandOrder.firstIndex(of: $0) ?? 99, $0) < (bandOrder.firstIndex(of: $1) ?? 99, $1) }
    }
    /// Contest bands (RTTY contests on HF without WARC) – grid rows even without QSOs.
    public static let contestBands = ["80m", "40m", "20m", "15m", "10m"]
}

/// Prefix per the CQ WPX rules.
///
/// Prefix = the letters and digits of the first part of the call up to the digit before the suffix (N8, WD8, OE25, LY1000).
/// A portable designator becomes the prefix; a designator without a digit gets 0 (PA/N8BJQ = PA0),
/// a call without a digit gets 0 after the first two letters (XEFTJW = XE0). /P, /M, /MM, /AM, /QRP, /A, /E, /J
/// are ignored. /digit changes the prefix number (W1ABC/3 = W3) – not stated in the rules, common practice.
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

    /// Portable designator: the part that is not a whole call (ends with a digit or has none); otherwise the shortest one.
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

    /// Prefix of a whole call: everything up to the last digit that is followed by a letter.
    static func callPrefix(_ c: String) -> String {
        let a = Array(c)
        var end: Int?
        for i in a.indices.dropLast() where a[i].isNumber && a[i + 1].isLetter { end = i }
        if let end { return String(a[...end]) }
        if !a.contains(where: \.isNumber) { return String(c.prefix(2)) + "0" }       // XEFTJW → XE0
        return c                                                                     // only digits at the end
    }
}
