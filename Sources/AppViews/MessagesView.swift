// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import Settings
import SwiftUI

/// Nabídka seznamu zpráv (MMTTY MsgList): výběr = odeslat jako makro.
struct MessagesMenu: View {
    @Bindable var model: AppModel
    @State private var editing = false
    var body: some View {
        Menu("Zprávy") {
            ForEach(Array(model.settings.messages.enumerated()), id: \.offset) { i, m in
                Button(m.name.isEmpty ? "Zpráva \(i + 1)" : m.name) { Task { await model.runMessage(i) } }
                    .disabled(m.text.isEmpty)
            }
            if !model.settings.messages.isEmpty { Divider() }
            Button("Upravit zprávy…") { editing = true }
        }
        .fixedSize()
        .help("Seznam uložených zpráv – výběr zprávu odešle (syntaxe maker)")
        .sheet(isPresented: $editing) { MessagesEditor(model: model) }
    }
}

/// Editor seznamu zpráv: přidat, smazat, přesunout, upravit název a text.
struct MessagesEditor: View {
    @Bindable var model: AppModel
    @State private var items: [Macro] = []
    @State private var sel: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Seznam zpráv").font(.headline)
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 4) {
                    List(selection: $sel) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, m in
                            Text(m.name.isEmpty ? "Zpráva \(i + 1)" : m.name).tag(i)
                        }
                        .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .frame(width: 180)
                    HStack {
                        Button { items.append(Macro(name: "Nová", text: "")); sel = items.count - 1 } label: { Image(systemName: "plus") }
                        Button { if let s = sel, items.indices.contains(s) { items.remove(at: s); sel = nil } } label: { Image(systemName: "minus") }
                            .disabled(sel == nil)
                        Spacer()
                    }
                }
                if let s = sel, items.indices.contains(s) {
                    VStack(alignment: .leading) {
                        TextField("Název", text: $items[s].name)
                        TextEditor(text: Binding(get: { items[s].text.replacingOccurrences(of: "\r\n", with: "\n") },
                                                 set: { items[s].text = $0.replacingOccurrences(of: "\n", with: "\r\n") }))
                            .font(.system(.body, design: .monospaced))
                    }
                } else {
                    Text("Vyberte zprávu vlevo").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Text("Syntaxe jako makra: %c %m %n %r %g … · \\ na konci = RX · # na konci = zůstat TX · %l = zalogovat")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Zrušit") { dismiss() }
                Button("Uložit") { let m = items; Task { await model.saveMessages(m) }; dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 640, height: 400)
        .onAppear { items = model.settings.messages; sel = items.isEmpty ? nil : 0 }
    }
}

extension Color {
    /// `#RRGGBB` → barva (nil = neplatné).
    init?(hex: String?) {
        guard let h = Macro.validColor(hex), let v = UInt32(h.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    var hexString: String? {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
