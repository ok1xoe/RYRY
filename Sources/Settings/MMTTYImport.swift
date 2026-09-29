// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
// Import nastavení z Windows MMTTY (Mmtty.ini). Sekce a klíče podle TMmttyWd::ReadRegister / WriteRegister
// (MMTTY Main.cpp), escapování maker podle Yen2CrLf / CrLf2Yen (ComLib.cpp). Čistý parser bez vedlejších účinků.
import Foundation
import Localization
import ModemKit

// MARK: INI

/// Minimální parser INI jako TMemIniFile: `[sekce]`, `klíč=hodnota`, komentáře `;`.
/// Jména sekcí a klíčů nerozlišují velikost písmen; sekce se stejným jménem se sloučí,
/// u duplicitního klíče platí první výskyt (jako `ReadString`).
public struct INIFile: Sendable {
    public struct Entry: Sendable, Equatable { public var section: String, key: String, value: String }
    public private(set) var entries: [Entry] = []
    public private(set) var duplicateKeys = 0
    /// Neprázdné řádky, které nejsou komentář, sekce ani `klíč=hodnota` uvnitř sekce.
    public private(set) var ignoredLines = 0
    private var index: [String: Int] = [:]
    private var sections: Set<String> = []

    static func id(_ section: String, _ key: String) -> String { section.lowercased() + "\u{1}" + key.lowercased() }

    public init(text: String) {
        var current: String?
        let clean = text.replacingOccurrences(of: "\u{0}", with: "")
        for raw in clean.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") {
                guard let close = line.firstIndex(of: "]") else { ignoredLines += 1; continue }
                let name = line[line.index(after: line.startIndex)..<close].trimmingCharacters(in: .whitespaces)
                if name.isEmpty { ignoredLines += 1; continue }
                current = name; sections.insert(name.lowercased()); continue
            }
            guard let section = current, let eq = line.firstIndex(of: "=") else { ignoredLines += 1; continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            if key.isEmpty { ignoredLines += 1; continue }
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let k = Self.id(section, key)
            if index[k] != nil { duplicateKeys += 1; continue }
            index[k] = entries.count
            entries.append(Entry(section: section, key: key, value: value))
        }
    }

    public func value(_ section: String, _ key: String) -> String? {
        index[Self.id(section, key)].map { entries[$0].value }
    }
    public func hasSection(_ name: String) -> Bool { sections.contains(name.lowercased()) }
}

// MARK: Výsledek

/// Co se z importu přepíše.
public struct MMTTYImportOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let macros = MMTTYImportOptions(rawValue: 1)
    public static let messages = MMTTYImportOptions(rawValue: 2)
    public static let station = MMTTYImportOptions(rawValue: 4)
    public static let modem = MMTTYImportOptions(rawValue: 8)
    public static let shortcuts = MMTTYImportOptions(rawValue: 16)
    public static let all: MMTTYImportOptions = [.macros, .messages, .station, .modem, .shortcuts]
}

public struct MMTTYImportResult: Sendable, Equatable {
    /// 16 maker (`AppSettings.macroCount`), nil = soubor makra neobsahuje.
    public var macros: [Macro]?
    /// Seznam zpráv (MsgList), nil = žádné zprávy.
    public var messages: [Macro]?
    /// Jen `call` (MMTTY jméno, QTH ani lokátor stanice neukládá), nil = nevyplněno nebo NOCALL.
    public var station: Station?
    /// Parametry modemu podle `ParameterDescriptor.id`, už ve správném typu.
    public var rtty: [String: ParameterValue] = [:]
    /// Vlastní klávesové zkratky (id příkazu → zkratka), jen ty, které lze na macOS použít.
    public var shortcuts: [String: KeyBinding] = [:]
    public var warnings: [String] = []
    /// Kolik klíčů souboru nemá v mmtty4mac protějšek (okna, písma, TNC, …).
    public var ignoredKeyCount = 0

    public init() {}
    public var isEmpty: Bool { macros == nil && messages == nil && station == nil && rtty.isEmpty && shortcuts.isEmpty }

