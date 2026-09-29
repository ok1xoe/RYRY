// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import AppViews
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("mmtty4mac", id: "main") {
            MainView(model: model)
                .task {
                    delegate.model = model
                    if model.state == .stopped { await model.start() }
                }
        }
        .commands {
            CommandMenu("Vysílání") {
                Button("TX / RX") { Task { await model.toggleTx() } }.keyboardShortcut("t", modifiers: .command)
                Button("Okamžitě RX") { Task { await model.rxNow() } }.keyboardShortcut(".", modifiers: .command)
                Button("Ladění (tune)") { Task { await model.tune() } }
                Button("Zastavit opakování makra") { Task { await model.stopMacro() } }
                Divider()
                Button("Zalogovat QSO") { Task { await model.logQSO() } }.keyboardShortcut("l", modifiers: .command)
                Button("Vymazat QSO") { Task { await model.clearQSO() } }
                Button("Vymazat příjem") { model.clearRx() }.keyboardShortcut("k", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Menu("Přehrát WAV do příjmu") {
                    ForEach([(1.0, "Reálný čas"), (4.0, "4× rychleji"), (0.0, "Co nejrychleji")], id: \.0) { sp in
                        Button(sp.1 + "…") { playWAV(speed: sp.0) }
                    }
                }
                Button("Zastavit přehrávání WAV") { model.stopWAV() }.disabled(!model.wavPlaying)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Log") { openWindow(id: "log") }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Exportovat Cabrillo…") { exportCabrillo(model) }
            }
        }
        Window("Log", id: "log") { LogWindow(model: model) }
        Settings { SettingsView(model: model) }
    }
}
