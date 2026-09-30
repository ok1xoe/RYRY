// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import Localization
import Settings
import SwiftUI
import UniformTypeIdentifiers

/// File menu actions that open system dialogs.
@MainActor public enum FileActions {
    static let stamp: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd-HHmm"; return f
    }()

    /// Saves the contents of the receive window into a text file (MMTTY "RxWindow to file").
    public static func saveRxWindow(_ model: AppModel) {
        let p = NSSavePanel()
        p.allowedContentTypes = [.plainText]
        p.nameFieldStringValue = "rx-\(stamp.string(from: Date())).txt"
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try model.saveRxText(to: url) } catch { NSAlert(error: error).runModal() }
    }

    /// Starts recording the receive audio into a WAV file (MMTTY "Record WAVE").
    public static func recordWAV(_ model: AppModel) {
        let p = NSSavePanel()
        p.allowedContentTypes = [.wav]
        p.nameFieldStringValue = "rx-\(stamp.string(from: Date())).wav"
        guard p.runModal() == .OK, let url = p.url else { return }
        Task { @MainActor in
            do { try await model.startRecordingWAV(to: url) } catch { NSAlert(error: error).runModal() }
        }
    }

    /// Transmits a text file (MMTTY "Send Text…").
    public static func sendTextFile(_ model: AppModel) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.plainText, .text]
        guard p.runModal() == .OK, let url = p.url else { return }
        Task { @MainActor in await model.sendTextFile(url) }
    }

    /// Imports QSOs from ADIF (MMTTY can export its own log to ADIF).
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

    // MARK: Import from MMTTY

    private static var importWindow: NSWindow?

    /// File → Import from MMTTY…: pick Mmtty.ini, preview and choose what to overwrite.
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

    // MARK: Log management

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

    /// A new log: name and location (`<name>.adi` and `.jsonl` are created).
    public static func newLog(_ model: AppModel) {
        let p = NSSavePanel()
        p.allowedContentTypes = adifTypes; p.nameFieldStringValue = "log.adi"; p.title = L("Nový log")
        p.directoryURL = model.logLocation.directory
        guard p.runModal() == .OK, let url = p.url else { return }
        run { try await model.newLog(file: url); return nil }
    }

    /// Opens an mmtty4mac log or an ADIF file from another program.
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

    /// Saves a copy of the log under a different name and keeps working in that copy.
    public static func saveLogAs(_ model: AppModel) {
        let p = NSSavePanel()
        p.allowedContentTypes = adifTypes; p.nameFieldStringValue = model.logLocation.name + "-" + L("kopie") + ".adi"
        p.title = L("Uložit log jako")
        guard p.runModal() == .OK, let url = p.url else { return }
        run { try await model.saveLogAs(file: url); return nil }
    }

    /// An ADIF copy elsewhere (the log stays open).
    public static func exportADIF(_ model: AppModel) {
        let p = NSSavePanel()
        p.allowedContentTypes = adifTypes; p.nameFieldStringValue = model.logLocation.name + ".adi"
        p.title = L("Exportovat ADIF")
        guard p.runModal() == .OK, let url = p.url else { return }
        run { try await model.exportADIF(to: url); return nil }
    }

    /// Back the log up now (File menu).
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

    /// Opens the system sound settings (the sound card's input and output level).
    public static func openSoundSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(u) }
    }

    /// Opens Audio MIDI Setup (the device's channel format and level).
    public static func openAudioMIDISetup() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
    }
}
