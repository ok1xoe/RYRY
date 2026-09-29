// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import Settings
import SwiftUI

struct MacroBar: View {
    @Bindable var model: AppModel
    @State private var editing: Int?

    var body: some View {
        let macros = model.settings.macros
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<2) { row in
                GridRow {
                    ForEach(0..<6) { col in
                        let i = row * 6 + col
                        let name = i < macros.count ? macros[i].name : ""
                        Button { Task { await model.runMacro(i) } } label: {
                            Text("F\(i + 1) \(name)").lineLimit(1).frame(maxWidth: .infinity)
                        }
                        .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSF1FunctionKey + i)!)), modifiers: [])
                        .contextMenu { Button("Upravit…") { editing = i } }
                        .disabled(i >= macros.count || macros[i].text.isEmpty)
                    }
                }
            }
        }
        .padding(6)
        .sheet(item: Binding(get: { editing.map { EditIndex(id: $0) } }, set: { editing = $0?.id })) { e in
            MacroEditor(model: model, index: e.id)
        }
    }
}

struct EditIndex: Identifiable { let id: Int }

struct MacroEditor: View {
    @Bindable var model: AppModel
    let index: Int
    @State private var name = ""
    @State private var text = ""
    @State private var repeatSec = 0.0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Makro F\(index + 1)").font(.headline)
            TextField("Název", text: $name)
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 120)
            HStack {
                Text("Opakovat po (s, 0 = ne):")
                TextField("", value: $repeatSec, format: .number).frame(width: 60)
            }
            Text("%m moje značka · %c protistanice · %n jméno · %q QTH · %r/%s RST · %R %N %M soutěžní · %g pozdrav · %D %T %t čas UTC · %L %F LTRS/FIGS · %{…} CW ID · %l zalogovat · \\ na konci = RX · # na konci = zůstat TX")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Zrušit") { dismiss() }
                Button("Uložit") {
                    var m = model.settings.macros
                    while m.count <= index { m.append(Macro(name: "", text: "")) }
                    m[index] = Macro(name: name, text: text.replacingOccurrences(of: "\n", with: "\r\n"),
                                     repeatSeconds: repeatSec > 0 ? repeatSec : nil)
                    Task { await model.saveMacros(m) }
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520)
        .onAppear {
            let m = index < model.settings.macros.count ? model.settings.macros[index] : Macro(name: "", text: "")
            name = m.name; text = m.text.replacingOccurrences(of: "\r\n", with: "\n"); repeatSec = m.repeatSeconds ?? 0
        }
    }
}
