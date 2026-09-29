// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import Localization
import Settings
import SwiftUI
import UniformTypeIdentifiers

/// Akce menu Soubor, které otevírají systémové dialogy.
@MainActor public enum FileActions {
    static let stamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd-HHmm"; return f
    }()

    /// Uloží obsah okna příjmu do textového souboru (MMTTY „RxWindow to file“).
    public static func saveRxWindow(_ model: AppModel) {
        let p = NSSavePanel()
        p.allowedContentTypes = [.plainText]
        p.nameFieldStringValue = "rx-\(stamp.string(from: Date())).txt"
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try model.saveRxText(to: url) } catch { NSAlert(error: error).runModal() }
    }

    /// Spustí nahrávání příjmu do WAV (MMTTY „Record WAVE“).
    public static func recordWAV(_ model: AppModel) {
        let p = NSSavePanel()
        p.allowedContentTypes = [.wav]
        p.nameFieldStringValue = "rx-\(stamp.string(from: Date())).wav"
        guard p.runModal() == .OK, let url = p.url else { return }
        Task { @MainActor in
            do { try await model.startRecordingWAV(to: url) } catch { NSAlert(error: error).runModal() }
        }
    }

    /// Vyšle textový soubor (MMTTY „Send Text…“).
    public static func sendTextFile(_ model: AppModel) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.plainText, .text]
        guard p.runModal() == .OK, let url = p.url else { return }
        Task { @MainActor in await model.sendTextFile(url) }
    }

    /// Import spojení z ADIF (MMTTY umí svůj log exportovat do ADIF).
    public static func importADIF(_ model: AppModel) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [UTType(filenameExtension: "adi"), UTType(filenameExtension: "adif"), .plainText].compactMap { $0 }
        guard p.runModal() == .OK, let url = p.url else { return }
        Task { @MainActor in
            do {
                let msg = try await model.importADIF(url)
                let a = NSAlert(); a.messageText = L("Import ADIF"); a.informativeText = msg; a.runModal()
            } catch { NSAlert(error: error).runModal() }
        }
    }

    // MARK: Import z MMTTY

    private static var importWindow: NSWindow?

    /// Menu Soubor → Importovat z MMTTY…: výběr Mmtty.ini, náhled a volba, co přepsat.
    public static func importMMTTY(_ model: AppModel) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [UTType(filenameExtension: "ini"), .plainText].compactMap { $0 }
        p.title = L("Importovat z MMTTY"); p.message = L("Vyberte soubor Mmtty.ini z Windows MMTTY.")
        guard p.runModal() == .OK, let url = p.url else { return }
        let result: MMTTYImportResult
        do { result = try model.previewMMTTYImport(url) } catch { NSAlert(error: error).runModal(); return }
        importWindow?.close()
        let view = MMTTYImportView(model: model, result: result, fileName: url.path) { importWindow?.close() }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = L("Importovat z MMTTY"); w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center(); w.makeKeyAndOrderFront(nil)
        importWindow = w
    }

    // MARK: Správa logu

    static var adifTypes: [UTType] { [UTType(filenameExtension: "adi"), UTType(filenameExtension: "adif")].compactMap { $0 } }

    private static func run(_ body: @escaping @MainActor () async throws -> String?) {
        Task { @MainActor in
            do {
                if let msg = try await body() {
                    let a = NSAlert(); a.messageText = "Log"; a.informativeText = msg; a.runModal()
                }
            } catch { NSAlert(error: error).runModal() }
        }
    }

    /// Nový log: název a umístění (vytvoří se `<název>.adi` a `.jsonl`).
    public static func newLog(_ model: AppModel) {
        let p = NSSavePanel()
        p.allowedContentTypes = adifTypes; p.nameFieldStringValue = "log.adi"; p.title = L("Nový log")
        p.directoryURL = model.logLocation.directory
        guard p.runModal() == .OK, let url = p.url else { return }
        run { try await model.newLog(file: url); return nil }
    }

    /// Otevře log mmtty4mac nebo ADIF z jiného programu.
    public static func openLog(_ model: AppModel) {
        let p = NSOpenPanel()
        p.allowedContentTypes = adifTypes + [UTType(filenameExtension: "jsonl")].compactMap { $0 }
        p.title = L("Otevřít log"); p.directoryURL = model.logLocation.directory
        guard p.runModal() == .OK, let url = p.url else { return }
        openLog(model, url: url)
    }

    public static func openLog(_ model: AppModel, url: URL) {
        run { try await model.openLog(file: url) }
    }

    /// Uloží kopii logu pod jiným názvem a dál pracuje v ní.
    public static func saveLogAs(_ model: AppModel) {
        let p = NSSavePanel()
        p.allowedContentTypes = adifTypes; p.nameFieldStringValue = model.logLocation.name + "-" + L("kopie") + ".adi"
        p.title = L("Uložit log jako")
        guard p.runModal() == .OK, let url = p.url else { return }
        run { try await model.saveLogAs(file: url); return nil }
    }

    /// Kopie ADIF jinam (log zůstává otevřený).
    public static func exportADIF(_ model: AppModel) {
        let p = NSSavePanel()
        p.allowedContentTypes = adifTypes; p.nameFieldStringValue = model.logLocation.name + ".adi"
        p.title = L("Exportovat ADIF")
        guard p.runModal() == .OK, let url = p.url else { return }
        run { try await model.exportADIF(to: url); return nil }
    }

    /// Záloha logu teď (menu Soubor).
    public static func backupLog(_ model: AppModel) {
        Task { @MainActor in
            do {
                let dir = try await model.backupLogNow()
                let a = NSAlert(); a.messageText = "Log"
                a.informativeText = L("Záloha uložena: %@", (dir.path as NSString).abbreviatingWithTildeInPath); a.runModal()
            } catch { NSAlert(error: error).runModal() }
        }
    }

    public static func openBackups(_ model: AppModel) {
        try? FileManager.default.createDirectory(at: model.backupDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(model.backupDirectory)
    }

    /// Otevře nastavení zvuku systému (úroveň vstupu a výstupu zvukovky).
    public static func openSoundSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(u) }
    }

    /// Otevře Audio MIDI Setup (formát a úroveň kanálů zařízení).
    public static func openAudioMIDISetup() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
    }
}
