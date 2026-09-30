// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import Settings
import SwiftUI
import Localization

/// The message list menu (MMTTY MsgList): picking an item sends it as a macro.
struct MessagesMenu: View {
    @Bindable var model: AppModel
    @State private var editing = false
    var body: some View {
        Menu(L("Zprávy")) {
            ForEach(Array(model.settings.messages.enumerated()), id: \.offset) { i, m in
                Button(m.name.isEmpty ? L("Zpráva %ld", i + 1) : m.name) { Task { await model.runMessage(i) } }
                    .disabled(m.text.isEmpty)
            }
            if !model.settings.messages.isEmpty { Divider() }
            Button(L("Upravit zprávy…")) { editing = true }
        }
        .fixedSize()
        .hint(L("Seznam uložených zpráv – výběr zprávu odešle (syntaxe maker)"))
        .sheet(isPresented: $editing) { MessagesEditor(model: model) }
    }
}

/// Message list editor: add, delete, move, edit the name and the text.
/// The rows have stable IDs (neither the selection nor a half-typed field may point at a different message after a delete/move).
struct MessagesEditor: View {
    @Bindable var model: AppModel
    struct Row: Identifiable { let id = UUID(); var m: Macro }
    @State private var rows: [Row] = []
    @State private var sel: UUID?
    @Environment(\.dismiss) private var dismiss

    private func binding(_ id: UUID, _ kp: WritableKeyPath<Macro, String>) -> Binding<String> {
        Binding(get: { rows.first { $0.id == id }?.m[keyPath: kp] ?? "" },
                set: { v in if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].m[keyPath: kp] = v } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Seznam zpráv")).font(.headline)
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 4) {
                    List(selection: $sel) {
                        ForEach(rows) { r in Text(r.m.name.isEmpty ? L("(bez názvu)") : r.m.name).tag(r.id) }
                            .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .frame(width: 180)
                    .accessibilityLabel(L("Seznam zpráv"))
                    HStack {
                        Button { let r = Row(m: Macro(name: L("Nová"), text: "")); rows.append(r); sel = r.id } label: { Image(systemName: "plus") }
                            .accessibilityLabel(L("Přidat zprávu"))
                        Button {
                            NSApp.keyWindow?.makeFirstResponder(nil)        // commit the half-typed field before deleting
                            if let s = sel { rows.removeAll { $0.id == s }; sel = rows.first?.id }
                        } label: { Image(systemName: "minus") }
                            .disabled(sel == nil)
                            .accessibilityLabel(L("Odebrat vybranou zprávu"))
                        Spacer()
                    }
                }
                if let s = sel, rows.contains(where: { $0.id == s }) {
                    VStack(alignment: .leading) {
                        TextField(L("Název"), text: binding(s, \.name))
                        TextEditor(text: Binding(get: { binding(s, \.text).wrappedValue.replacingOccurrences(of: "\r\n", with: "\n") },
                                                 set: { binding(s, \.text).wrappedValue = $0.replacingOccurrences(of: "\n", with: "\r\n") }))
                            .font(.system(.body, design: .monospaced))
                            .accessibilityLabel(L("Text zprávy"))
                    }
                    .id(s)                                           // a new field when the selection changes, no state carried over
                } else {
                    Text(L("Vyberte zprávu vlevo")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Text(L("Syntaxe jako makra: %c %m %n %r %g … · \\ na konci = RX · # na konci = zůstat TX · %l = zalogovat"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L("Zrušit")) { dismiss() }
                Button(L("Uložit")) {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    let m = rows.map(\.m); Task { await model.saveMessages(m) }; dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 640, height: 400)
        .onAppear { rows = model.settings.messages.map { Row(m: $0) }; sel = rows.first?.id }
    }
}

extension Color {
    /// `#RRGGBB` → color (nil = invalid).
    init?(hex: String?) {
        guard let h = Macro.validColor(hex), let v = UInt32(h.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    /// A light color (yellow, light green…) needs dark text.
    var isLight: Bool {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return false }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent > 0.6
    }
    var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
