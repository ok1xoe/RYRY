// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import Localization
import Settings
import Spots
import SwiftUI

/// Příkazy pro DX cluster v okně Spoty: 10 tlačítek (makra `settings.spots.clusterMacros`, úprava jako u maker
/// pro vysílání), řádek pro ruční příkaz s historií (šipka nahoru/dolů) a rozbalitelná konzole s odpověďmi clusteru.
/// Neaktivní, dokud DX cluster nepřijímá příkazy (přihlášení). Makra lze upravit i bez spojení (nabídka „Upravit“,
/// kontextová nabídka). Odesílá se jen do clusteru, nikdy do rádia.
struct ClusterPanel: View {
    @Bindable var model: AppModel
    @State private var editing: Int?
    @State private var command = ""
    @State private var historyPos: Int?
    @State private var showConsole = false
    @FocusState private var fieldFocused: Bool

    /// Příkazy lze poslat: cluster zapnutý, připojený a přihlášený (ne jen navázané TCP).
    private var connected: Bool {
        model.settings.spots.clusterEnabled && model.spotFeed.clusterCommandsReady
    }

    var body: some View {
        let macros = model.settings.spots.clusterMacros
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { ForEach(0..<10, id: \.self) { button($0, macros) } }
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(0..<2) { row in
                        GridRow { ForEach(0..<5) { col in button(row * 5 + col, macros) } }
                    }
                }
            }
            HStack(spacing: 6) {
                // psaní ukončí procházení historie (šipka pak začne znovu od nejnovějšího)
                TextField(L("Příkaz pro DX cluster (např. sh/dx 30)"),
                          text: Binding(get: { command }, set: { command = $0; historyPos = nil }))
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                    .focused($fieldFocused)
                    .onSubmit { send() }
                    .onKeyPress(.upArrow) { history(-1); return .handled }
                    .onKeyPress(.downArrow) { history(+1); return .handled }
                    .disabled(!connected)
                Button(L("Odeslat")) { send() }
                    .disabled(!connected || command.trimmingCharacters(in: .whitespaces).isEmpty)
                Menu(L("Upravit")) {
                    ForEach(0..<SpotSettings.clusterMacroCount, id: \.self) { i in
                        let name = i < macros.count ? macros[i].name : ""
                        Button("\(i + 1). " + (name.isEmpty ? "—" : name)) { editing = i }
                    }
                }
                .fixedSize()
                .hint(L("Upravit tlačítka příkazů (i bez spojení s clusterem)"))
            }
            if let msg = model.clusterMessage {
                Text(msg).font(.caption).foregroundStyle(.red)
            } else if !connected {
                Text(L("Příkazy lze odeslat, až je DX cluster připojený a přihlášený."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup(L("Konzola clusteru"), isExpanded: $showConsole) { console }
        }
        .sheet(item: Binding(get: { editing.map { EditIndex(id: $0) } }, set: { editing = $0?.id })) { e in
            MacroEditor(model: model, index: e.id, target: .cluster)
        }
    }

    private func button(_ i: Int, _ macros: [Macro]) -> some View {
        let m = i < macros.count ? macros[i] : nil
        // kontextová nabídka na obalu, ne na zakázaném tlačítku (to by ji nezobrazilo); úprava jde i bez spojení
        return HStack(spacing: 0) {
            Button { Task { await model.runClusterMacro(i) } } label: {
                Text(m?.name ?? "").lineLimit(1).frame(maxWidth: .infinity)
                    .foregroundStyle(MacroBar.textColor(m?.color))
            }
            .buttonStyle(.borderedProminentIf(m?.color != nil, color: Color(hex: m?.color)))
            .disabled(!connected || m == nil || m!.isBlank)
        }
        .contentShape(Rectangle())
        .hint(m?.text ?? "")
        .contextMenu { Button(L("Upravit…")) { editing = i } }
    }

    private var console: some View {
        let lines = model.spotFeed.consoleLines
        return VStack(alignment: .trailing, spacing: 2) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                            Text(l.isEmpty ? " " : l).font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(4)
                }
                .frame(height: 140)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                .onChange(of: lines.count) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: showConsole) { proxy.scrollTo("end", anchor: .bottom) }
            }
            Button(L("Vymazat konzolu")) { model.spotFeed.clearConsole() }.controlSize(.small)
        }
    }

    private func send() {
        let text = command
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            if await model.sendClusterLine(text) { command = ""; historyPos = nil }
        }
    }

    /// Šipka nahoru = starší příkaz, dolů = novější (za nejnovějším prázdný řádek).
    private func history(_ step: Int) {
        let h = model.clusterHistory
        guard !h.isEmpty else { return }
        let pos = (historyPos ?? h.count) + step
        if pos >= h.count { historyPos = nil; command = ""; return }
        historyPos = max(pos, 0)
        command = h[historyPos!]
    }
}
