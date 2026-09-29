// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Umístění logu: složka a název. Log tvoří `<název>.jsonl` (zdroj pravdy), `<název>.adi` (odvozený ADIF)
/// a série QTC (`<název>-qtc.jsonl`; výchozí log „mmtty4mac“ používá dosavadní `qtc.jsonl`).
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

    public static let defaultName = "mmtty4mac"
    public var directory: URL
    public var name: String

    public init(directory: URL, name: String) { self.directory = directory.standardizedFileURL; self.name = name }

    /// Z vybraného souboru (`.adi`, `.adif`, `.jsonl` nebo bez přípony).
    public init(file: URL) {
        var n = file.lastPathComponent
        for ext in [".jsonl", ".adif", ".adi"] where n.lowercased().hasSuffix(ext) { n = String(n.dropLast(ext.count)); break }
        self.init(directory: file.deletingLastPathComponent(), name: n)
    }

    public var jsonlURL: URL { directory.appendingPathComponent(name + ".jsonl") }
    public var adifURL: URL { directory.appendingPathComponent(name + ".adi") }
    public var qtcFileName: String { name == Self.defaultName ? "qtc.jsonl" : name + "-qtc.jsonl" }
    public var qtcURL: URL { directory.appendingPathComponent(qtcFileName) }
    /// Cesta pro zobrazení a seznam nedávných logů (ADIF – ten uživatel zná).
    public var displayPath: String { adifURL.path }

    public struct OpenResult: Sendable { public var imported = 0; public var skipped = 0; public var backup: URL? }

    /// Před otevřením: ADIF bez JSONL (log z jiného programu) se převede do JSONL, originál se uloží jako `.adi.orig`
    /// (log pak ADIF přepíše ze svých záznamů).
    public func prepareForOpen() async throws -> OpenResult {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: jsonlURL.path) else { return OpenResult() }
        var src = adifURL
        if !fm.fileExists(atPath: src.path) {
            let alt = directory.appendingPathComponent(name + ".adif")
            guard fm.fileExists(atPath: alt.path) else { return OpenResult() }         // nový prázdný log
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

    /// Kopie logu (JSONL, ADIF, QTC) pod jiným názvem nebo jinam. Cíl nesmí existovat.
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
