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
/// Řádky mají stabilní ID (výběr ani rozepsané pole nesmí po smazání/přesunu ukazovat na jinou zprávu).
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
            Text("Seznam zpráv").font(.headline)
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 4) {
                    List(selection: $sel) {
                        ForEach(rows) { r in Text(r.m.name.isEmpty ? "(bez názvu)" : r.m.name).tag(r.id) }
                            .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .frame(width: 180)
                    HStack {
                        Button { let r = Row(m: Macro(name: "Nová", text: "")); rows.append(r); sel = r.id } label: { Image(systemName: "plus") }
                        Button {
                            NSApp.keyWindow?.makeFirstResponder(nil)        // dokončit rozepsané pole ještě před smazáním
                            if let s = sel { rows.removeAll { $0.id == s }; sel = rows.first?.id }
                        } label: { Image(systemName: "minus") }
                            .disabled(sel == nil)
                        Spacer()
                    }
                }
                if let s = sel, rows.contains(where: { $0.id == s }) {
                    VStack(alignment: .leading) {
                        TextField("Název", text: binding(s, \.name))
                        TextEditor(text: Binding(get: { binding(s, \.text).wrappedValue.replacingOccurrences(of: "\r\n", with: "\n") },
                                                 set: { binding(s, \.text).wrappedValue = $0.replacingOccurrences(of: "\n", with: "\r\n") }))
                            .font(.system(.body, design: .monospaced))
                    }
                    .id(s)                                           // při změně výběru nové pole, žádný přenos stavu
                } else {
                    Text("Vyberte zprávu vlevo").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Text("Syntaxe jako makra: %c %m %n %r %g … · \\ na konci = RX · # na konci = zůstat TX · %l = zalogovat")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Zrušit") { dismiss() }
                Button("Uložit") {
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
