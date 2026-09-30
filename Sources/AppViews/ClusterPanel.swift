// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import Localization
import Settings
import Spots
import SwiftUI

/// DX cluster commands in the Spots window: 10 buttons (the `settings.spots.clusterMacros` macros, edited like the transmit
/// macros), a manual command line with history (up/down arrow) and an expandable console with the cluster's replies.
/// Disabled until the DX cluster accepts commands (logged in). The macros can be edited without a connection too ("Edit" menu,
/// context menu). Sent to the cluster only, never to the radio.
struct ClusterPanel: View {
    @Bindable var model: AppModel
    @State private var editing: Int?
    @State private var command = ""
    @State private var historyPos: Int?
    @State private var showConsole = false
    @FocusState private var fieldFocused: Bool

    /// Commands can be sent: the cluster is enabled, connected and logged in (not just a TCP connection established).
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
            // one group of 10 buttons, each still individually reachable
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("Příkazy clusteru"))
            HStack(spacing: 6) {
                // typing ends the history walk (the arrow then starts again from the newest entry)
                TextField(L("Příkaz pro DX cluster (např. sh/dx 30)"),
                          text: Binding(get: { command }, set: { command = $0; historyPos = nil }))
                    .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                    // the placeholder is only read while the field is empty, so name the field too
                    .accessibilityLabel(L("Příkaz pro DX cluster"))
                    .accessibilityHint(L("Šipky nahoru a dolů procházejí historii příkazů."))
                    .focused($fieldFocused)
                    .onSubmit { send() }
                    .onKeyPress(.upArrow) { history(-1); return .handled }
                    .onKeyPress(.downArrow) { history(+1); return .handled }
                    .disabled(!connected)
                    .accessibilityHint(Text(L("Šipka nahoru a dolů prochází historii příkazů, Enter příkaz odešle")))
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
        // the context menu goes on the wrapper, not on the disabled button (which would not show it); editing works without a connection
        return HStack(spacing: 0) {
            Button { Task { await model.runClusterMacro(i) } } label: {
                Text(m?.name ?? "").lineLimit(1).frame(maxWidth: .infinity)
                    .foregroundStyle(MacroBar.textColor(m?.color))
            }
            .buttonStyle(.borderedProminentIf(m?.color != nil, color: Color(hex: m?.color)))
            .disabled(!connected || m == nil || m!.isBlank)
            .accessibilityLabel((m?.name ?? "").isEmpty ? L("Příkaz clusteru %ld", i + 1)
                                                        : L("Příkaz clusteru %ld – %@", i + 1, m!.name))
            .accessibilityValue(m?.text ?? "")
            // the keyboard/VoiceOver route instead of a right click (also in the "Upravit" menu next to Odeslat)
            .accessibilityAction(named: L("Upravit…")) { editing = i }
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
                .accessibilityLabel(L("Konzola clusteru"))
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

    /// Up arrow = older command, down = newer (an empty line past the newest one).
    private func history(_ step: Int) {
        let h = model.clusterHistory
        guard !h.isEmpty else { return }
        let pos = (historyPos ?? h.count) + step
        if pos >= h.count { historyPos = nil; command = ""; return }
        historyPos = max(pos, 0)
        command = h[historyPos!]
    }
}
