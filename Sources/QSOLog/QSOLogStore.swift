// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation

public enum QSOLogError: Error, Equatable, Sendable { case notFound(UUID), io(String) }

/// Log: incremental write into .jsonl (source of truth) and .adi; edit/delete by an atomic rewrite.
public actor QSOLogStore {
    public let adifURL: URL
    public let jsonlURL: URL
    public private(set) var records: [QSORecord] = []
    public private(set) var warnings: [String] = []
    /// Corrupted JSONL lines – they are preserved on every rewrite (they can be fixed by hand).
    private var badLines: [String] = []
    /// The log could not be read → writes are refused so that it does not get overwritten.
    private var readFailed = false
    /// JSONL size and modification time after our own last read/write – detects a change by another instance
    /// (e.g. a long upload to LoTW across a restart after Apply).
    private var signature: [Int] = []

    /// ISO 8601 with milliseconds; also reads the older notation without fractions.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { d, enc in
            var c = enc.singleValueContainer(); try c.encode(ISODates.format(d))
        }
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            guard let date = ISODates.parse(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "datum \(s)"))
            }
            return date
        }
        return d
    }()

    public init(directory: URL, baseName: String = "RYRY") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        adifURL = directory.appendingPathComponent(baseName + ".adi")
        jsonlURL = directory.appendingPathComponent(baseName + ".jsonl")
        let fm = FileManager.default
        if fm.fileExists(atPath: jsonlURL.path) {
            do {
                var data = try Data(contentsOf: jsonlURL)
                // truncated last line (an outage) → terminate it so that the next write starts on a new line
                if let last = data.last, last != UInt8(ascii: "\n") {
                    data.append(UInt8(ascii: "\n"))
                    try? Self.appendRaw(Data([UInt8(ascii: "\n")]), to: jsonlURL)
                    warnings.append("\(jsonlURL.lastPathComponent): poslední řádek byl neúplný")
                }
                var n = 0
                for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
                    n += 1
                    if line.isEmpty { continue }
                    if let r = try? Self.decoder.decode(QSORecord.self, from: Data(line)) { records.append(r) }
                    else {
                        badLines.append(String(decoding: line, as: UTF8.self))
                        warnings.append("\(jsonlURL.lastPathComponent): řádek \(n) je poškozený (zachován v souboru)")
                    }
                }
            } catch {
                readFailed = true
                warnings.append("\(jsonlURL.lastPathComponent) nelze přečíst: \(error.localizedDescription) – zápis do logu vypnut")
            }
        }
        if !readFailed, !records.isEmpty, !Self.consistent(adifURL, records) {
            do { try Self.atomicWrite(ADIF.header() + records.map(ADIF.record).joined(), to: adifURL); warnings.append("\(adifURL.lastPathComponent) neodpovídal JSONL – přegenerován") }
            catch { warnings.append("\(adifURL.lastPathComponent) nelze přegenerovat: \(error)") }
        }
        signature = Self.signatureOf(jsonlURL)
    }

    private func fileSignature() -> [Int] { Self.signatureOf(jsonlURL) }

    static func signatureOf(_ url: URL) -> [Int] {
        guard let at = try? FileManager.default.attributesOfItem(atPath: url.path) else { return [] }
        let size = (at[.size] as? NSNumber)?.intValue ?? -1
        let mtime = Int(((at[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) * 1_000_000)
        return [size, mtime]
    }

    /// Before rewriting the log: if another instance has changed the file meanwhile, load it again (otherwise the rewrite
    /// would lose QSOs written elsewhere).
    private func refreshIfChangedExternally() {
        guard !readFailed, fileSignature() != signature, let d = try? Data(contentsOf: jsonlURL) else { return }
        var recs: [QSORecord] = [], bad: [String] = []
        for line in d.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            if let r = try? Self.decoder.decode(QSORecord.self, from: Data(line)) { recs.append(r) }
            else { bad.append(String(decoding: line, as: UTF8.self)) }
        }
        records = recs; badLines = bad
        signature = fileSignature()
    }

    private static func appendRaw(_ d: Data, to url: URL) throws {
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        try h.seekToEnd(); try h.write(contentsOf: d); try h.synchronize()
    }

    private func checkWritable() throws {
        if readFailed { throw QSOLogError.io("\(jsonlURL.lastPathComponent) nelze přečíst – zápis odmítnut") }
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

    public func append(_ rec: QSORecord) throws {
        var r = rec; r.call = QSORecord.normalizeCall(r.call)
        try checkWritable()
        let external = fileSignature() != signature
        try appendLine(try jsonLine(r), to: jsonlURL)        // source of truth – an error means the QSO is not logged
        records.append(r)
        if external { signature = [] } else { signature = fileSignature() }   // external change → the next rewrite reloads
        do { try appendLine(ADIF.record(r), to: adifURL, header: ADIF.header()) }
        catch { warnings.append("ADIF zápis selhal (\(error)); JSONL je v pořádku, ADIF se přegeneruje") }
    }

    private func rewrite(_ recs: [QSORecord]) throws {
        try checkWritable()
        let jsonl = try recs.map(jsonLine).joined() + badLines.map { $0 + "\n" }.joined()
        try atomicWrite(jsonl, to: jsonlURL)
        records = recs
        signature = fileSignature()
        do { try atomicWrite(ADIF.header() + recs.map(ADIF.record).joined(), to: adifURL) }
        catch { warnings.append("ADIF přepis selhal (\(error)); JSONL je v pořádku") }
    }

    private func atomicWrite(_ text: String, to url: URL) throws { try Self.atomicWrite(text, to: url) }

    private static func consistent(_ adifURL: URL, _ records: [QSORecord]) -> Bool {
        guard let text = try? String(contentsOf: adifURL, encoding: .utf8) else { return records.isEmpty }
        return ADIF.parse(text).compactMap { $0["APP_MMTTY4MAC_ID"] } == records.map(\.id.uuidString)
    }

    private static func atomicWrite(_ text: String, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try Data(text.utf8).write(to: tmp)
            let h = try FileHandle(forWritingTo: tmp); try h.synchronize(); try h.close()   // fsync before the swap
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

    /// Bulk import (ADIF): a dupe = the same id, or the same call, band and mode with a time within ±1 min.
    public func importRecords(_ recs: [QSORecord]) throws -> (added: Int, duplicates: Int) {
        refreshIfChangedExternally()
        var all = records, added = 0, dup = 0
        var ids = Set(all.map(\.id))
        for var r in recs {
            r.call = QSORecord.normalizeCall(r.call)
            if ids.contains(r.id) || all.contains(where: { Self.sameQSO($0, r) }) { dup += 1; continue }
            all.append(r); ids.insert(r.id); added += 1
        }
        if added > 0 { try rewrite(all.sorted { $0.timeOn < $1.timeOn }) }
        return (added, dup)
    }

    static func sameQSO(_ a: QSORecord, _ b: QSORecord) -> Bool {
        a.call == b.call && a.band == b.band && a.mode == b.mode && abs(a.timeOn.timeIntervalSince(b.timeOn)) <= 60
    }

    public func update(_ rec: QSORecord) throws {
        refreshIfChangedExternally()
        var r = rec; r.call = QSORecord.normalizeCall(r.call)
        guard let i = records.firstIndex(where: { $0.id == r.id }) else { throw QSOLogError.notFound(r.id) }
        var recs = records; recs[i] = r
        try rewrite(recs)
    }

    /// Marks the QSOs as uploaded to a service (a single log rewrite). Returns the number of changed records.
    @discardableResult
    public func markUploaded(ids: [UUID], target: UploadTarget, at: Date = Date()) throws -> Int {
        refreshIfChangedExternally()
        let set = Set(ids)
        var recs = records, n = 0
        for i in recs.indices where set.contains(recs[i].id) { recs[i].markUploaded(target, at: at); n += 1 }
        if n > 0 { try rewrite(recs) }
        return n
    }

    public func delete(id: UUID) throws {
        refreshIfChangedExternally()
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

    /// Does the ADIF contain exactly the same IDs as the JSONL (in the same order)?
    public func isADIFConsistent() -> Bool { Self.consistent(adifURL, records) }

    public func rebuildADIF() throws {
        try atomicWrite(ADIF.header() + records.map(ADIF.record).joined(), to: adifURL)
    }
}

/// ISO 8601 (UTC) with and without milliseconds.
public enum ISODates {
    nonisolated(unsafe) static let frac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) static let plain = ISO8601DateFormatter()
    public static func format(_ d: Date) -> String { frac.string(from: d) }
    public static func parse(_ s: String) -> Date? { frac.date(from: s) ?? plain.date(from: s) }
}
