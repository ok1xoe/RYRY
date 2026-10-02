// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppKit
import AppUI
import Settings
import SwiftUI
import Localization

struct MacroBar: View {
    @Bindable var model: AppModel
    @State private var editing: Int?
    @State private var confirmReset = false

    /// The macro set: normal / DX outside a contest (a switch), the contest's own set in a contest; reset to defaults.
    var setRow: some View {
        HStack(spacing: 8) {
            Text(L("Sada maker:")).uiFont(.callout).foregroundStyle(.secondary)
            if model.settings.contest.enabled {
                Text(model.macroSetTitle).uiFont(.caption, weight: .bold)
            } else {
                Picker("", selection: Binding(get: { model.settings.operatingMode }, set: { model.setOperatingMode($0) })) {
                    Text(L("Běžný provoz")).tag(OperatingMode.normal)
                    Text("DX").tag(OperatingMode.dx)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize().uiControlSize(-1)
            }
            Spacer()
            Button(L("Výchozí makra…")) { confirmReset = true }.uiControlSize(-1)
                .hint(L("Nahradí makra této sady výchozími (v závodě podle jeho výměny)."))
        }
        .confirmationDialog(L("Nahradit makra sady „%@“ výchozími?", model.macroSetTitle), isPresented: $confirmReset) {
            Button(L("Nahradit"), role: .destructive) { Task { await model.resetMacroSet() } }
        }
    }

    var body: some View {
        let macros = model.settings.macros
        VStack(spacing: 4) {
        setRow.padding(.horizontal, 6).padding(.top, 4)
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<2) { row in
                GridRow {
                    ForEach(0..<8) { col in
                        let i = row * 8 + col
                        let name = i < macros.count ? macros[i].name : ""
                        let kb = model.settings.binding(for: .macro(i))
                        Button {
                            guard let m = Self.macroIndex(button: i, settings: model.settings, event: NSApp.currentEvent) else { return }
                            Task { await model.runMacro(m) }
                        } label: {
                            Text(kb.isNone ? name : "\(kb.display) \(name)").lineLimit(1).frame(maxWidth: .infinity)
                                .foregroundStyle(Self.textColor(i < macros.count ? macros[i].color : nil))
                        }
                        .shortcut(kb)
                        .hint(model.macroPreview(i))
                        .buttonStyle(.borderedProminentIf(i < macros.count && macros[i].color != nil,
                                                          color: i < macros.count ? Color(hex: macros[i].color) : nil))
                        .contextMenu { Button(L("Upravit…")) { editing = i } }
                        .disabled(i >= macros.count || macros[i].text.isEmpty)
                    }
                }
            }
        }
        .padding(6)
        }
        .sheet(item: Binding(get: { editing.map { EditIndex(id: $0) } }, set: { editing = $0?.id })) { e in
            MacroEditor(model: model, index: e.id)
        }
    }
}

extension MacroBar {
    /// Macros 1–12 = F1–F12, 13–16 = ⇧F1–⇧F4 (MMTTY has 16 buttons).
    /// Button text: black on a light color, white on a dark one, default when there is no color.
    static func textColor(_ hex: String?) -> Color {
        guard let c = Color(hex: hex) else { return .primary }
        return c.isLight ? .black : .white
    }
    /// Which macro a press of button `i` runs. A key shortcut: SwiftUI does not tell Shift apart on function keys
    /// (⇧F1 triggered the F1 button), so the macro is chosen by the exact key combination of the event; a combination
    /// that no macro has = nothing. A mouse click = macro `i`.
    static func macroIndex(button i: Int, settings: AppSettings, event: NSEvent?) -> Int? {
        guard let e = event, e.type == .keyDown, let b = KeyBinding.from(e) else { return i }
        if b == settings.binding(for: .macro(i)) { return i }
        return settings.macro(for: b)
    }
    static func keyName(_ i: Int) -> String { i < 12 ? "F\(i + 1)" : "⇧F\(i - 11)" }
}

struct EditIndex: Identifiable { let id: Int }

/// Macro editor: transmit macros (`settings.macros`) or DX cluster command macros (`settings.spots.clusterMacros`).
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
            Text(target == .cluster ? L("Příkaz clusteru %ld", index + 1) : L("Makro %@", MacroBar.keyName(index))).uiFont(.headline)
            TextField(L("Název"), text: $name)
            TextEditor(text: $text).uiFont(.body, design: .monospaced).frame(minHeight: 120)
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
                    .uiFont(.callout).foregroundStyle(.secondary)
            } else {
            GroupBox(L("Zástupné znaky")) {
                ScrollView { MacroVariablesHelp().frame(maxWidth: .infinity, alignment: .leading).padding(4) }
                    .frame(height: 260)
            }
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
        .frame(width: 640)
        .onAppear {
            let m = index < list.count ? list[index] : Macro(name: "", text: "")
            name = m.name; text = m.text.replacingOccurrences(of: "\r\n", with: "\n"); repeatSec = m.repeatSeconds ?? 0
            useColor = m.color != nil; color = Color(hex: m.color) ?? .blue
        }
    }
}

/// A colored macro = a button filled with its own color (kept even in an inactive window), the rest are ordinary.
struct BorderedProminentIf: PrimitiveButtonStyle {
    let on: Bool
    var color: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        // the system bordered style keeps its own font size – our style follows the interface size (Settings → Display)
        Button(configuration).buttonStyle(ColorFillButtonStyle(color: on ? color ?? .accentColor : Color.primary.opacity(0.1)))
    }
}

struct ColorFillButtonStyle: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var enabled
    @Environment(\.uiScale) private var scale
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 4 * scale).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(configuration.isPressed ? 0.7 : 1)))
            .opacity(enabled ? 1 : 0.45)
    }
}
extension PrimitiveButtonStyle where Self == BorderedProminentIf {
    static func borderedProminentIf(_ on: Bool, color: Color? = nil) -> BorderedProminentIf { BorderedProminentIf(on: on, color: color) }
}
