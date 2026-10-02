// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import Localization

/// Asks for a folder with an open panel - in the sandbox the only way to get into a folder outside the container.
public struct FolderAccessPanel: FolderAccessPrompt {
    public init() {}
    @MainActor public func requestFolder(suggested: URL, message: String) async -> URL? {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.allowsMultipleSelection = false
        p.directoryURL = FileManager.default.fileExists(atPath: suggested.path) ? suggested : suggested.deletingLastPathComponent()
        p.message = message
        p.prompt = L("Povolit přístup")
        NSApp.activate(ignoringOtherApps: true)
        return p.runModal() == .OK ? p.url : nil
    }
}
