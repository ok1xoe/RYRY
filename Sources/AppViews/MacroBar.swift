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
                    ForEach(0..<8) { col in
                        let i = row * 8 + col
                        let name = i < macros.count ? macros[i].name : ""
                        Button { Task { await model.runMacro(i) } } label: {
                            Text("\(Self.keyName(i)) \(name)").lineLimit(1).frame(maxWidth: .infinity)
                        }
                        .keyboardShortcut(Self.key(i), modifiers: i < 12 ? [] : .shift)
                        .tint(i < macros.count ? Color(hex: macros[i].color) : nil)
                        .buttonStyle(.borderedProminentIf(i < macros.count && macros[i].color != nil))
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

extension MacroBar {
    /// Makra 1–12 = F1–F12, 13–16 = ⇧F1–⇧F4 (MMTTY má 16 tlačítek).
    static func keyName(_ i: Int) -> String { i < 12 ? "F\(i + 1)" : "⇧F\(i - 11)" }
    static func key(_ i: Int) -> KeyEquivalent {
        KeyEquivalent(Character(UnicodeScalar(NSF1FunctionKey + (i < 12 ? i : i - 12))!))
    }
}

struct EditIndex: Identifiable { let id: Int }

struct MacroEditor: View {
    @Bindable var model: AppModel
    let index: Int
    @State private var name = ""
    @State private var text = ""
    @State private var repeatSec = 0.0
    @State private var useColor = false
    @State private var color = Color.blue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Makro \(MacroBar.keyName(index))").font(.headline)
            TextField("Název", text: $name)
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 120)
            HStack {
                Toggle("Barva tlačítka", isOn: $useColor)
                ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden().disabled(!useColor)
                Spacer()
            }
            HStack {
                Text("Opakovat po (s, 0 = ne):")
                TextField("", value: $repeatSec, format: .number).frame(width: 60)
            }
            Text("%m moje značka · %c protistanice · %n jméno · %q QTH · %r RST odeslané · %s přijaté · %N odesílané číslo · %M přijaté číslo · %g pozdrav · %D %T %t čas UTC · %L %F LTRS/FIGS · %{…} CW ID · %l zalogovat · \\ na konci = RX · # na konci = zůstat TX")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Zrušit") { dismiss() }
                Button("Uložit") {
                    var m = model.settings.macros
                    while m.count <= index { m.append(Macro(name: "", text: "")) }
                    m[index] = Macro(name: name, text: text.replacingOccurrences(of: "\n", with: "\r\n"),
                                     repeatSeconds: repeatSec > 0 ? repeatSec : nil, color: useColor ? color.hexString : nil)
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
            useColor = m.color != nil; color = Color(hex: m.color) ?? .blue
        }
    }
}

/// Obarvené makro = výrazné tlačítko v barvě, ostatní běžná.
struct BorderedProminentIf: PrimitiveButtonStyle {
    let on: Bool
    func makeBody(configuration: Configuration) -> some View {
        if on { Button(configuration).buttonStyle(.borderedProminent) } else { Button(configuration).buttonStyle(.bordered) }
    }
}
extension PrimitiveButtonStyle where Self == BorderedProminentIf {
    static func borderedProminentIf(_ on: Bool) -> BorderedProminentIf { BorderedProminentIf(on: on) }
}