    /// Zapíše vybrané části do nastavení (čistá funkce; ukládání a aplikace do běžícího modemu řeší AppModel).
    public func apply(to s: inout AppSettings, options: MMTTYImportOptions) {
        if options.contains(.macros), let macros { s.macros = macros }
        if options.contains(.messages), let messages { s.messages = messages }
        if options.contains(.station), let station { s.station.call = station.call }
        if options.contains(.modem) { for (k, v) in rtty { s.rtty[k] = v } }
        if options.contains(.shortcuts) {
            for (id, b) in shortcuts {
                guard let c = ShortcutCommand.allCases.first(where: { $0.id == id }) else { continue }
                s.shortcuts[id] = b == c.defaultBinding ? nil : b
            }
        }
    }
}

// MARK: Import

public enum MMTTYImport {
    /// Bajty souboru → text. Platné UTF-8 se nemění (včetně BOM), jinak se každý bajt ≥ 0x80 nahradí „?“
    /// (Shift-JIS / Windows-1250 – v makrech RTTY stačí ASCII).
    public static func decode(_ data: Data) -> (text: String, replaced: Int) {
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        if let s = String(data: d, encoding: .utf8) { return (s, 0) }
        var out = "", n = 0
        for b in d {
            if b < 0x80 { out.unicodeScalars.append(Unicode.Scalar(b)) } else { out.append("?"); n += 1 }
        }
        return (out, n)
    }

    /// Hodnota z ini → text makra (MMTTY Yen2CrLf): volitelná úvodní `"`, `\r` `\n` `\\`,
    /// jiná escape sekvence = znak bez zpětného lomítka, koncová `"` se zahodí.
    public static func unescape(_ s: String) -> String {
        var out = ""
        let c = Array(s)
        var i = 0
        let quoted = c.first == "\""
        if quoted { i = 1 }
        while i < c.count {
            let ch = c[i]
            if ch == "\\" {
                guard i + 1 < c.count else { break }
                i += 1
                switch c[i] {
                case "r": out.append("\r")
                case "n": out.append("\n")
                default: out.append(c[i])
                }
            } else if !quoted || ch != "\"" || i + 1 < c.count {
                out.append(ch)
            }
            i += 1
        }
        return out
    }

    /// Text makra MMTTY → mmtty4mac. Syntaxe (`%c`, `\` na začátku a konci, `#`, `%{…}`) je stejná;
    /// řídicí znaky MMTTY `_ ~ [ ]` (mark, nosná vyp., diddle) jádro nevysílá, proto se mimo CW ID `%{…}` odstraní.
    public static func convertMacroText(_ s: String, removed: inout Int) -> String {
        var out = "", inCW = false
        let c = Array(s)
        var i = 0
        while i < c.count {
            let ch = c[i]
            if inCW {
                out.append(ch); if ch == "}" { inCW = false }
            } else if ch == "%", i + 1 < c.count, c[i + 1] == "{" {
                out.append("%{"); inCW = true; i += 1
            } else if "_~[]".contains(ch) {
                removed += 1
            } else {
                out.append(ch)
            }
            i += 1
        }
        return out
    }
    public static func convertMacroText(_ s: String) -> String { var n = 0; return convertMacroText(s, removed: &n) }

    public static func parse(data: Data, descriptors: [ParameterDescriptor] = []) -> MMTTYImportResult {
        let (text, replaced) = decode(data)
        var r = parse(text: text, descriptors: descriptors)
        if replaced > 0 { r.warnings.append(L("Znaky mimo ASCII (%ld) nahrazeny „?“.", replaced)) }
        return r
    }

    // MARK: parametry modemu

