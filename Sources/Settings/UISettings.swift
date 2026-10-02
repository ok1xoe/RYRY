// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation

/// Transmit window options (MMTTY "Auto send CR/LF with TX button", "Word wrap on keyboard").
public struct TxWindowSettings: Codable, Sendable, Equatable {
    /// When switching to TX with the button, transmit CR LF first.
    public var autoCRLF = false
    /// Wrap the typed text at this column (0 = do not wrap).
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

/// Waterfall color palette.
public enum WaterfallPalette: String, Codable, Sendable, CaseIterable { case classic, gray, heat, green, blue }
/// Response (smoothing) of the line spectrum – MMTTY "FFT Response".
public enum FFTResponse: String, Codable, Sendable, CaseIterable {
    case fast, normal, slow
    /// Weight of the previous value while decaying (0 = immediately).
    public var decay: Float { switch self { case .fast: 0.3; case .normal: 0.6; case .slow: 0.85 } }
}
/// XY scope size (MMTTY "XYScope Size").
public enum XYScopeSize: String, Codable, Sendable, CaseIterable {
    case small, medium, large
    public var points: Double { switch self { case .small: 100; case .medium: 160; case .large: 240 } }
}
/// XY scope quality (MMTTY "XYScope Quality"): low = every other point.
public enum XYScopeQuality: String, Codable, Sendable, CaseIterable { case low, high }

/// Keyboard shortcut: a key ("f1"…"f20", a single character, "space", "return", "escape", "tab", "delete", arrows)
/// and modifiers. The key "none" = a command without a shortcut.
public struct KeyBinding: Codable, Sendable, Hashable {
    public enum Modifier: String, Codable, Sendable, CaseIterable, Comparable {
        case control, option, shift, command                  // symbol order as in the macOS menu ⌃⌥⇧⌘
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
        if Self.named[key] != nil { return !modifiers.isEmpty }        // Space, Return, arrows… would collide with typing
        guard key.count == 1, let ch = key.first, !ch.isWhitespace, !ch.isNewline else { return false }
        return !modifiers.isEmpty                               // a bare letter would collide with typing text
    }

    /// Display as in the menu: "⌥⌘1", "⇧F2".
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

/// Commands that can be assigned a shortcut (MMTTY "Assign ShortCut Keys").
public enum ShortcutCommand: Hashable, Sendable, CaseIterable {
    case macro(Int), toggleTx, rxNow, tune, logQSO, clearQSO, clearRx, stopMacro, openLog, esmMode, enterFrequency
    public static var allCases: [ShortcutCommand] {
        (0..<AppSettings.macroCount).map { .macro($0) } + [.toggleTx, .rxNow, .tune, .logQSO, .clearQSO, .clearRx, .stopMacro, .openLog, .esmMode, .enterFrequency]
    }
    public var id: String {
        switch self {
        case .macro(let i): "macro.\(i)"
        case .toggleTx: "toggleTx"; case .rxNow: "rxNow"; case .tune: "tune"; case .logQSO: "logQSO"
        case .clearQSO: "clearQSO"; case .clearRx: "clearRx"; case .stopMacro: "stopMacro"; case .openLog: "openLog"
        case .esmMode: "esmMode"
        case .enterFrequency: "enterFrequency"
        }
    }
    /// Default shortcuts (the existing fixed ones): F1–F12, ⇧F1–⇧F4, ⌘T, ⌘., ⌘L, ⌘K, ⇧⌘L; ⌃R toggles Run / S&P, ⌥⌘F frequency entry.
    public var defaultBinding: KeyBinding {
        switch self {
        case .macro(let i): i < 12 ? KeyBinding(key: "f\(i + 1)") : KeyBinding(key: "f\(i - 11)", modifiers: [.shift])
        case .toggleTx: KeyBinding(key: "t", modifiers: [.command])
        case .rxNow: KeyBinding(key: ".", modifiers: [.command])
        case .logQSO: KeyBinding(key: "l", modifiers: [.command])
        case .clearRx: KeyBinding(key: "k", modifiers: [.command])
        case .openLog: KeyBinding(key: "l", modifiers: [.command, .shift])
        case .esmMode: KeyBinding(key: "r", modifiers: [.control])
        case .enterFrequency: KeyBinding(key: "f", modifiers: [.option, .command])
        case .tune, .clearQSO, .stopMacro: .none
        }
    }
}

extension AppSettings {
    /// The valid shortcut of a command (custom, otherwise the default).
    public func binding(for c: ShortcutCommand) -> KeyBinding { shortcuts[c.id] ?? c.defaultBinding }

    /// The macro whose shortcut is exactly this key combination; nil = none.
    public func macro(for b: KeyBinding) -> Int? {
        (0..<AppSettings.macroCount).first { binding(for: .macro($0)) == b }
    }

    /// Commands with the same shortcut (for a warning in Settings).
    public func conflictingShortcuts() -> [[ShortcutCommand]] {
        var by: [KeyBinding: [ShortcutCommand]] = [:]
        for c in ShortcutCommand.allCases { let b = binding(for: c); if !b.isNone { by[b, default: []].append(c) } }
        return by.values.filter { $0.count > 1 }.sorted { $0[0].id < $1[0].id }
    }
}
