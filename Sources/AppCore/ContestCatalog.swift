// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import DXCC
import Localization
import QSOLog
import Settings

/// A contest's rules in one place for Settings: what is exchanged, how it scores, the dupes and the source.
public struct ContestRules: Sendable, Equatable {
    public var dates: String
    public var bands: String
    public var exchange: String
    public var points: String
    public var multipliers: String
    public var dupes: String
    /// Unverified or ambiguous parts (empty = none).
    public var unverified: [String]
    public var source: String
}

/// The catalogue of the contest presets: the rules overview and the default sent exchange.
public enum ContestCatalog {
    /// The rules of a preset. `ownCountry` = the primary prefix of my own country (some rules depend on it).
    public static func rules(_ p: ContestPreset, ownCountry: String? = nil) -> ContestRules {
        let s = ScoreRule.rule(for: p), m = MultiplierRule.rule(for: p, ownCountry: ownCountry)
        let parts = p.summary.components(separatedBy: " · ")
        let hours = p.durationHours == p.durationHours.rounded() ? String(Int(p.durationHours)) : String(p.durationHours)
        let dupes = DupeCheck.perMode(preset: p) ? L("Stejná stanice jednou na pásmu a módu.") : L("Stejná stanice jednou na pásmu.")
        return ContestRules(dates: L("%@ (%@ h)", parts.first ?? "", hours),
                            bands: p.bands.joined(separator: ", "),
                            exchange: parts.dropFirst().joined(separator: " · "),
                            points: s.pointsNote,
                            multipliers: m.note,
                            dupes: dupes,
                            unverified: [s.unverifiedNote, m.unverifiedNote].filter { !$0.isEmpty },
                            source: m.source)
    }

    /// The sent exchange the preset needs from my station (empty = a serial number, my zone from DXCC, or it has to be
    /// filled in by hand: age, licence year, membership).
    public static func defaultExchange(_ p: ContestPreset, station: Station, countries: CountryDB?) -> String {
        let call = QSORecord.normalizeCall(station.call)
        let country = countries?.lookup(call)
        // RTTY (ITA2) has no diacritics: Tomáš → TOMAS
        let name = station.name.trimmingCharacters(in: .whitespaces).folding(options: .diacriticInsensitive, locale: nil).uppercased()
        let firstName = name.split(separator: " ").first.map(String.init) ?? ""
        let northAmerica = country.map { $0.continent == "NA" || $0.primaryPrefix == "KH6" } ?? false
        // QTH for the North American contests: a state/province from Station → QTH, otherwise the DXCC prefix
        let qthWord = station.qth.uppercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .first { Multipliers.stateOrProvince($0) != nil }
        let qth = northAmerica ? (qthWord ?? country?.primaryPrefix ?? "") : "DX"
        func join(_ x: String...) -> String { x.filter { !$0.isEmpty }.joined(separator: " ") }
        switch p {
        case .urcDX: return urcTerritory(call) ?? ""
        case .wrt: return join(firstName, northAmerica ? qth : (country?.primaryPrefix ?? ""))
        case .naqpRTTY: return northAmerica ? join(firstName, qth) : firstName
        case .naSprintRTTY: return join(firstName, qth)
        case .rookieRoundup: return join(firstName, qth)
        case .sartgNewYear: return firstName
        default: return ""
        }
    }

    /// Contests whose exchange has no RST (NA Sprint, NAQP, WRT, Rookie Roundup, BARTG Sprint).
    public static func sendsRST(_ p: ContestPreset?) -> Bool {
        ![.naSprintRTTY, .naqpRTTY, .wrt, .rookieRoundup, .bartgSprint, .bartgSprint75].contains(p)
    }

    /// The whole sent exchange (%e) per the contest rules: [RST] [serial] [text] separated by spaces; outside a contest the RST.
    public static func sentExchange(_ c: ContestSettings, rst: String, serial: Int?, text: String) -> String {
        let r = rst.isEmpty ? "599" : rst
        guard c.enabled else { return r }
        let parts = [sendsRST(c.selectedPreset) ? r : "", serial.map { String(format: "%03d", $0) } ?? "", text]
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// URC territory from the call: the longest URC prefix with a single territory (OK1 → BHE, OM → SLA).
    public static func urcTerritory(_ call: String) -> String? {
        let c = QSORecord.normalizeCall(call)
        let wpx = WPX.prefix(c) ?? c
        for src in [wpx, c] {
            var p = src
            while !p.isEmpty {
                if let t = ContestCodes.urcByPrefix[p] { return t }
                p.removeLast()
            }
        }
        return nil
    }
}