    private enum Kind { case bool, int, double, choice([String]) }
    /// Klíče sekce [Define] → id parametru modemu (RTTYParameters). Mark/shift se řeší zvlášť.
    private static let table: [(key: String, id: String, kind: Kind)] = [
        ("BaudRate", "baud", .double), ("Rev", "reverse", .bool),
        ("AFC", "afc", .bool), ("AFCFixShift", "afcMode", .choice(["free", "fixed", "ham", "fsk"])),
        ("AFCSQ", "afcSquelch", .double), ("AFCTime", "afcTime", .double), ("AFCSweep", "afcSweep", .double),
        ("TxNet", "net", .bool), ("ATC", "atc", .bool),
        ("SQ", "squelch", .bool), ("SQLevel", "squelchLevel", .double),
        ("DEMTYPE", "demodType", .choice(["iir", "fir", "pll", "fft"])),
        ("IIRBW", "iirBandwidth", .double), ("Tap", "firTaps", .int),
        ("SmoozType", "integrator", .choice(["average", "lpf"])), ("Smooz", "smoothFreq", .double),
        ("SmoozIIR", "lpfFreq", .double), ("SmoozOrder", "lpfOrder", .int),
        ("Majority", "majority", .bool), ("IgnoreFreamError", "ignoreFraming", .bool),
        ("LimitAGC", "limiterAGC", .bool), ("LimitOverSampling", "limiterOversampling", .bool),
        ("UOS", "uos", .bool), ("Diddle", "diddle", .choice(["off", "blk", "ltr"])), ("TXLoop", "echo", .int),
        ("OutputGain", "txGain", .double),
        ("TXBPF", "txBPF", .bool), ("TXLPF", "txLPF", .bool), ("TXLPFFreq", "txLPFFreq", .double),
        ("TXCharWait", "charWait", .int), ("TXCharWaitDiddle", "charWaitDiddle", .bool),
        ("TXRandomDiddle", "randomDiddle", .bool),
        ("RXBPF", "bpf", .bool), ("RXBPFFW", "bpfWidth", .double),
        ("RXlms", "lms", .bool), ("RXlmsDelay", "lmsDelay", .int), ("RXlmsMU2", "lmsMu2", .double),
        ("RXlmsGM", "lmsGamma", .double), ("RXlmsAGC", "lmsAGC", .bool), ("RXlmsInv", "lmsInvert", .bool),
        ("RXlmsTAP", "lmsTaps", .int), ("RXNotchTAP", "notchTaps", .int), ("RXlmsBPF", "lmsBPF", .bool),
        ("RXlmsType", "lmsType", .choice(["lms", "notch"])), ("RXlmsNotch", "notchFreq", .int),
        ("RXlmsNotch2", "notch2Freq", .int), ("RXlmsTwoNotch", "twoNotch", .bool),
        ("pllVcoGain", "pllVcoGain", .double), ("pllLoopOrder", "pllLoopOrder", .int), ("pllLoopFC", "pllLoopFc", .double),
        ("pllOutOrder", "pllOutOrder", .int), ("pllOutFC", "pllOutFc", .double),
    ]

    // MARK: zkratky

    /// SysKey: index výčtu kk… v ComLib.h (klíč `S<index+1>`) → příkaz mmtty4mac, výchozí kód MMTTY se nepřenáší.
    private static let sysKeys: [(index: Int, id: String, mmttyDefault: Int)] = [
        (3, "openLog", 0), (24, "toggleTx", 0x78), (25, "rxNow", 0x77), (58, "clearRx", 0),
    ]
    /// ⌘ + písmeno, které v macOS/menu aplikace už něco dělá.
    private static let reservedLetters: Set<String> = ["q", "w", "h", "m", "n", "o", "c", "v", "x", "a", "z", "s", "p"]

    private enum KeyConversion { case ok(KeyBinding), unsupported, reserved }

