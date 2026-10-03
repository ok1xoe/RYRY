// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppKit
import AppUI
import AppViews
import Settings
import SwiftUI
import UniformTypeIdentifiers
import Localization

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    /// On quit always go safely to RX, PTT off, stop the API.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        Task { @MainActor in
            await model.shutdown(timeout: .seconds(3))      // RX + PTT off at once, stop at most 3 s
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Closing the main window quits the app (it must not transmit without a window).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Opens the bundled HTML manual in the UI language (Czech, otherwise English).
@MainActor func openManual() {
    let lang = Localizer.shared.code == "cs" ? "cs" : "en"
    guard let r = Bundle.main.resourceURL?.appendingPathComponent("Help/\(lang)/index.html"),
          FileManager.default.fileExists(atPath: r.path) else { return }
    NSWorkspace.shared.open(r)
}

/// A page of the product website (ok1xoe.dev/ryry/, English): "" = the product page, "support/", "privacy/".
@MainActor func openWeb(_ page: String) {
    if let u = URL(string: "https://ok1xoe.dev/ryry/" + page) { NSWorkspace.shared.open(u) }
}

@MainActor func showAbout() {
    let credits = [
        L("RTTY pro macOS – nativní přepis MMTTY s API pro loggery (fldigi XML-RPC, JSON-RPC)."),
        "",
        L("Jádro demodulátoru a modulátoru: MMTTY © 2000–2013 Makoto Mori (JE3HHT), Nobuyuki Oba."),
        L("RYRY © 2026 OK1XOE. Licence GNU LGPL v3, zdrojový kód: github.com/ok1xoe/RYRY."),
        L("DXCC: cty.dat – Jim Reisert AD1C (country-files.com)."),
    ].joined(separator: "\n")
    let para = NSMutableParagraphStyle(); para.alignment = .center
    NSApp.orderFrontStandardAboutPanel(options: [
        .credits: NSAttributedString(string: credits, attributes: [.font: NSFont.systemFont(ofSize: 11), .paragraphStyle: para]),
    ])
    NSApp.activate(ignoringOtherApps: true)
}

