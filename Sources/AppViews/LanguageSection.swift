// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import Localization
import SwiftUI
import UniformTypeIdentifiers

/// Volba jazyka rozhraní – platí hned ve všech oknech (nečeká na „Použít“).
struct LanguageSection: View {
    let library: LanguageLibrary
    @State private var packs: [LanguagePack] = []
    @State private var message: String?

    init(library: LanguageLibrary = .standard()) { self.library = library }

    var body: some View {
        Section {
            Picker(L("Jazyk rozhraní"), selection: Binding(get: { Localizer.shared.code },
                                                         set: { library.select($0) })) {
                Text("Čeština").tag(Localizer.baseCode)
                ForEach(packs, id: \.code) { p in Text(p.name).tag(p.code) }
            }
            LabeledContent(L("Vlastní překlad")) {
                HStack {
                    Button(L("Nahrát jazyk…")) { importPack() }
                    Button(L("Uložit šablonu…")) { saveTemplate() }
                        .disabled(library.reference() == nil)
                    Button { openFolder() } label: { Image(systemName: "folder") }
                        .help(L("Otevřít složku jazyků"))
                }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        } header: { Text(L("Jazyk")) } footer: {
            Text(L("Nový překlad: ulož šablonu, přelož hodnoty v „strings“, nastav „code“ a „name“ a soubor nahraj. Chybějící texty zůstanou česky."))
        }
        .onAppear { packs = library.available() }
    }

    private func importPack() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let p = try library.importPack(from: url)
            packs = library.available()
            library.select(p.code)
            message = L("Jazyk „%@“ nahrán (%ld textů).", p.name, p.strings.count)
        } catch { message = LanguagePack.message(error) }
    }

    private func saveTemplate() {
        guard let ref = library.reference() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "mmtty4mac-language.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try LanguagePack.template(from: ref).encoded().write(to: url, options: .atomic)
            message = L("Šablona uložena: %@", url.lastPathComponent)
        } catch { message = error.localizedDescription }
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: library.userDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(library.userDirectory)
    }
}
