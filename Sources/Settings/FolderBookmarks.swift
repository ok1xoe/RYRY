// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation

/// Security-scoped bookmarks of folders outside the App Store sandbox container (the log folder and folders of
/// recent logs): with them the app keeps access to a folder the user chose once, across restarts.
public struct FolderBookmarks: Codable, Sendable, Equatable {
    /// Normalized folder path → bookmark data.
    public var entries: [String: Data] = [:]
    public init() {}

    /// The same folder written with a trailing slash or "." has one key.
    public static func key(_ path: String) -> String {
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        return p.count > 1 && p.hasSuffix("/") ? String(p.dropLast()) : p
    }
    public func bookmark(for path: String) -> Data? { entries[Self.key(path)] }
    public mutating func set(_ data: Data, for path: String) { entries[Self.key(path)] = data }
    public mutating func remove(_ path: String) { entries[Self.key(path)] = nil }

    enum CodingKeys: String, CodingKey { case entries }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        entries = c.tolerant(.entries, [:], d.warningSink, "log.bookmarks")
    }
}

/// The user's real home folder. In the sandbox `NSHomeDirectory()` is the app's container; the default log
/// folder must be where the user can find it.
public enum HomeDirectory {
    public static var real: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }
}
