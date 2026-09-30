// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import Settings
import SwiftUI
import Localization

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
                        let kb = model.settings.binding(for: .macro(i))
                        Button { Task { await model.runMacro(i) } } label: {
                            Text(kb.isNone ? name : "\(kb.display) \(name)").lineLimit(1).frame(maxWidth: .infinity)
                                .foregroundStyle(Self.textColor(i < macros.count ? macros[i].color : nil))
                        }
                        .shortcut(kb)
                        .buttonStyle(.borderedProminentIf(i < macros.count && macros[i].color != nil,
                                                          color: i < macros.count ? Color(hex: macros[i].color) : nil))
                        .contextMenu { Button(L("Upravit…")) { editing = i } }
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
    /// Text tlačítka: na světlé barvě černý, na tmavé bílý, bez barvy výchozí.
    static func textColor(_ hex: String?) -> Color {
        guard let c = Color(hex: hex) else { return .primary }
        return c.isLight ? .black : .white
    }
    static func keyName(_ i: Int) -> String { i < 12 ? "F\(i + 1)" : "⇧F\(i - 11)" }
}

struct EditIndex: Identifiable { let id: Int }

/// Editor maker: makra pro vysílání (`settings.macros`) nebo příkazů DX clusteru (`settings.spots.clusterMacros`).
struct MacroEditor: View {
    enum Target { case transmit, cluster }
    @Bindable var model: AppModel
    let index: Int
    var target: Target = .transmit
    @State private var name = ""
    @State private var text = ""
    @State private var repeatSec = 0.0
    @State private var useColor = false
    @State private var color = Color.blue
    @Environment(\.dismiss) private var dismiss

    private var list: [Macro] { target == .cluster ? model.settings.spots.clusterMacros : model.settings.macros }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(target == .cluster ? L("Příkaz clusteru %ld", index + 1) : L("Makro %@", MacroBar.keyName(index))).font(.headline)
            TextField(L("Název"), text: $name)
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 120)
            HStack {
                Toggle(L("Barva tlačítka"), isOn: $useColor)
                ColorPicker("", selection: $color, supportsOpacity: false).labelsHidden().disabled(!useColor)
                Spacer()
            }
            if target == .transmit {
                HStack {
                    Text(L("Opakovat po (s, 0 = ne):"))
                    TextField("", value: $repeatSec, format: .number).frame(width: 60)
                }
            }
            if target == .cluster {
                Text(L("%m moje značka · %c protistanice · %n jméno · %q QTH · %k frekvence rigu v kHz · %D %T %t čas UTC · jeden řádek = jeden příkaz · \\ # a CW ID se ignorují"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
            Text(L("%m moje značka · %c protistanice · %n jméno · %q QTH · %r RST odeslané · %s přijaté · %N odesílané číslo · %M přijaté číslo · %g pozdrav · %D %T %t čas UTC · %L %F LTRS/FIGS · %{…} CW ID · %l zalogovat · \\ na konci = RX · # na konci = zůstat TX"))
                .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(L("Zrušit")) { dismiss() }
                Button(L("Uložit")) {
                    var m = list
                    while m.count <= index { m.append(Macro(name: "", text: "")) }
                    m[index] = Macro(name: name, text: target == .cluster ? text : text.replacingOccurrences(of: "\n", with: "\r\n"),
                                     repeatSeconds: target == .transmit && repeatSec > 0 ? repeatSec : nil,
                                     color: useColor ? color.hexString : nil)
                    switch target {
                    case .transmit: Task { await model.saveMacros(m) }
                    case .cluster: model.saveClusterMacros(m)
                    }
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 520)
        .onAppear {
            let m = index < list.count ? list[index] : Macro(name: "", text: "")
            name = m.name; text = m.text.replacingOccurrences(of: "\r\n", with: "\n"); repeatSec = m.repeatSeconds ?? 0
            useColor = m.color != nil; color = Color(hex: m.color) ?? .blue
        }
    }
}

/// Obarvené makro = tlačítko vyplněné vlastní barvou (drží se i v neaktivním okně), ostatní běžná.
struct BorderedProminentIf: PrimitiveButtonStyle {
    let on: Bool
    var color: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        if on, let color {
            Button(configuration).buttonStyle(ColorFillButtonStyle(color: color))
        } else {
            Button(configuration).buttonStyle(.automatic)
        }
    }
}

struct ColorFillButtonStyle: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(configuration.isPressed ? 0.7 : 1)))
            .opacity(enabled ? 1 : 0.45)
    }
}
extension PrimitiveButtonStyle where Self == BorderedProminentIf {
    static func borderedProminentIf(_ on: Bool, color: Color? = nil) -> BorderedProminentIf { BorderedProminentIf(on: on, color: color) }
}
