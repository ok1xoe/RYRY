// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Localization

/// When a contest takes place (UTC). Several entries = several dates a year (NAQP, NA Sprint, DARC sprint).
public enum ContestSchedule: Sendable, Equatable {
    /// The n-th full weekend of a month (0 = the last one); `hour` = hours from Saturday 00:00 (Sunday 18:00 = 42).
    case fullWeekend(month: Int, n: Int, hour: Double)
    /// The n-th given weekday of a month (1 = Sunday … 7 = Saturday; n = 0 → the last one) and the start hour.
    case weekday(month: Int, weekday: Int, n: Int, hour: Double)
    /// A fixed date.
    case date(month: Int, day: Int, hour: Double)
    /// Every week on the given weekday (1 = Sunday … 7 = Saturday).
    case weekly(weekday: Int, hour: Double)

    static var utc: Calendar {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// The starts in the given year, in order.
    public func starts(year: Int) -> [Date] {
        let cal = Self.utc
        func day(_ m: Int, _ d: Int) -> Date? {
            guard let x = cal.date(from: DateComponents(year: year, month: m, day: d)), cal.component(.month, from: x) == m
            else { return nil }
            return x
        }
        switch self {
        case .fullWeekend(let m, let n, let h):
            let sats = (1...31).compactMap { d -> Date? in
                guard let x = day(m, d), cal.component(.weekday, from: x) == 7, day(m, d + 1) != nil else { return nil }
                return x
            }
            let s = n == 0 ? sats.last : (sats.count >= n ? sats[n - 1] : nil)
            return s.map { [$0.addingTimeInterval(h * 3600)] } ?? []
        case .weekday(let m, let wd, let n, let h):
            let days = (1...31).compactMap { d in day(m, d).flatMap { cal.component(.weekday, from: $0) == wd ? $0 : nil } }
            let s = n == 0 ? days.last : (days.count >= n ? days[n - 1] : nil)
            return s.map { [$0.addingTimeInterval(h * 3600)] } ?? []
        case .date(let m, let d, let h):
            return day(m, d).map { [$0.addingTimeInterval(h * 3600)] } ?? []
        case .weekly(let wd, let h):
            return (1...12).flatMap { m in (1...31).compactMap { d in day(m, d) } }
                .filter { cal.component(.weekday, from: $0) == wd }.map { $0.addingTimeInterval(h * 3600) }
        }
    }
}

/// Presets of known RTTY contests (name for Cabrillo, format, dates, exchange) – in calendar year order.
/// Rules and sources: docs/rulings.md, "Contest catalogue"; scoring and multipliers in AppCore (Score, Multipliers).
public enum ContestPreset: String, CaseIterable, Codable, Sendable {
    case sartgNewYear, arrlRoundup, proDigi, bartgSprint, mexicoRTTY, cqwpxRTTY, naqpRTTY, naSprintRTTY, ybDX, bartgHF
    case eaRTTY, igryWW, bartgSprint75, spDX, voltaRTTY, sartgRTTY, rookieRoundup, russianRTTY, cqwwRTTY
    case urcDX, russianDigi, makrothen, darcSprint, jartsRTTY, waeRTTY, trcDigi, okDXRTTY, wrt

    public var title: String {
        switch self {
        case .sartgNewYear: return "SARTG New Year RTTY"
        case .arrlRoundup: return "ARRL RTTY Roundup"
        case .proDigi: return "PRO Digi Contest"
        case .bartgSprint: return "BARTG RTTY Sprint"
        case .mexicoRTTY: return "Mexico RTTY International"
        case .cqwpxRTTY: return "CQ WPX RTTY"
        case .naqpRTTY: return "NAQP RTTY"
        case .naSprintRTTY: return "North American Sprint RTTY"
        case .ybDX: return "YB DX RTTY"
        case .bartgHF: return "BARTG HF RTTY"
        case .eaRTTY: return "EA RTTY (URE)"
        case .igryWW: return "IG-RY WW RTTY"
        case .bartgSprint75: return "BARTG Sprint 75"
        case .spDX: return "SP DX RTTY"
        case .voltaRTTY: return "VOLTA WW RTTY"
        case .sartgRTTY: return "SARTG WW RTTY"
        case .rookieRoundup: return "ARRL Rookie Roundup RTTY"
        case .russianRTTY: return "Russian WW RTTY"
        case .cqwwRTTY: return "CQ WW RTTY"
        case .urcDX: return "URC DX RTTY"
        case .russianDigi: return "Russian WW Digital"
        case .makrothen: return "Makrothen RTTY"
        case .darcSprint: return "DARC RTTY Sprint (Kurz-Contest)"
        case .jartsRTTY: return "JARL WW RTTY (JARTS)"
        case .waeRTTY: return "WAE DX Contest RTTY"
        case .trcDigi: return "TRC DIGI"
        case .okDXRTTY: return "OK DX RTTY Contest"
        case .wrt: return "Weekly RTTY Test (WRT)"
        }
    }

