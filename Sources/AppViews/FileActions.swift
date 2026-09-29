// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import Localization
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

    /// Otevře nastavení zvuku systému (úroveň vstupu a výstupu zvukovky).
    public static func openSoundSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(u) }
    }

    /// Otevře Audio MIDI Setup (formát a úroveň kanálů zařízení).
    public static func openAudioMIDISetup() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
    }
}
