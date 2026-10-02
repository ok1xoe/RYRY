// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation

/// Operating outside a contest – picks the macro set (normal QSOs or short DX/pile-up QSOs).
public enum OperatingMode: String, Codable, Sendable, CaseIterable { case normal, dx }

/// Macro sets: one for normal operating, one for DX and one for each contest (preset or custom). The active set is
/// `AppSettings.macros`; switching the contest or the operating mode stores it and loads the other one
/// (`switchingMacroSet`). The slot layout follows the ESM defaults (F1 CQ, F4 exchange, F5 TU, F11 AGN, ⇧F3 my call).
extension AppSettings {
    public static let normalMacroSetKey = "normal"
    public static let dxMacroSetKey = "dx"

    /// The key of the set that belongs to the current settings.
    public var activeMacroSetKey: String {
        guard contest.enabled else { return operatingMode == .dx ? Self.dxMacroSetKey : Self.normalMacroSetKey }
        return "contest." + (contest.selectedPreset?.rawValue ?? "custom")
    }

    /// The settings with `macros` stored under `previousKey` and the set of the current key loaded (stored or default).
    public func switchingMacroSet(from previousKey: String) -> AppSettings {
        var s = self
        let key = activeMacroSetKey
        guard key != previousKey else { return s }
        s.macroSets[previousKey] = macros
        s.macros = macroSets[key] ?? Self.defaultMacroSet(key)
        return s
    }

    /// The active set replaced by its defaults (and stored).
    public mutating func resetActiveMacroSet() {
        macros = Self.defaultMacroSet(activeMacroSetKey)
        macroSets[activeMacroSetKey] = macros
    }

    /// The default set of a key ("normal", "dx", "contest.<preset>", "contest.custom").
    public static func defaultMacroSet(_ key: String) -> [Macro] {
        switch key {
        case normalMacroSetKey: return defaultMacros
        case dxMacroSetKey: return dxMacros
        default:
            let raw = key.hasPrefix("contest.") ? String(key.dropFirst("contest.".count)) : ""
            return contestMacros(ContestPreset(rawValue: raw))
        }
    }

    /// 16 macros (a shorter list is filled with empty ones).
    static func padded(_ m: [Macro]) -> [Macro] {
        var list = Array(m.prefix(macroCount))
        while list.count < macroCount { list.append(Macro(name: "", text: "")) }
        return list
    }

    /// DX and pile-ups: short reports, TU and QRZ.
    public static let dxMacros: [Macro] = padded([
        Macro(name: "CQ DX", text: "\r\nCQ DX CQ DX DE %m %m %m DX K\r\n\\"),
        Macro(name: "Answer", text: "\r\n%c DE %m %m K\r\n\\"),
        Macro(name: "Report", text: "\r\n%c DE %m UR 599 599 TU\r\n\\"),
        Macro(name: "599 TU", text: "\r\n%c 599 599 TU\r\n\\"),
        Macro(name: "TU QRZ", text: "\r\nTU 73 %m QRZ?\r\n%l\\"),
        Macro(name: "73", text: "\r\n%c DE %m TNX 73 SK\r\n%l\\"),
        Macro(name: "QRZ", text: "\r\nQRZ? DE %m K\r\n\\"),
        Macro(name: "BTU", text: "\r\nBTU %c DE %m KN\r\n\\"),
        Macro(name: "RYRY", text: "RYRYRYRYRYRYRYRYRYRY\r\n#"),
        Macro(name: "CW ID", text: "%{DE %m}\\"),
        Macro(name: "AGN", text: "\r\nAGN? AGN?\r\n\\"),
        Macro(name: "Call?", text: "\r\n%c? %c?\r\n\\"),
        Macro(name: "CQ UP", text: "\r\nCQ DX DE %m %m UP\r\n\\"),
        Macro(name: "QSL TU", text: "\r\nQSL TU %c 599 599\r\n\\"),
        Macro(name: "My call", text: "\r\n%m %m\r\n\\"),
    ])

    /// A contest set built from the exchange: %N = what this contest sends after the RST ("001", "BHE", "015 TOMAS DX"),
    /// the RST written in the macro only where the contest has one; BARTG HF %x %y (number and time). The calls go around
    /// the exchange as usual on RTTY ("DL1ABC 599 BHE BHE DL1ABC").
    public static func contestMacros(_ p: ContestPreset?) -> [Macro] {
        let sprint = p == .naSprintRTTY
        let test = p == .waeRTTY ? "WAE" : sprint ? "NA" : "TEST"
        let rst = p?.sendsRST ?? true ? "599 " : ""
        let x = p == .bartgHF ? "%x %y" : "%N"                         // one copy of the exchange
        // NA Sprint: the station that moves sends both calls first, the one staying on the frequency its own call last
        let runExch = sprint ? "%c %m \(x)" : "%c \(rst)\(x) \(x) %c"
        let spExch = sprint ? "%c \(x) %m" : "%c TU \(rst)\(x) \(x) %m"
        let ask = p == nil || p?.format == .serial || p?.format == .serialText || p?.format == .wae || p?.format == .bartg
            ? "NR?" : "EXCH?"
        func m(_ name: String, _ body: String, log: Bool = false) -> Macro {
            Macro(name: name, text: "\r\n" + body + (log ? "\r\n%l\\" : "\r\n\\"))
        }
        return padded([
            m("CQ", "CQ \(test) CQ \(test) DE %m %m \(test)"),
            m("Answer", "%c DE %m %m"),
            m("TU Exch", spExch),
            m("Exch", runExch),
            m("TU", sprint ? "%c TU %m" : "%c TU %m \(test)", log: true),
            m("Exch ×1", "%c \(rst)\(x)"),
            m("QRZ", "QRZ? DE %m \(test)"),
            m("Call?", "%c? %c? DE %m"),
            Macro(name: "RYRY", text: "RYRYRYRYRYRYRYRYRYRY\r\n#"),
            Macro(name: "CW ID", text: "%{DE %m}\\"),
            m("AGN", "%c AGN AGN"),
            m(ask, "%c \(ask) \(ask)"),
            m("Call ×2", "%c %c"),
            m("Exch ×3", "%c \(rst)\(x) \(x) \(x) %c"),
            m("My call", "%m %m"),
        ])
    }
}