    /// CONTEST: in Cabrillo.
    public var cabrilloName: String {
        switch self {
        case .sartgNewYear: return "SARTG-NY-RTTY"
        case .arrlRoundup: return "ARRL-RTTY"
        case .proDigi: return "PDC"
        case .bartgSprint: return "BARTG-SPRINT"
        case .mexicoRTTY: return "XE-RTTY"
        case .cqwpxRTTY: return "CQ-WPX-RTTY"
        case .naqpRTTY: return "NAQP-RTTY"
        case .naSprintRTTY: return "NA-SPRINT-RTTY"
        case .ybDX: return "YB-DX-CONTEST"
        case .bartgHF: return "BARTG-RTTY"
        case .eaRTTY: return "EARTTY"
        case .igryWW: return "IG-WW-RY"
        case .bartgSprint75: return "BARTG-SPRINT75"
        case .spDX: return "SPDX-RTTY"
        case .voltaRTTY: return "VOLTA-RTTY"
        case .sartgRTTY: return "SARTG-RTTY"
        case .rookieRoundup: return "ARRL-RR-DIG"
        case .russianRTTY: return "RADIO-WW-RTTY"
        case .cqwwRTTY: return "CQ-WW-RTTY"
        case .urcDX: return "URCDX"
        case .russianDigi: return "RUS-WW-DIGI"
        case .makrothen: return "MAKROTHEN-RTTY"
        case .darcSprint: return "SHORTRY"
        case .jartsRTTY: return "JARL-WW-RTTY"
        case .waeRTTY: return "DARC-WAEDC-RTTY"
        case .trcDigi: return "TRC-DIGI"
        case .okDXRTTY: return "OK-DX-RTTY"
        case .wrt: return "WRT"
        }
    }

    public var format: ContestFormat {
        switch self {
        case .cqwwRTTY: return .cqrj
        case .bartgHF: return .bartg
        case .waeRTTY: return .wae
        case .okDXRTTY: return .zone
        case .sartgNewYear, .naSprintRTTY, .trcDigi, .proDigi, .voltaRTTY: return .serialText
        case .urcDX, .wrt, .naqpRTTY, .rookieRoundup, .igryWW: return .text
        case .arrlRoundup, .cqwpxRTTY, .sartgRTTY, .makrothen, .jartsRTTY, .mexicoRTTY, .ybDX, .eaRTTY, .bartgSprint,
             .bartgSprint75, .russianRTTY, .russianDigi, .darcSprint, .spDX:
            return .serial
        }
    }

