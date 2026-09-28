// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

public enum QSOLogError: Error, Equatable, Sendable { case notFound(UUID), io(String) }

/// Log: přírůstkový zápis do .jsonl (zdroj pravdy) a .adi; oprava/mazání atomickým přepsáním.
public actor QSOLogStore {
    public let adifURL: URL
    public let jsonlURL: URL
    public private(set) var records: [QSORecord] = []
    public private(set) var warnings: [String] = []

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return e
    }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    public init(directory: URL, baseName: String = "mmtty4mac") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        adifURL = directory.appendingPathComponent(baseName + ".adi")
        jsonlURL = directory.appendingPathComponent(baseName + ".jsonl")
        if let data = try? Data(contentsOf: jsonlURL) {
            var recs: [QSORecord] = [], warns: [String] = []
            for (n, line) in data.split(separator: UInt8(ascii: "\n")).enumerated() where !line.isEmpty {
                if let r = try? Self.decoder.decode(QSORecord.self, from: Data(line)) { recs.append(r) }
                else { warns.append("\(jsonlURL.lastPathComponent): řádek \(n + 1) je poškozený, přeskočen") }
            }
            records = recs; warnings = warns
        }
    }

    private func appendLine(_ text: String, to url: URL, header: String? = nil) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            guard fm.createFile(atPath: url.path, contents: Data((header ?? "").utf8)) else {
                throw QSOLogError.io("nelze vytvořit \(url.path)")
            }
        }
        do {
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: Data(text.utf8))
            try h.synchronize()                                 // fsync
        } catch { throw QSOLogError.io("\(url.lastPathComponent): \(error)") }
    }

    private func jsonLine(_ r: QSORecord) throws -> String {
        guard let d = try? Self.encoder.encode(r) else { throw QSOLogError.io("JSON") }
        return String(decoding: d, as: UTF8.self) + "\n"
    }

    public func append(_ r: QSORecord) throws {
        try appendLine(try jsonLine(r), to: jsonlURL)
        try appendLine(ADIF.record(r), to: adifURL, header: ADIF.header())
        records.append(r)
    }

    private func rewrite(_ recs: [QSORecord]) throws {
        let jsonl = try recs.map(jsonLine).joined()
        let adif = ADIF.header() + recs.map(ADIF.record).joined()
        try atomicWrite(jsonl, to: jsonlURL)
        try atomicWrite(adif, to: adifURL)
        records = recs
    }

    private func atomicWrite(_ text: String, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try Data(text.utf8).write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw QSOLogError.io("\(url.lastPathComponent): \(error)")
        }
    }

    public func update(_ r: QSORecord) throws {
        guard let i = records.firstIndex(where: { $0.id == r.id }) else { throw QSOLogError.notFound(r.id) }
        var recs = records; recs[i] = r
        try rewrite(recs)
    }

    public func delete(id: UUID) throws {
        guard records.contains(where: { $0.id == id }) else { throw QSOLogError.notFound(id) }
        try rewrite(records.filter { $0.id != id })
    }

    public func query(call: String? = nil, from: Date? = nil, to: Date? = nil, limit: Int? = nil) -> [QSORecord] {
        var r = records.sorted { $0.timeOn > $1.timeOn }
        if let call { let c = call.uppercased(); r = r.filter { $0.call == c } }
        if let from { r = r.filter { $0.timeOn >= from } }
        if let to { r = r.filter { $0.timeOn <= to } }
        if let limit { r = Array(r.prefix(max(0, limit))) }
        return r
    }

    public func previous(call: String) -> [QSORecord] {
        let base = QSORecord.baseCall(call)
        return records.filter { QSORecord.baseCall($0.call) == base }.sorted { $0.timeOn > $1.timeOn }
    }

    /// ADIF obsahuje přesně stejná ID jako JSONL (ve stejném pořadí)?
    public func isADIFConsistent() -> Bool {
        guard let text = try? String(contentsOf: adifURL, encoding: .utf8) else { return records.isEmpty }
        return ADIF.parse(text).compactMap { $0["APP_MMTTY4MAC_ID"] } == records.map(\.id.uuidString)
    }

    public func rebuildADIF() throws {
        try atomicWrite(ADIF.header() + records.map(ADIF.record).joined(), to: adifURL)
    }
}
