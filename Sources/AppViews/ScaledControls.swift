// Copyright 2026 OK1XOE (RYRY), LGPL v3
import SwiftUI

// Menus, menu pickers and segmented pickers that follow the interface size (Settings → Display). The native macOS
// controls keep their 13 pt text at any control size, so above or below the normal size they are drawn by us.

extension View {
    /// A `Menu` whose button follows the interface size.
    func uiMenu() -> some View { modifier(UIMenuModifier()) }
}

struct UIMenuModifier: ViewModifier {
    @Environment(\.uiSize) private var size
    func body(content: Content) -> some View {
        if size == .normal {
            content
        } else {
            content.menuStyle(.button).buttonStyle(ColorFillButtonStyle(color: Color.primary.opacity(0.1)))
        }
    }
}

/// The label of a menu: the text, and above or below the normal size a chevron (the drawn menu button has none).
struct UIMenuLabel: View {
    let text: String
    @Environment(\.uiSize) private var size
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(spacing: 4) {
            Text(text).lineLimit(1)
            if size != .normal { Image(systemName: "chevron.down").imageScale(.small).foregroundStyle(.secondary) }
        }
    }
}

/// A menu picker (`Picker` in the menu style) that follows the interface size.
struct UIMenuPicker<T: Hashable>: View {
    var title: String?
    @Binding var selection: T
    let options: [(T, String)]
    @Environment(\.uiSize) private var size

    var body: some View {
        if size == .normal {
            Picker(title ?? "", selection: $selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden(title == nil)
        } else {
            HStack(spacing: 4) {
                if let title { Text(title) }
                Menu {
                    ForEach(options, id: \.0) { o in
                        Button { selection = o.0 } label: {
                            if o.0 == selection { Label(o.1, systemImage: "checkmark") } else { Text(o.1) }
                        }
                    }
                } label: {
                    UIMenuLabel(options.first { $0.0 == selection }?.1 ?? "—")
                }
                .uiMenu()
            }
        }
    }
}

/// A segmented picker that follows the interface size.
struct UISegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    @Environment(\.uiSize) private var size

    var body: some View {
        if size == .normal {
            Picker("", selection: $selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.segmented).labelsHidden()
        } else {
            HStack(spacing: 2) {
                ForEach(options, id: \.0) { o in
                    Button(o.1) { selection = o.0 }
                        .buttonStyle(ColorFillButtonStyle(color: o.0 == selection ? Color.accentColor : Color.primary.opacity(0.1)))
                        .foregroundStyle(o.0 == selection ? Color.white : Color.primary)
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder func labelsHidden(_ on: Bool) -> some View {
        if on { labelsHidden() } else { self }
    }
}
