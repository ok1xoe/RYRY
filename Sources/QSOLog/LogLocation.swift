// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation

/// Log location: folder and name. A log consists of `<name>.jsonl` (source of truth), `<name>.adi` (derived ADIF)
/// and the QTC series (`<name>-qtc.jsonl`; the default log – "RYRY", formerly "mmtty4mac" – uses `qtc.jsonl`).
public struct LogLocation: Sendable, Equatable {
    public enum LocationError: Error, Equatable, LocalizedError {
        case exists(String), same
        public var errorDescription: String? {
            switch self {
            case .exists(let f): return "Soubor \(f) už existuje."
            case .same: return "Cíl je stejný jako současný log."
            }
        }
    }

    public static let defaultName = "RYRY"
    /// The default log name before the rename (its QTC file is `qtc.jsonl` as well).
    public static let legacyDefaultName = "mmtty4mac"
    public var directory: URL
    public var name: String

    /// Always stored as a directory URL: `URL(fileURLWithPath:)` adds the trailing slash only when the folder exists,
    /// and without it the same folder would not compare equal (`copy(to:)` would miss "the same as the current log").
    public init(directory: URL, name: String) {
        self.directory = URL(fileURLWithPath: directory.standardizedFileURL.path, isDirectory: true)
        self.name = name
    }

    /// From the selected file (`.adi`, `.adif`, `.jsonl` or without an extension).
    public init(file: URL) {
        var n = file.lastPathComponent
        for ext in [".jsonl", ".adif", ".adi"] where n.lowercased().hasSuffix(ext) { n = String(n.dropLast(ext.count)); break }
        self.init(directory: file.deletingLastPathComponent(), name: n)
    }

    public var jsonlURL: URL { directory.appendingPathComponent(name + ".jsonl") }
    public var adifURL: URL { directory.appendingPathComponent(name + ".adi") }
    public var qtcFileName: String { name == Self.defaultName || name == Self.legacyDefaultName ? "qtc.jsonl" : name + "-qtc.jsonl" }
    public var qtcURL: URL { directory.appendingPathComponent(qtcFileName) }
    /// Path for display and for the list of recent logs (ADIF – the one the user knows).
    public var displayPath: String { adifURL.path }

    public struct OpenResult: Sendable { public var imported = 0; public var skipped = 0; public var backup: URL? }

    /// Before opening: ADIF without JSONL (log from another program) is converted to JSONL, the original saved as `.adi.orig`
    /// (the log then rewrites the ADIF from its own records).
    public func prepareForOpen() async throws -> OpenResult {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: jsonlURL.path) else { return OpenResult() }
        var src = adifURL
        if !fm.fileExists(atPath: src.path) {
            let alt = directory.appendingPathComponent(name + ".adif")
            guard fm.fileExists(atPath: alt.path) else { return OpenResult() }         // a new empty log
            src = alt
        }
        let data = try Data(contentsOf: src)
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let parsed = ADIF.importRecords(text)
        var backup = directory.appendingPathComponent(src.lastPathComponent + ".orig")
        var i = 2
        while fm.fileExists(atPath: backup.path) { backup = directory.appendingPathComponent(src.lastPathComponent + ".orig\(i)"); i += 1 }
        try fm.copyItem(at: src, to: backup)
        if src != adifURL { try? fm.removeItem(at: adifURL) }
        let store = try QSOLogStore(directory: directory, baseName: name)
        let r = try await store.importRecords(parsed.records)
        if parsed.records.isEmpty { try? fm.removeItem(at: adifURL) }
        return OpenResult(imported: r.added, skipped: parsed.skipped + r.duplicates, backup: backup)
    }

    /// Copy of the log (JSONL, ADIF, QTC) under a different name or elsewhere. The destination must not exist.
    public func copy(to dst: LogLocation) throws {
        guard dst != self else { throw LocationError.same }
        let fm = FileManager.default
        for u in [dst.jsonlURL, dst.adifURL, dst.qtcURL] where fm.fileExists(atPath: u.path) {
            throw LocationError.exists(u.lastPathComponent)
        }
        try fm.createDirectory(at: dst.directory, withIntermediateDirectories: true)
        for (a, b) in [(jsonlURL, dst.jsonlURL), (adifURL, dst.adifURL), (qtcURL, dst.qtcURL)] where fm.fileExists(atPath: a.path) {
            try fm.copyItem(at: a, to: b)
        }
    }
}