    /// Kód klávesy MMTTY (KEYTBL v ComLib.cpp): dolních 8 bitů = VK, 0x100 Ctrl, 0x200 Alt, 0x400 Shift.
    /// Ctrl → ⌘ (zvyk při přenosu z Windows), Alt → ⌥, Shift → ⇧.
    private static func convertKey(_ code: Int) -> KeyConversion {
        guard code > 0, code < 0x800 else { return .unsupported }
        let vk = code & 0xFF
        var mods: [KeyBinding.Modifier] = []
        if code & 0x100 != 0 { mods.append(.command) }
        if code & 0x200 != 0 { mods.append(.option) }
        if code & 0x400 != 0 { mods.append(.shift) }
        let key: String
        switch vk {
        case 0x70...0x7B: key = "f\(vk - 0x6F)"
        case 0x30...0x39, 0x41...0x5A: key = String(Character(Unicode.Scalar(UInt8(vk)))).lowercased()
        case 0x25: key = "left"
        case 0x26: key = "up"
        case 0x27: key = "right"
        case 0x28: key = "down"
        case 0x1B: key = "escape"
        case 0x2E: key = "delete"
        default: return .unsupported
        }
        let b = KeyBinding(key: key, modifiers: mods)
        guard b.isValid, !b.isNone else { return .unsupported }
        if b.modifiers == [.command], reservedLetters.contains(b.key) { return .reserved }
        return .ok(b)
    }

    // MARK: parse

