// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import Upload

/// Opens a file in TrustedQSL through Launch Services (the sandbox allows that, unlike running tqsl).
public struct WorkspaceTQSLOpener: TQSLOpener {
    public init() {}

    /// TrustedQSL by its bundle identifier, then any app named "tqsl" that opens the file, then the usual location.
    @MainActor static func tqslApp(for file: URL) -> URL? {
        let ws = NSWorkspace.shared
        if let u = ws.urlForApplication(withBundleIdentifier: "org.arrl.trustedqsl") { return u }
        if let u = ws.urlsForApplications(toOpen: file).first(where: { $0.lastPathComponent.lowercased().contains("tqsl") }) { return u }
        let std = URL(fileURLWithPath: "/Applications/TrustedQSL/tqsl.app")
        return FileManager.default.fileExists(atPath: std.path) ? std : nil
    }

    public func open(_ file: URL) async -> Bool {
        guard let app = await Self.tqslApp(for: file) else { return false }
        do {
            _ = try await NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            return true
        } catch { return false }
    }
}
