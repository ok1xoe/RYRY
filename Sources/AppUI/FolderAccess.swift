// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Settings

/// Asks the user for a folder (the real one is an NSOpenPanel in AppViews).
public protocol FolderAccessPrompt: Sendable {
    /// `suggested` is preselected; nil = the user cancelled.
    @MainActor func requestFolder(suggested: URL, message: String) async -> URL?
}

/// A prompt that never gets an answer (the default until the app installs the real panel; tests).
public struct NoFolderPrompt: FolderAccessPrompt {
    public init() {}
    public func requestFolder(suggested: URL, message: String) async -> URL? { nil }
}

/// Makes and resolves bookmark data (security-scoped in the app, fake in tests).
public protocol BookmarkCodec: Sendable {
    func make(_ url: URL) throws -> Data
    func resolve(_ data: Data) throws -> (url: URL, stale: Bool)
}

public struct SecurityScopedCodec: BookmarkCodec {
    public init() {}
    public func make(_ url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    public func resolve(_ data: Data) throws -> (url: URL, stale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }
}

/// Access to folders outside the App Store sandbox container. The sandbox lets the app into a folder only
/// after the user chose it in an open panel; a bookmark keeps that access across restarts.
@MainActor public final class FolderAccess {
    let prompt: any FolderAccessPrompt
    let codec: any BookmarkCodec
    let sandboxed: Bool
    /// The container's home (`NSHomeDirectory()` in the sandbox) - folders inside it need no permission.
    public let containerHome: String
    /// Folders whose security-scoped access was started (stopped by `stopAll`).
    private var active: [URL] = []

    public init(prompt: any FolderAccessPrompt, codec: any BookmarkCodec = SecurityScopedCodec(),
                sandboxed: Bool = FolderAccess.isSandboxed, containerHome: String = NSHomeDirectory()) {
        self.prompt = prompt; self.codec = codec; self.sandboxed = sandboxed; self.containerHome = containerHome
    }

    public nonisolated static var isSandboxed: Bool { ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil }

    /// A folder URL the app may use for `path`, asking the user when there is no valid bookmark. The user may pick
    /// a different folder - the returned URL is what counts. nil = the user refused. `bookmarks` is updated in place.
    public func acquire(_ path: String, bookmarks: inout FolderBookmarks, message: String) async -> URL? {
        let key = FolderBookmarks.key(path)
        guard sandboxed, !key.hasPrefix(FolderBookmarks.key(containerHome) + "/") else { return URL(fileURLWithPath: key) }
        if let data = bookmarks.bookmark(for: key), let r = try? codec.resolve(data), FolderBookmarks.key(r.url.path) == key {
            if r.stale, let fresh = try? codec.make(r.url) { bookmarks.set(fresh, for: key) }
            start(r.url)
            return r.url
        }
        bookmarks.remove(key)                                    // missing, broken or moved elsewhere
        guard let chosen = await prompt.requestFolder(suggested: URL(fileURLWithPath: key), message: message) else { return nil }
        var result = chosen
        // The wanted folder does not exist yet (a new ~/Documents/RYRY), so the panel opened on its parent. Choosing the
        // parent grants it; create the folder inside instead of scattering the log files over the parent.
        if !FileManager.default.fileExists(atPath: key),
           FolderBookmarks.key(chosen.path) == FolderBookmarks.key((key as NSString).deletingLastPathComponent) {
            start(chosen)
            if (try? FileManager.default.createDirectory(atPath: key, withIntermediateDirectories: true)) != nil {
                result = URL(fileURLWithPath: key)
            }
        }
        if let data = try? codec.make(result) { bookmarks.set(data, for: result.path) }
        start(result)
        return result
    }

    /// A single file outside the container (e.g. the call history) - usable after a relaunch only through the bookmark
    /// made when the user chose it. nil = no valid bookmark: the user has to choose the file again.
    public func accessFile(_ path: String, bookmark: Data?) -> URL? {
        let key = FolderBookmarks.key(path)
        guard sandboxed, !key.hasPrefix(FolderBookmarks.key(containerHome) + "/") else { return URL(fileURLWithPath: key) }
        guard let bookmark, let r = try? codec.resolve(bookmark), FolderBookmarks.key(r.url.path) == key else { return nil }
        start(r.url)
        return r.url
    }

    private func start(_ url: URL) {
        if url.startAccessingSecurityScopedResource() { active.append(url) }
    }

    public func stopAll() {
        for u in active { u.stopAccessingSecurityScopedResource() }
        active.removeAll()
    }
}
