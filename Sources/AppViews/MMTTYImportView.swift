// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import Localization
import Settings
import SwiftUI

/// Preview of the import from Mmtty.ini: what was found, what will be overwritten, warnings.
struct MMTTYImportView: View {
    let model: AppModel
    let result: MMTTYImportResult
    let fileName: String
    let close: () -> Void

    @State private var options: MMTTYImportOptions = .all
    @State private var working = false
    /// Turn ESM off after importing macros (the step macros are indices - once the macros are overwritten they may point elsewhere).
    @State private var disableESM = true

    private func binding(_ o: MMTTYImportOptions) -> Binding<Bool> {
        Binding(get: { options.contains(o) }, set: { if $0 { options.insert(o) } else { options.remove(o) } })
    }

    private var available: MMTTYImportOptions {
        var a: MMTTYImportOptions = []
        if result.macros != nil { a.insert(.macros) }
        if result.messages != nil { a.insert(.messages) }
        if result.station != nil { a.insert(.station) }
        if !result.rtty.isEmpty { a.insert(.modem) }
        if !result.shortcuts.isEmpty { a.insert(.shortcuts) }
        return a
    }
    private var selected: MMTTYImportOptions { options.intersection(available) }

    private func row(_ o: MMTTYImportOptions, _ title: String) -> some View {
        Toggle(title, isOn: binding(o)).disabled(!available.contains(o))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Import z MMTTY")).font(.headline)
            Text(fileName).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            if available.isEmpty {
                Text(L("V souboru není nic, co by šlo importovat.")).foregroundStyle(.secondary)
            } else {
                Text(L("Vyberte, co se má přepsat. Původní hodnoty se nahradí.")).font(.callout)
                VStack(alignment: .leading, spacing: 6) {
                    row(.macros, L("Makra: %ld", result.macros?.filter { !$0.text.isEmpty }.count ?? 0))
                    row(.messages, L("Zprávy: %ld", result.messages?.count ?? 0))
                    row(.station, L("Stanice: %@", result.station?.call ?? "—"))
                    row(.modem, L("Parametry modemu: %ld", result.rtty.count))
                    row(.shortcuts, L("Klávesové zkratky: %ld", result.shortcuts.count))
                }
            }
            if model.mmttyImportAffectsESM(result, options: selected) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L("ESM používá makra podle pořadí (F1, F4, F5…). Po importu maker zkontrolujte přiřazení v Nastavení → Závod → ESM."),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Toggle(L("Vypnout ESM"), isOn: $disableESM)
                }
            }
            if !result.warnings.isEmpty {
                DisclosureGroup(L("Upozornění (%ld)", result.warnings.count)) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, w in
                                Text("• " + w).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.frame(maxHeight: 140)
                }
            }
            HStack {
                Spacer()
                Button(L("Zrušit")) { close() }.keyboardShortcut(.cancelAction)
                Button(L("Importovat")) {
                    working = true
                    let opts = selected, off = disableESM
                    Task { @MainActor in
                        await model.applyMMTTYImport(result, options: opts, disableESM: off)
                        working = false
                        close()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty || working)
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}