    /// Dates of the contest (UTC).
    public var schedule: [ContestSchedule] {
        switch self {
        case .sartgNewYear: return [.date(month: 1, day: 1, hour: 8)]
        case .arrlRoundup: return [.fullWeekend(month: 1, n: 1, hour: 18)]
        case .proDigi: return [.fullWeekend(month: 1, n: 3, hour: 12)]
        case .bartgSprint: return [.fullWeekend(month: 1, n: 4, hour: 12)]
        case .mexicoRTTY: return [.fullWeekend(month: 2, n: 1, hour: 12)]
        case .cqwpxRTTY: return [.fullWeekend(month: 2, n: 2, hour: 0)]
        case .naqpRTTY: return [.weekday(month: 2, weekday: 7, n: 0, hour: 18), .fullWeekend(month: 7, n: 3, hour: 18)]
        case .naSprintRTTY:                                  // the Sunday after the 2nd Saturday of March / 3rd of September
            return [.weekday(month: 3, weekday: 7, n: 2, hour: 24), .weekday(month: 9, weekday: 7, n: 3, hour: 24)]
        case .ybDX: return [.weekday(month: 3, weekday: 7, n: 2, hour: 0)]
        case .bartgHF: return [.fullWeekend(month: 3, n: 3, hour: 2)]
        case .eaRTTY: return [.fullWeekend(month: 4, n: 1, hour: 12)]
        case .igryWW: return [.fullWeekend(month: 4, n: 2, hour: 12)]
        case .bartgSprint75: return [.weekday(month: 4, weekday: 1, n: 4, hour: 17)]
        case .spDX: return [.fullWeekend(month: 4, n: 4, hour: 12)]
        case .voltaRTTY: return [.fullWeekend(month: 5, n: 2, hour: 12)]
        case .sartgRTTY: return [.fullWeekend(month: 8, n: 3, hour: 0)]
        case .rookieRoundup: return [.fullWeekend(month: 8, n: 3, hour: 42)]
        case .russianRTTY: return [.fullWeekend(month: 9, n: 1, hour: 12)]
        case .cqwwRTTY: return [.fullWeekend(month: 9, n: 0, hour: 0)]
        case .urcDX: return [.weekday(month: 10, weekday: 6, n: 1, hour: 0)]
        case .russianDigi: return [.weekday(month: 10, weekday: 7, n: 1, hour: 12)]
        case .makrothen: return [.fullWeekend(month: 10, n: 2, hour: 0)]
        case .darcSprint: return [1, 4, 7, 10].map { .weekday(month: $0, weekday: 3, n: 2, hour: 18) }
        case .jartsRTTY: return [.fullWeekend(month: 10, n: 3, hour: 0)]
        case .waeRTTY: return [.fullWeekend(month: 11, n: 2, hour: 0)]
        case .trcDigi: return [.fullWeekend(month: 12, n: 2, hour: 6)]
        case .okDXRTTY: return [.fullWeekend(month: 12, n: 3, hour: 0)]
        case .wrt: return [.weekly(weekday: 6, hour: 1.75)]
        }
    }

    /// The starts in the given year, in order.
    public func starts(year: Int) -> [Date] { schedule.flatMap { $0.starts(year: year) }.sorted() }

    /// Contest length in hours from the start according to the official rules (docs/rulings.md, "Scoring and score").
    public var durationHours: Double {
        switch self {
        case .wrt: return 0.5
        case .darcSprint: return 1.5
        case .sartgNewYear: return 3
        case .naSprintRTTY, .bartgSprint75: return 4
        case .rookieRoundup: return 6
        case .naqpRTTY: return 12
        case .okDXRTTY, .proDigi, .bartgSprint, .ybDX, .eaRTTY, .spDX, .voltaRTTY, .russianRTTY, .urcDX, .russianDigi: return 24
        case .arrlRoundup, .igryWW: return 30                  // ARRL: Sat 18:00 – Sun 23:59
        case .mexicoRTTY, .trcDigi: return 36
        case .sartgRTTY, .makrothen: return 40                 // three legs: Sat 00–08, Sat 16–24, Sun 08–16
        case .cqwpxRTTY, .bartgHF, .cqwwRTTY, .jartsRTTY, .waeRTTY: return 48   // BARTG Sat 02:00 – Mon 01:59
        }
    }

    /// Bands of the contest.
    public var bands: [String] {
        switch self {
        case .sartgNewYear, .darcSprint: return ["80m", "40m"]
        case .naSprintRTTY: return ["80m", "40m", "20m"]
        case .urcDX, .russianDigi, .trcDigi: return ["160m", "80m", "40m", "20m", "15m", "10m"]
        default: return ["80m", "40m", "20m", "15m", "10m"]
        }
    }

    /// Serial-number contests where some stations send a code instead of the number: the name of the code
    /// (the "State/prov. r" field); nil = everybody sends the same.
    public var alternativeCode: String? {
        switch self {
        case .arrlRoundup: return L("Stát/prov.")
        case .russianRTTY, .russianDigi: return L("Oblast")
        case .darcSprint: return "DOK"
        case .mexicoRTTY: return L("Stát")
        case .eaRTTY: return L("Provincie")
        case .spDX: return L("Powiat")
        default: return nil
        }
    }

    /// Name of the text part of the exchange (formats `serialText` and `text`, a fixed exchange).
    public var textLabel: String? {
        switch self {
        case .sartgNewYear: return L("Jméno")
        case .naSprintRTTY, .wrt, .naqpRTTY: return L("Jméno QTH")
        case .trcDigi: return "TRC"
        case .proDigi: return L("Člen")
        case .voltaRTTY: return L("Zóna")
        case .urcDX: return L("Teritorium")
        case .rookieRoundup: return L("Jméno rok QTH")
        case .igryWW: return L("Rok")
        case .jartsRTTY: return L("Věk")
        case .makrothen: return L("Lokátor")
        default: return nil
        }
    }

