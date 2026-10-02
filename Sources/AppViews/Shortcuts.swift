// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppKit
import Settings
import SwiftUI

extension KeyBinding {
    /// The key for SwiftUI (nil = no shortcut).
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

    /// A shortcut from a keyboard event (recorded in Settings); nil = unusable key.
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
    /// Keyboard shortcut from the settings (none = no shortcut).
    @ViewBuilder public func shortcut(_ b: KeyBinding) -> some View {
        if let k = b.keyEquivalent { keyboardShortcut(k, modifiers: b.eventModifiers) } else { self }
    }

    /// The size of the controls and the app's text (Settings → Display → Interface size).
    public func uiSized(_ size: UISize) -> some View {
        let cs: ControlSize
        switch size {
        case .small: cs = .small
        case .normal: cs = .regular
        case .large: cs = .large
        case .xlarge: cs = .extraLarge
        }
        return controlSize(cs).font(.system(size: size.basePoints)).environment(\.uiScale, size.basePoints / UISize.normal.basePoints)
    }

    /// A text style scaled by the interface size (instead of `.font(.caption)` etc., which have a fixed size on macOS).
    public func uiFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil, digits: Bool = false) -> some View {
        modifier(UIFontModifier(style: style, weight: weight, design: design, digits: digits))
    }

    /// A tooltip that can be turned off in Settings (MMTTY "Show Button Hint").
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

private struct UIScaleKey: EnvironmentKey { static let defaultValue = 1.0 }
extension EnvironmentValues {
    /// The interface scale (1 = normal) – `uiSized` sets it, `uiFont` uses it.
    public var uiScale: Double {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

struct UIFontModifier: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?
    let design: Font.Design?
    let digits: Bool
    @Environment(\.uiScale) private var scale

    /// The macOS sizes of the text styles (pt).
    static func points(_ s: Font.TextStyle) -> Double {
        switch s {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption: 10
        case .caption2: 10
        @unknown default: 13
        }
    }

    func body(content: Content) -> some View {
        var f = Font.system(size: Self.points(style) * scale, weight: weight ?? (style == .headline ? .bold : .regular),
                            design: design ?? .default)
        if digits { f = f.monospacedDigit() }
        return content.font(f)
    }
}
