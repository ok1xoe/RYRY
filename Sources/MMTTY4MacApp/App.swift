// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
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

    /// Při ukončení vždy bezpečně RX, PTT off, zastavit API.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        Task { @MainActor in
            await model.shutdown(timeout: .seconds(3))      // RX + PTT off hned, stop max. 3 s
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Zavřením hlavního okna se aplikace ukončí (nesmí vysílat bez okna).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Otevře přibalenou HTML příručku v jazyce rozhraní (čeština, jinak angličtina).
@MainActor func openManual() {
    let lang = Localizer.shared.code == "cs" ? "cs" : "en"
    guard let r = Bundle.main.resourceURL?.appendingPathComponent("Help/\(lang)/index.html"),
          FileManager.default.fileExists(atPath: r.path) else { return }
    NSWorkspace.shared.open(r)
}

@MainActor func showAbout() {
    let credits = [
        L("RTTY pro macOS – nativní přepis MMTTY s API pro loggery (fldigi XML-RPC, JSON-RPC)."),
        "",
        L("Jádro demodulátoru a modulátoru: MMTTY © 2000–2013 Makoto Mori (JE3HHT), Nobuyuki Oba."),
        L("mmtty4mac © 2026 OK1XOE. Licence GNU LGPL v3 (COPYING, COPYING.LESSER)."),
        L("DXCC: cty.dat – Jim Reisert AD1C (country-files.com)."),
    ].joined(separator: "\n")
    let para = NSMutableParagraphStyle(); para.alignment = .center
    NSApp.orderFrontStandardAboutPanel(options: [
        .credits: NSAttributedString(string: credits, attributes: [.font: NSFont.systemFont(ofSize: 11), .paragraphStyle: para]),
    ])
    NSApp.activate(ignoringOtherApps: true)
}

@main
struct MMTTY4MacApp: App {
    @MainActor func playWAV(speed: Double) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.wav]
        guard p.runModal() == .OK, let url = p.url else { return }
        Task { @MainActor in
            do { try await model.playWAV(url, speed: speed) }
            catch { NSAlert(error: error).runModal() }
        }
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var model = AppModel(alertSink: SystemAlertSink())
    @State private var updates = UpdateModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    /// Jazyk rozhraní z minulého spuštění (spouštěcí parametr -language en přepíše volbu).
    /// Hlídá složku jazyků – uložený soubor se projeví hned.
    private let languageWatcher: LanguageWatcher

    init() {
        let lib = LanguageLibrary.standard()
        lib.seedUserDirectory()                  // cs.json, en.json do složky jazyků (k úpravám)
        lib.restore()
        languageWatcher = LanguageWatcher(library: lib)
        languageWatcher.start()
    }

    var body: some Scene {
        Window("mmtty4mac", id: "main") {
            MainView(model: model)
                .environment(\.showHints, model.settings.display.showHints)
                .task {
                    delegate.model = model
                    // spouštěcí parametr -openSettings YES (+ -settingsTab N): otevřít Nastavení (snímky obrazovky, podpora)
                    if UserDefaults.standard.bool(forKey: "openSettings") { openSettings() }
                    // -switchLanguage cs: za 4 s přepnout jazyk jako výběrem v Nastavení (zkouška živého přepnutí)
                    if let c = UserDefaults.standard.string(forKey: "switchLanguage") {
                        try? await Task.sleep(for: .seconds(4))
                        LanguageLibrary.standard().select(c)
                    }
                    // -openWindow log,scope: otevřít okna (snímky obrazovky do dokumentace)
                    for id in (UserDefaults.standard.string(forKey: "openWindow") ?? "").split(separator: ",") {
                        openWindow(id: String(id))
                    }
                    updates.showWindow = { openWindow(id: "update") }
                    if model.state == .stopped { await model.start() }
                    await updates.checkAtLaunch(enabled: model.settings.updates.autoCheck)
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
            }
            CommandGroup(replacing: .appInfo) {
                Button(L("O aplikaci mmtty4mac")) { showAbout() }
                Button(L("Zkontrolovat aktualizace…")) { Task { await updates.checkManually() } }
            }
            CommandGroup(replacing: .help) {
                Button(L("Příručka mmtty4mac")) { openManual() }.keyboardShortcut("?", modifiers: .command)
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
            CommandGroup(after: .windowArrangement) {
                Button("Log") { openWindow(id: "log") }.shortcut(model.settings.binding(for: .openLog))
                Button(L("Exportovat Cabrillo…")) { exportCabrillo(model) }
                Button(L("Scope demodulátoru")) { openWindow(id: "scope") }
                Button(L("Spoty")) { openWindow(id: "spots") }
                Divider()
                Toggle(L("2. dekodér"), isOn: Binding(get: { model.settings.decoders.secondEnabled },
                                                      set: { v in Task { await model.setSecondDecoder(v) } }))
                Toggle(L("Vícekanálové dekódování"), isOn: Binding(get: { model.settings.decoders.channelsEnabled },
                                                                   set: { v in Task { await model.setChannelDecoding(v) } }))
                Button(L("Kanály")) { openWindow(id: "channels") }
            }
        }
        Window("Log – " + model.settings.log.name, id: "log") { LogWindow(model: model).environment(\.showHints, model.settings.display.showHints) }
        Window(L("Scope demodulátoru"), id: "scope") {
            ScopeWindow(model: model).environment(\.showHints, model.settings.display.showHints)
        }
        Window(L("Aktualizace"), id: "update") { UpdateWindow(model: updates) }
            .windowResizability(.contentSize)
        Window(L("Spoty"), id: "spots") {
            SpotsWindow(model: model).environment(\.showHints, model.settings.display.showHints)
        }
        Window(L("Kanály"), id: "channels") {
            ChannelsWindow(model: model).environment(\.showHints, model.settings.display.showHints)
        }
        Settings { SettingsView(model: model).environment(\.showHints, model.settings.display.showHints) }
    }
}