    /// The text part is optional (a member mark – non-members send nothing).
    public var textOptional: Bool { self == .trcDigi || self == .proDigi }
    /// The received text starts with the name (the call history fills it in).
    public var textIsName: Bool { [.sartgNewYear, .naSprintRTTY, .wrt, .naqpRTTY, .rookieRoundup].contains(self) }

    /// Date and exchange on one line (for the menu and the label in Settings).
    public var summary: String {
        switch self {
        case .sartgNewYear: return L("1. ledna 08–11 UTC · RST + číslo + jméno + přání v rodném jazyce")
        case .arrlRoundup: return L("1. celý víkend v lednu · RST + číslo (W/VE stát)")
        case .proDigi: return L("3. celý víkend v lednu · RST + číslo (člen + „M“)")
        case .bartgSprint: return L("4. celý víkend v lednu · jen pořadové číslo")
        case .mexicoRTTY: return L("1. celý víkend v únoru · RST + číslo (XE stát)")
        case .cqwpxRTTY: return L("2. celý víkend v únoru · RST + číslo")
        case .naqpRTTY: return L("poslední sobota v únoru a 3. celý víkend v červenci · jméno (+ stát v Severní Americe)")
        case .naSprintRTTY: return L("neděle po 2. sobotě v březnu a po 3. sobotě v září 00–04 UTC · číslo + jméno + QTH")
        case .ybDX: return L("2. sobota v březnu · RST + číslo")
        case .bartgHF: return L("3. celý víkend v březnu · RST + číslo + čas")
        case .eaRTTY: return L("1. celý víkend v dubnu · RST + číslo (EA provincie)")
        case .igryWW: return L("2. celý víkend v dubnu · RST + rok první licence")
        case .bartgSprint75: return L("4. neděle v dubnu 17–21 UTC, 75 Bd · jen pořadové číslo")
        case .spDX: return L("4. celý víkend v dubnu · RST + číslo (SP: powiat)")
        case .voltaRTTY: return L("2. celý víkend v květnu · RST + číslo + CQ zóna")
        case .sartgRTTY: return L("3. celý víkend v srpnu · RST + číslo, tři etapy")
        case .rookieRoundup: return L("neděle 3. celého víkendu v srpnu · jméno + rok licence + QTH")
        case .russianRTTY: return L("1. celý víkend v září · RST + číslo (RU oblast)")
        case .cqwwRTTY: return L("poslední celý víkend v září · RST + CQ zóna (W/VE + stát)")
        case .urcDX: return L("1. pátek v říjnu · RST + kód teritoria (OK1 BHE, OK2 MOR)")
        case .russianDigi: return L("1. sobota v říjnu 12 UTC · RST + číslo (RU oblast)")
        case .makrothen: return L("2. celý víkend v říjnu · RST + lokátor (4 znaky), tři etapy")
        case .darcSprint: return L("2. úterý v lednu, dubnu, červenci a říjnu 18:00–19:30 UTC · RST + číslo (DL: DOK)")
        case .jartsRTTY: return L("3. celý víkend v říjnu · RST + věk operátora (00/01/99)")
        case .waeRTTY: return L("2. celý víkend v listopadu · RST + číslo, QTC")
        case .trcDigi: return L("2. celý víkend v prosinci · RST + číslo (člen + „TRC“)")
        case .okDXRTTY: return L("3. celý víkend v prosinci · RST + CQ zóna")
        case .wrt: return L("každý pátek 01:45–02:15 UTC · jméno + stát/země")
        }
    }

    /// The preset matching the settings (by name and format); nil = custom settings.
    public static func matching(_ c: ContestSettings) -> ContestPreset? {
        allCases.first { ($0.cabrilloName == c.name || $0.formerCabrilloNames.contains(c.name)) && $0.format == c.format }
    }
    /// Names used by older versions (an older settings file without the preset field).
    var formerCabrilloNames: [String] {
        switch self {
        case .waeRTTY: return ["WAEDC"]
        case .jartsRTTY: return ["JARTS-WW-RTTY"]
        default: return []
        }
    }
}
