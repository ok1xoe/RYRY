// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import Localization
import SwiftUI
import Updates

/// Okno aktualizací: výsledek ruční kontroly, poznámky k nové verzi a tlačítka Stáhnout / Později / Přeskočit.
public struct UpdateWindow: View {
    @Bindable var model: UpdateModel
    @Environment(\.dismiss) private var dismiss
    public init(model: UpdateModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.status {
            case .idle:
                Text(L("Žádná nová verze k zobrazení.")).foregroundStyle(.secondary)
                closeRow
            case .checking:
                HStack { ProgressView().controlSize(.small); Text(L("Kontroluji aktualizace…")) }
            case .upToDate:
                Label(L("Používáte nejnovější verzi."), systemImage: "checkmark.circle").font(.headline)
                Text(L("Verze %@", model.currentVersionText)).foregroundStyle(.secondary)
                closeRow
            case .notConfigured:
                Label(L("Adresa aktualizací není nastavená."), systemImage: "exclamationmark.triangle").font(.headline)
                Text(L("V Info.plist aplikace je klíč MMUpdateFeedURL prázdný, kontrola aktualizací je vypnutá."))
                    .font(.callout).foregroundStyle(.secondary)
                closeRow
            case .failed(let m):
                Label(L("Kontrola aktualizací se nezdařila."), systemImage: "wifi.exclamationmark").font(.headline)
                Text(m).font(.callout).foregroundStyle(.secondary)
                closeRow
            case .systemTooOld(let i):
                Label(L("Verze %@ vyžaduje novější macOS.", i.version.description), systemImage: "exclamationmark.triangle").font(.headline)
                Text(L("Minimální verze macOS: %@", i.minimumSystemVersion ?? "")).foregroundStyle(.secondary)
                closeRow
            case .available(let i):
                available(i, downloading: false)
            case .downloading(let i):
                available(i, downloading: true)
            case .downloaded(let f):
                Label(L("Stahování dokončeno."), systemImage: "checkmark.circle").font(.headline)
                Text(L("Obraz disku je otevřený. Přetáhněte mmtty4mac do složky Aplikace (nahradí starou verzi)."))
                Text(f.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button(L("Ukázat ve Finderu")) { NSWorkspace.shared.activateFileViewerSelecting([f]) }
                    Spacer()
                    Button(L("Zavřít")) { model.later(); dismiss() }.keyboardShortcut(.defaultAction)
                }
            case .downloadFailed(let m):
                Label(L("Stažení se nezdařilo."), systemImage: "exclamationmark.triangle").font(.headline)
                Text(m).font(.callout).foregroundStyle(.secondary)
                closeRow
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var closeRow: some View {
        HStack { Spacer(); Button(L("Zavřít")) { model.later(); dismiss() }.keyboardShortcut(.defaultAction) }
    }

    @ViewBuilder private func available(_ i: UpdateInfo, downloading: Bool) -> some View {
        Label(L("Je dostupná nová verze %@.", i.version.description), systemImage: "arrow.down.circle").font(.headline)
        Text(L("Máte verzi %@.", model.currentVersionText)).foregroundStyle(.secondary)
        let notes = i.notes(for: Localizer.shared.code)
        if !notes.isEmpty {
            ScrollView {
                Text(notes).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(height: 140).padding(6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
        HStack {
            Button(L("Přeskočit tuto verzi")) { model.skipThisVersion(); dismiss() }.disabled(downloading)
            Spacer()
            if downloading { ProgressView().controlSize(.small) }
            Button(L("Později")) { model.later(); dismiss() }.disabled(downloading)
            Button(L("Stáhnout")) { Task { await model.download() } }
                .keyboardShortcut(.defaultAction).disabled(downloading)
        }
    }
}
