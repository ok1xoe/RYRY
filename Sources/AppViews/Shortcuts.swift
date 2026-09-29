// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import Settings
import SwiftUI

extension KeyBinding {
    /// Klávesa pro SwiftUI (nil = bez zkratky).
    var keyEquivalent: KeyEquivalent? {
        if isNone { return nil }
        if key.hasPrefix("f"), let n = Int(key.dropFirst()), (1...20).contains(n) {
            return KeyEquivalent(Character(UnicodeScalar(NSF1FunctionKey + n - 1)!))
        }
        switch key {
        case "space": return .space
        case "return": return .return
        case "escape": return .escape
        case "tab": return .tab
        case "delete": return .delete
        case "up": return .upArrow
        case "down": return .downArrow
        case "left": return .leftArrow
        case "right": return .rightArrow
        default: return key.count == 1 ? KeyEquivalent(key.first!) : nil
        }
    }

    var eventModifiers: EventModifiers {
        var m: EventModifiers = []
        for x in modifiers {
            switch x {
            case .command: m.insert(.command)
            case .shift: m.insert(.shift)
            case .option: m.insert(.option)
            case .control: m.insert(.control)
            }
        }
        return m
    }

    /// Zkratka z události klávesnice (záznam v Nastavení); nil = nepoužitelná klávesa.
    static func from(_ e: NSEvent) -> KeyBinding? {
        var mods: [Modifier] = []
        let f = e.modifierFlags
        if f.contains(.command) { mods.append(.command) }
        if f.contains(.shift) { mods.append(.shift) }
        if f.contains(.option) { mods.append(.option) }
        if f.contains(.control) { mods.append(.control) }
        let key: String
        switch Int(e.keyCode) {
        case 49: key = "space"
        case 36, 76: key = "return"
        case 53: key = "escape"
        case 48: key = "tab"
        case 51, 117: key = "delete"
        case 126: key = "up"
        case 125: key = "down"
        case 123: key = "left"
        case 124: key = "right"
        default:
            if let s = e.charactersIgnoringModifiers?.unicodeScalars.first,
               (NSF1FunctionKey...NSF20FunctionKey).contains(Int(s.value)) {
                key = "f\(Int(s.value) - NSF1FunctionKey + 1)"
            } else if let c = e.charactersIgnoringModifiers?.lowercased(), c.count == 1 {
                key = c
            } else { return nil }
        }
        let b = KeyBinding(key: key, modifiers: mods)
        return b.isValid ? b : nil
    }
}

extension View {
    /// Klávesová zkratka z nastavení (žádná = bez zkratky).
    @ViewBuilder public func shortcut(_ b: KeyBinding) -> some View {
        if let k = b.keyEquivalent { keyboardShortcut(k, modifiers: b.eventModifiers) } else { self }
    }

    /// Bublinová nápověda, kterou lze v Nastavení vypnout (MMTTY „Show Button Hint“).
    public func hint(_ text: String) -> some View { modifier(HintModifier(text: text)) }
}

private struct ShowHintsKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    public var showHints: Bool {
        get { self[ShowHintsKey.self] }
        set { self[ShowHintsKey.self] = newValue }
    }
}

struct HintModifier: ViewModifier {
    let text: String
    @Environment(\.showHints) private var show
    func body(content: Content) -> some View {
        if show { content.help(text) } else { content }
    }
}
