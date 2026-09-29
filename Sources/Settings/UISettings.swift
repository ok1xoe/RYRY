// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Volby okna vysílání (MMTTY „Auto send CR/LF with TX button“, „Word wrap on keyboard“).
public struct TxWindowSettings: Codable, Sendable, Equatable {
    /// Při přepnutí na TX tlačítkem nejdřív odvysílat CR LF.
    public var autoCRLF = false
    /// Zalomit psaný text na tomto sloupci (0 = nezalamovat).
    public var wrapColumn = 0
    public static let wrapRange = 20...200
    public init() {}
    enum CodingKeys: String, CodingKey { case autoCRLF, wrapColumn }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "txWindow", x = TxWindowSettings()
        autoCRLF = c.tolerant(.autoCRLF, x.autoCRLF, w, s)
        let col = c.tolerant(.wrapColumn, x.wrapColumn, w, s)
        wrapColumn = Self.wrapRange.contains(col) ? col : 0
    }
}

/// Barevná paleta vodopádu.
public enum WaterfallPalette: String, Codable, Sendable, CaseIterable { case classic, gray, heat, green, blue }
/// Odezva (vyhlazení) čárového spektra – MMTTY „FFT Response“.
public enum FFTResponse: String, Codable, Sendable, CaseIterable {
    case fast, normal, slow
    /// Váha předchozí hodnoty při doznívání (0 = okamžitě).
    public var decay: Float { switch self { case .fast: 0.3; case .normal: 0.6; case .slow: 0.85 } }
}
/// Velikost XY scope (MMTTY „XYScope Size“).
public enum XYScopeSize: String, Codable, Sendable, CaseIterable {
    case small, medium, large
    public var points: Double { switch self { case .small: 100; case .medium: 160; case .large: 240 } }
}
/// Kvalita XY scope (MMTTY „XYScope Quality“): nízká = každý druhý bod.
public enum XYScopeQuality: String, Codable, Sendable, CaseIterable { case low, high }

/// Klávesová zkratka: klávesa („f1“…„f20“, jeden znak, „space“, „return“, „escape“, „tab“, „delete“, šipky)
/// a modifikátory. Klávesa „none“ = příkaz bez zkratky.
public struct KeyBinding: Codable, Sendable, Hashable {
    public enum Modifier: String, Codable, Sendable, CaseIterable, Comparable {
        case control, option, shift, command                  // pořadí symbolů jako v menu macOS ⌃⌥⇧⌘
        public static func < (a: Self, b: Self) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
        public var symbol: String { switch self { case .control: "⌃"; case .option: "⌥"; case .shift: "⇧"; case .command: "⌘" } }
    }
    public var key: String
    public var modifiers: [Modifier]

    public init(key: String, modifiers: [Modifier] = []) {
        self.key = key.lowercased(); self.modifiers = Array(Set(modifiers)).sorted()
    }
    public static let none = KeyBinding(key: "none")
    public var isNone: Bool { key == "none" }

    static let named: [String: String] = ["space": "Space", "return": "↩", "escape": "Esc", "tab": "⇥", "delete": "⌫",
                                          "up": "↑", "down": "↓", "left": "←", "right": "→"]
    public var isValid: Bool {
        if isNone { return true }
        if key.hasPrefix("f"), let n = Int(key.dropFirst()), (1...20).contains(n) { return true }
        if Self.named[key] != nil { return !modifiers.isEmpty }        // Space, Return, šipky… by kolidovaly s psaním
        guard key.count == 1, let ch = key.first, !ch.isWhitespace, !ch.isNewline else { return false }
        return !modifiers.isEmpty                               // samotné písmeno by kolidovalo s psaním textu
    }

    /// Zobrazení jako v menu: „⌥⌘1“, „⇧F2“.
    public var display: String {
        if isNone { return "—" }
        let k = key.hasPrefix("f") && key.count > 1 ? key.uppercased() : (Self.named[key] ?? key.uppercased())
        return modifiers.map(\.symbol).joined() + k
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.init(key: try c.decode(String.self, forKey: .key),
                  modifiers: (try? c.decode([Modifier].self, forKey: .modifiers)) ?? [])
    }
}

/// Příkazy, kterým lze přiřadit zkratku (MMTTY „Assign ShortCut Keys“).
public enum ShortcutCommand: Hashable, Sendable, CaseIterable {
    case macro(Int), toggleTx, rxNow, tune, logQSO, clearQSO, clearRx, stopMacro, openLog
    public static var allCases: [ShortcutCommand] {
        (0..<AppSettings.macroCount).map { .macro($0) } + [.toggleTx, .rxNow, .tune, .logQSO, .clearQSO, .clearRx, .stopMacro, .openLog]
    }
    public var id: String {
        switch self {
        case .macro(let i): "macro.\(i)"
        case .toggleTx: "toggleTx"; case .rxNow: "rxNow"; case .tune: "tune"; case .logQSO: "logQSO"
        case .clearQSO: "clearQSO"; case .clearRx: "clearRx"; case .stopMacro: "stopMacro"; case .openLog: "openLog"
        }
    }
    /// Výchozí zkratky (dosavadní pevné): F1–F12, ⇧F1–⇧F4, ⌘T, ⌘., ⌘L, ⌘K, ⇧⌘L.
    public var defaultBinding: KeyBinding {
        switch self {
        case .macro(let i): i < 12 ? KeyBinding(key: "f\(i + 1)") : KeyBinding(key: "f\(i - 11)", modifiers: [.shift])
        case .toggleTx: KeyBinding(key: "t", modifiers: [.command])
        case .rxNow: KeyBinding(key: ".", modifiers: [.command])
        case .logQSO: KeyBinding(key: "l", modifiers: [.command])
        case .clearRx: KeyBinding(key: "k", modifiers: [.command])
        case .openLog: KeyBinding(key: "l", modifiers: [.command, .shift])
        case .tune, .clearQSO, .stopMacro: .none
        }
    }
}

extension AppSettings {
    /// Platná zkratka příkazu (vlastní, jinak výchozí).
    public func binding(for c: ShortcutCommand) -> KeyBinding { shortcuts[c.id] ?? c.defaultBinding }

    /// Příkazy se stejnou zkratkou (pro varování v Nastavení).
    public func conflictingShortcuts() -> [[ShortcutCommand]] {
        var by: [KeyBinding: [ShortcutCommand]] = [:]
        for c in ShortcutCommand.allCases { let b = binding(for: c); if !b.isNone { by[b, default: []].append(c) } }
        return by.values.filter { $0.count > 1 }.sorted { $0[0].id < $1[0].id }
    }
}