@main
struct RYRYApp: App {
    @MainActor func playWAV(speed: Double) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.wav]
        guard p.runModal() == .OK, let url = p.url else { return }
        Task { @MainActor in
            do { try await model.playWAV(url, speed: speed) }
            catch { NSAlert(error: error).runModal() }
        }
    }

    /// A short RTTY contest QSO with noise, bundled so the app can be tried without a radio.
    @MainActor func playDemo() {
        guard let url = Bundle.main.url(forResource: "demo-rtty", withExtension: "wav") else { return }
        Task { @MainActor in
            do { try await model.playWAV(url, speed: 1) }
            catch { NSAlert(error: error).runModal() }
        }
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel(alertSink: SystemAlertSink())
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    /// The UI language from the previous launch (the -language en launch argument overrides the choice).
    /// Watches the languages folder – a saved file takes effect at once.
    private let languageWatcher: LanguageWatcher

    init() {
        AppSupport.migrateLegacy()               // the former name mmtty4mac: data folder and preferences
        let lib = LanguageLibrary.standard()
        lib.seedUserDirectory()                  // cs.json, en.json into the languages folder (for editing)
        lib.restore()
        languageWatcher = LanguageWatcher(library: lib)
        languageWatcher.start()
    }

    var body: some Scene {
        Window("RYRY", id: "main") {
            MainView(model: model)
                .environment(\.showHints, model.settings.display.showHints).uiSized(model.settings.display.uiSize)
                .task {
                    delegate.model = model
                    model.folderAccess = FolderAccess(prompt: FolderAccessPanel())
                    // the -openSettings YES launch argument (+ -settingsTab N): open Settings (screenshots, support)
                    if UserDefaults.standard.bool(forKey: "openSettings") { openSettings() }
                    // -switchLanguage cs: after 4 s switch the language as if chosen in Settings (live switch test)
                    if let c = UserDefaults.standard.string(forKey: "switchLanguage") {
                        try? await Task.sleep(for: .seconds(4))
                        LanguageLibrary.standard().select(c)
                    }
                    // -openWindow log,scope: open the windows (screenshots for the documentation)
                    for id in (UserDefaults.standard.string(forKey: "openWindow") ?? "").split(separator: ",") {
                        openWindow(id: String(id))
                    }
                    if model.state == .stopped { await model.start() }
                    // -playDemo YES: play the demo signal right after start (App Store screenshots)
                    if UserDefaults.standard.bool(forKey: "playDemo") { playDemo() }
                }
        }
        .commands {
            CommandMenu(L("Vysílání")) {
                Button("TX / RX") { Task { await model.toggleTx() } }.shortcut(model.settings.binding(for: .toggleTx))
                Button(L("Okamžitě RX")) { Task { await model.rxNow() } }.shortcut(model.settings.binding(for: .rxNow))
                Button(L("Ladění (tune)")) { Task { await model.tune() } }.shortcut(model.settings.binding(for: .tune))
                Button(L("Zastavit opakování makra")) { Task { await model.stopMacro() } }
                    .shortcut(model.settings.binding(for: .stopMacro))
                Button(L("Odeslat textový soubor…")) { FileActions.sendTextFile(model) }
                Divider()
                Button(L("Zalogovat QSO")) { Task { await model.logQSO() } }.shortcut(model.settings.binding(for: .logQSO))
                Button(L("Vymazat QSO")) { Task { await model.clearQSO() } }.shortcut(model.settings.binding(for: .clearQSO))
                Button(L("Vymazat příjem")) { model.clearRx() }.shortcut(model.settings.binding(for: .clearRx))
                Divider()
                Button(model.settings.esm.mode == .run ? L("ESM: přepnout na S&P") : L("ESM: přepnout na Run")) {
                    model.toggleESMMode()
                }.shortcut(model.settings.binding(for: .esmMode))
                Divider()
                Button(L("Zadat frekvenci…")) { model.showFrequencyEntry = true }
                    .shortcut(model.settings.binding(for: .enterFrequency))
            }
            CommandGroup(replacing: .appInfo) {
                Button(L("O aplikaci RYRY")) { showAbout() }
            }
            CommandGroup(replacing: .help) {
                Button(L("Příručka RYRY")) { openManual() }.keyboardShortcut("?", modifiers: .command)
                Button(L("Přehrát ukázkový signál")) { playDemo() }
                Divider()
                Button(L("Web RYRY")) { openWeb("") }
                Button(L("Podpora")) { openWeb("support/") }
                Button(L("Ochrana osobních údajů")) { openWeb("privacy/") }
            }
            CommandGroup(replacing: .newItem) {
                Button(L("Nový log…")) { FileActions.newLog(model) }.keyboardShortcut("n", modifiers: .command)
                Button(L("Otevřít log…")) { FileActions.openLog(model) }.keyboardShortcut("o", modifiers: .command)
                Menu(L("Otevřít nedávný log")) {
                    ForEach(model.settings.log.recent, id: \.self) { p in
                        Button((p as NSString).lastPathComponent + " — " + ((p as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath) {
                            FileActions.openLog(model, url: URL(fileURLWithPath: p))
                        }.disabled(p == model.logLocation.displayPath)
                    }
                }.disabled(model.settings.log.recent.isEmpty)
                Button(L("Uložit log jako…")) { FileActions.saveLogAs(model) }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button(L("Exportovat ADIF…")) { FileActions.exportADIF(model) }
                Button(L("Importovat ADIF…")) { FileActions.importADIF(model) }
                Button(L("Importovat z MMTTY…")) { FileActions.importMMTTY(model) }
                Button(L("Zálohovat log teď")) { FileActions.backupLog(model) }
                Button(L("Otevřít složku záloh")) { FileActions.openBackups(model) }
                Divider()
            }
            CommandGroup(after: .newItem) {
                Button(L("Uložit příjem do souboru…")) { FileActions.saveRxWindow(model) }
                Toggle(L("Průběžně zapisovat příjem do souboru"),
                       isOn: Binding(get: { model.settings.log.rxText }, set: { model.setRxTextLog($0) }))
                Divider()
                Menu(L("Přehrát WAV do příjmu")) {
                    ForEach([(1.0, L("Reálný čas")), (4.0, L("4× rychleji")), (0.0, L("Co nejrychleji"))], id: \.0) { sp in
                        Button(sp.1 + "…") { playWAV(speed: sp.0) }
                    }
                }
                Button(model.wavPaused ? L("Pokračovat v přehrávání") : L("Pozastavit přehrávání")) {
                    Task { await model.pauseWAV(!model.wavPaused) }
                }.disabled(!model.wavPlaying)
                Button(L("Převinout na začátek")) { Task { await model.seekWAV(0) } }.disabled(!model.wavPlaying)
                Button(L("Zastavit přehrávání WAV")) { Task { await model.stopWAV() } }.disabled(!model.wavPlaying)
                if model.recordingURL == nil {
                    Button(L("Nahrávat příjem do WAV…")) { FileActions.recordWAV(model) }
                } else {
                    Button(L("Zastavit nahrávání WAV")) { Task { await model.stopRecordingWAV() } }
                }
                Divider()
                Button(L("Nastavení zvuku systému…")) { FileActions.openSoundSettings() }
                Button(L("Audio MIDI Setup…")) { FileActions.openAudioMIDISetup() }
            }
            CommandGroup(after: .toolbar) {
                Button(L("Větší písmo")) { Task { await model.changeTextSize(by: 1) } }.keyboardShortcut("+", modifiers: .command)
                Button(L("Menší písmo")) { Task { await model.changeTextSize(by: -1) } }.keyboardShortcut("-", modifiers: .command)
                Button(L("Výchozí velikost písma")) { Task { await model.changeTextSize(by: nil) } }.keyboardShortcut("0", modifiers: .command)
                Divider()
                Button(L("Větší rozhraní")) { Task { await model.changeUISize(by: 1) } }.keyboardShortcut("+", modifiers: [.command, .control])
                Button(L("Menší rozhraní")) { Task { await model.changeUISize(by: -1) } }.keyboardShortcut("-", modifiers: [.command, .control])
                Divider()
            }
            CommandGroup(after: .windowArrangement) {
                Button("Log") { openWindow(id: "log") }.shortcut(model.settings.binding(for: .openLog))
                Button(L("Exportovat Cabrillo…")) { exportCabrillo(model) }
                Button(L("Scope demodulátoru")) { openWindow(id: "scope") }
                Button(L("Spoty")) { openWindow(id: "spots") }
                Button(L("Filtr pásem")) { openWindow(id: SpotFilterWindowID.bands) }
                Button(L("Filtr módů")) { openWindow(id: SpotFilterWindowID.modes) }
                Button(L("Band mapa")) { openWindow(id: "bandmapwindow") }
                Button(L("Násobiče")) { openWindow(id: "multipliers") }
                Button(L("Skóre")) { openWindow(id: "score") }
                Divider()
                Toggle(L("2. dekodér"), isOn: Binding(get: { model.settings.decoders.secondEnabled },
                                                      set: { v in Task { await model.setSecondDecoder(v) } }))
                Toggle(L("Vícekanálové dekódování"), isOn: Binding(get: { model.settings.decoders.channelsEnabled },
                                                                   set: { v in Task { await model.setChannelDecoding(v) } }))
                Button(L("Kanály")) { openWindow(id: "channels") }
            }
        }
        Window("Log – " + model.settings.log.name, id: "log") { LogWindow(model: model).environment(\.showHints, model.settings.display.showHints).uiSized(model.settings.display.uiSize) }
        Window(L("Scope demodulátoru"), id: "scope") {
            ScopeWindow(model: model).environment(\.showHints, model.settings.display.showHints).uiSized(model.settings.display.uiSize)
        }
            .windowResizability(.contentSize)
        Window(L("Spoty"), id: "spots") {
            SpotsWindow(model: model).environment(\.showHints, model.settings.display.showHints).uiSized(model.settings.display.uiSize)
        }
        // filtr zobrazení spotů ve dvou samostatných oknech (zaškrtávátka pásem a skupin módů)
        Window(L("Filtr pásem"), id: SpotFilterWindowID.bands) {
            SpotBandFilterWindow(model: model).environment(\.showHints, model.settings.display.showHints).uiSized(model.settings.display.uiSize)
        }
        .windowResizability(.contentSize)
        Window(L("Filtr módů"), id: SpotFilterWindowID.modes) {
            SpotModeFilterWindow(model: model).environment(\.showHints, model.settings.display.showHints).uiSized(model.settings.display.uiSize)
        }
        .windowResizability(.contentSize)
        Window(L("Band mapa"), id: "bandmapwindow") {
            BandMapWindow(model: model).environment(\.showHints, model.settings.display.showHints).uiSized(model.settings.display.uiSize)
        }
        Window(L("Násobiče"), id: "multipliers") {
            MultipliersWindow(model: model).environment(\.showHints, model.settings.display.showHints).uiSized(model.settings.display.uiSize)
        }
        Window(L("Skóre"), id: "score") {
            ScoreWindow(model: model).environment(\.showHints, model.settings.display.showHints).uiSized(model.settings.display.uiSize)
        }
        Window(L("Kanály"), id: "channels") {
            ChannelsWindow(model: model).environment(\.showHints, model.settings.display.showHints).uiSized(model.settings.display.uiSize)
        }
        Settings { SettingsView(model: model).environment(\.showHints, model.settings.display.showHints).uiSized(model.settings.display.uiSize) }
    }
}