    public static func parse(text: String, descriptors: [ParameterDescriptor] = []) -> MMTTYImportResult {
        let ini = INIFile(text: text)
        var r = MMTTYImportResult()
        var consumed = Set<String>()
        func get(_ section: String, _ key: String) -> String? {
            let v = ini.value(section, key)
            if v != nil { consumed.insert(INIFile.id(section, key)) }
            return v
        }
        func number(_ section: String, _ key: String) -> Double? {
            guard let s = get(section, key), let d = Double(s), d.isFinite else { return nil }
            return d
        }
        var controlChars = 0

        // makra: 16 tlačítek
        if ini.hasSection("Macro") || ini.hasSection("MacroName") {
            var list: [Macro] = []
            for i in 1...AppSettings.macroCount {
                let k = "M\(i)"
                var name = get("MacroName", k) ?? ""
                let raw = get("Macro", k).map { convertMacroText(unescape($0), removed: &controlChars) } ?? ""
                if raw.isEmpty && name == k { name = "" }                     // zástupné jméno MMTTY prázdného tlačítka
                var timer: Double?
                if let t = number("MacroTimer", k), t > 0 { timer = t / 10 }  // MMTTY: násobky 0,1 s
                var color: String?
                if let c = number("MacroCol", k), c > 0, c <= 16_777_215 {
                    let v = Int(c)                                           // TColor = 0x00BBGGRR
                    color = String(format: "#%02X%02X%02X", v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF)
                }
                list.append(Macro(name: name, text: raw, repeatSeconds: timer, color: color))
            }
            r.macros = list
        }

        // zprávy: MsgName + MsgList, seznam končí prvním prázdným jménem / textem (jako ReadRegister)
        if ini.hasSection("MsgName") || ini.hasSection("MsgList") {
            var list: [Macro] = []
            for i in 1...64 {
                let k = "M\(i)"
                guard let name = get("MsgName", k), !name.isEmpty else { break }
                guard let raw = get("MsgList", k), !raw.isEmpty else { break }
                list.append(Macro(name: name, text: convertMacroText(unescape(raw), removed: &controlChars)))
            }
            r.messages = list.isEmpty ? nil : list
        }
        if controlChars > 0 {
            r.warnings.append(L("Makra a zprávy obsahovala řídicí znaky MMTTY _ ~ [ ] (%ld), které mmtty4mac nevysílá; odstraněny.", controlChars))
        }

        // stanice: MMTTY ukládá jen značku
        if let call = get("Define", "Call")?.trimmingCharacters(in: .whitespaces).uppercased(),
           !call.isEmpty, call != "NOCALL" {
            var st = Station(); st.call = call; r.station = st
        }

        // parametry modemu
        let byID = Dictionary(descriptors.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func accept(_ id: String, _ v: ParameterValue) {
            if !descriptors.isEmpty {
                guard let d = byID[id], let ok = try? d.validate(v) else {
                    r.warnings.append(L("Parametr %@ má hodnotu mimo povolený rozsah; přeskočeno.", id)); return
                }
                r.rtty[id] = ok
            } else { r.rtty[id] = v }
        }
        for p in table {
            guard let d = number("Define", p.key) else { continue }
            switch p.kind {
            case .bool: accept(p.id, .bool(d != 0))
            case .int: accept(p.id, .int(Int(d.rounded())))
            case .double: accept(p.id, .double(d))
            case .choice(let names):
                let i = Int(d.rounded())
                if names.indices.contains(i) { accept(p.id, .string(names[i])) }
                else { r.warnings.append(L("Parametr %@ má hodnotu mimo povolený rozsah; přeskočeno.", p.id)) }
            }
        }
        let mark = number("Define", "MarkFreq"), space = number("Define", "SpaceFreq")
        if let mark { accept("mark", .double(mark)) }
        if let mark, let space {
            let shift = ((space - mark) * 1e6).rounded() / 1e6
            if shift > 0 { accept("shift", .double(shift)) }
            else { r.warnings.append(L("Parametr %@ má hodnotu mimo povolený rozsah; přeskočeno.", "shift")) }
        }

        // PTT / FSK: port COMx nemá na macOS protějšek, nastavuje se ručně
        let ptt = get("Define", "PTT")?.trimmingCharacters(in: .whitespaces) ?? ""
        let txPort = Int(number("Define", "TxPort") ?? 0)
        _ = get("Define", "InvPTT")
        if !ptt.isEmpty, ptt.uppercased() != "NONE" {
            r.warnings.append(txPort == 0
                ? L("PTT na portu %@ nelze převést (porty COM na macOS neexistují); zvolte port v Nastavení → PTT.", ptt)
                : L("FSK/PTT na portu %@ nelze převést (porty COM na macOS neexistují); zvolte port v Nastavení → FSK.", ptt))
        }

        // klávesové zkratky: makra (MacroKey) a vybrané systémové (SysKey)
        var unsupported: [String] = [], reserved: [String] = []
        func shortcut(_ id: String, section: String, key: String, skip: Int = 0) {
            guard let d = number(section, key), Int(d) != 0, Int(d) != skip else { return }
            switch convertKey(Int(d)) {
            case .ok(let b): r.shortcuts[id] = b
            case .unsupported: unsupported.append("\(key) (0x" + String(Int(d), radix: 16, uppercase: true) + ")")
            case .reserved: reserved.append("\(key) (0x" + String(Int(d), radix: 16, uppercase: true) + ")")
            }
        }
        for i in 1...AppSettings.macroCount { shortcut("macro.\(i - 1)", section: "MacroKey", key: "M\(i)") }
        for s in sysKeys { shortcut(s.id, section: "SysKey", key: "S\(s.index + 1)", skip: s.mmttyDefault) }
        if !unsupported.isEmpty {
            r.warnings.append(L("Zkratky bez protějšku na macOS: %@.", unsupported.joined(separator: ", ")))
        }
        if !reserved.isEmpty {
            r.warnings.append(L("Zkratky kolidující s menu macOS nebyly převzaty: %@.", reserved.joined(separator: ", ")))
        }
        if !r.shortcuts.isEmpty {
            var probe = AppSettings(); probe.shortcuts = r.shortcuts
            let n = probe.conflictingShortcuts().count
            if n > 0 { r.warnings.append(L("Po importu se %ld zkratek kryje s jinou; upravte je v Nastavení → Zkratky.", n)) }
        }

        // shrnutí
        if consumed.isEmpty {
            r.warnings.append(L("Soubor nevypadá jako Mmtty.ini z MMTTY – nenalezeno žádné známé nastavení."))
        }
        r.ignoredKeyCount = ini.entries.filter { !consumed.contains(INIFile.id($0.section, $0.key)) }.count
        if r.ignoredKeyCount > 0 {
            r.warnings.append(L("Ignorováno %ld nastavení bez protějšku v mmtty4mac (okna, písma, barvy, TNC, log…).", r.ignoredKeyCount))
        }
        if ini.duplicateKeys > 0 { r.warnings.append(L("Duplicitní klíče v souboru: %ld (platí první).", ini.duplicateKeys)) }
        if ini.ignoredLines > 0 { r.warnings.append(L("Nepochopené řádky v souboru: %ld.", ini.ignoredLines)) }
        return r
    }
}
