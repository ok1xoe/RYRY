// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// One QTC (WAE DX Contest): time, call and the received serial number of an earlier QSO.
public struct QTCLine: Codable, Sendable, Equatable, Hashable {
    public var time: String        // HHMM UTC
    public var call: String
    public var serial: Int
    public init(time: String, call: String, serial: Int) {
        self.time = time; self.call = call.uppercased(); self.serial = serial
    }
}

/// A QTC series `QTC n/k` sent to or received from a single station.
public struct QTCSeries: Codable, Sendable, Equatable, Identifiable {
    public enum Direction: String, Codable, Sendable { case sent, received }
    public var id: UUID
    public var direction: Direction
    public var number: Int                 // the sender's series number (n in n/k)
    public var counterpart: String         // to whom sent / from whom received
    public var time: Date                  // time of the transfer
    public var frequency: Double?          // Hz
    public var lines: [QTCLine]
    /// k from the "QTC n/k" header of a received series (when not all lines could be read); otherwise nil.
    public var declaredCount: Int?
    public var count: Int { lines.count }
    /// Group for Cabrillo "n/k".
    public var groupSize: Int { declaredCount ?? lines.count }

    public init(id: UUID = UUID(), direction: Direction, number: Int, counterpart: String, time: Date,
                frequency: Double? = nil, lines: [QTCLine], declaredCount: Int? = nil) {
        self.id = id; self.direction = direction; self.number = number
        self.counterpart = counterpart.uppercased(); self.time = time; self.frequency = frequency; self.lines = lines
        self.declaredCount = declaredCount
    }
}

/// QTC rules (WAE RTTY): a pair of stations ≤ 10 QTC (sent + received), report each QSO only once
/// and never to the station it concerns; only QSOs with a received serial number go into QTC, oldest first.
public struct QTCPlanner: Sendable {
    public static let maxPerPair = 10
    public let records: [QSORecord]
    public let series: [QTCSeries]

    /// `since` = contest start: older QSOs and series do not count (the log and qtc.jsonl are shared by all contests).
    /// Only RTTY QSOs with both a sent and a received serial number go into QTC.
    public init(records: [QSORecord], series: [QTCSeries], since: Date? = nil) {
        let from = since ?? .distantPast
        self.records = records.filter {
            $0.timeOn >= from && $0.mode.uppercased() == "RTTY" && $0.serialSent != nil && $0.serialRcvd != nil
        }
        self.series = series.filter { $0.time >= from }
    }

    static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HHmm"; return f
    }()

    /// How many QTC have already been exchanged with this station (sent and received, by base call).
    public func exchanged(with call: String) -> Int {
        let b = QSORecord.baseCall(call)
        return series.filter { QSORecord.baseCall($0.counterpart) == b }.reduce(0) { $0 + $1.count }
    }

    /// Lines that can still be sent to this station (at most 10 − already exchanged).
    public func available(for call: String) -> [QTCLine] {
        let room = Self.maxPerPair - exchanged(with: call)
        guard room > 0 else { return [] }
        let b = QSORecord.baseCall(call)
        let reported = Set(series.filter { $0.direction == .sent }.flatMap(\.lines))
        return records.sorted { $0.timeOn < $1.timeOn }.lazy
            .filter { $0.serialRcvd != nil && QSORecord.baseCall($0.call) != b }
            .map { QTCLine(time: Self.hhmm.string(from: $0.timeOn), call: $0.call, serial: $0.serialRcvd!) }
            .filter { !reported.contains($0) }
            .prefix(room).map { $0 }
    }

    /// Number of the next series to be sent.
    public var nextSeriesNumber: Int { (series.filter { $0.direction == .sent }.map(\.number).max() ?? 0) + 1 }

    /// Points for QTC (1 for each sent and each received one).
    public var points: Int { series.reduce(0) { $0 + $1.count } }
}

/// QTC text for transmit and parsing of the received text.
public enum QTCText {
    public static func header(number: Int, count: Int) -> String { "QTC \(number)/\(count) QTC \(number)/\(count)" }
    public static func line(_ l: QTCLine) -> String { "\(l.time) \(l.call) \(String(format: "%03d", l.serial))" }
    public static func body(number: Int, lines: [QTCLine]) -> String {
        "\r\n" + header(number: number, count: lines.count) + "\r\n" + lines.map(line).joined(separator: "\r\n") + "\r\n"
    }
    /// Repeating a line (on an AGN N request) – the index and the line twice.
    public static func repeatLine(_ l: QTCLine, index: Int) -> String { "\r\n\(index) \(line(l)) \(line(l))\r\n" }

    /// `QTC 3/7` or `3/7` → (3, 7).
    public static func parseHeader(_ s: String) -> (Int, Int)? {
        guard let r = s.range(of: #"(?<!\d)(\d{1,4})/(\d{1,2})(?!\d)"#, options: .regularExpression) else { return nil }
        let p = s[r].split(separator: "/")
        guard p.count == 2, let n = Int(p[0]), let k = Int(p[1]), n > 0, k > 0, k <= 10 else { return nil }
        return (n, k)
    }

    static func isTime(_ t: Substring) -> Bool {
        guard t.count == 4, let v = Int(t) else { return false }
        return v / 100 < 24 && v % 100 < 60
    }

    /// A time–call–serial triple starting at position `i` (nil = invalid).
    static func triple(_ tok: [Substring], _ i: Int) -> QTCLine? {
        guard i + 2 < tok.count, isTime(tok[i]) else { return nil }
        let call = tok[i + 1], nr = tok[i + 2]
        guard call.count >= 3, call.contains(where: \.isLetter), call.contains(where: \.isNumber),
              call.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "/" }),
              nr.count <= 5, let n = Int(nr) else { return nil }
        return QTCLine(time: String(tok[i]), call: String(call), serial: n)
    }

    static func tokens(_ s: String) -> [Substring] {
        s.uppercased().split(whereSeparator: { $0 == " " || $0 == "\r" || $0 == "\n" || $0 == "\t" })
    }

    /// `1307 DA1AA 431` (also repeated) → a QTC line. If the repeated copy differs, returns nil (request AGN).
    public static func parseLine(_ s: String) -> QTCLine? {
        let tok = tokens(s)
        var found: [QTCLine] = []
        var i = 0
        while i < tok.count {
            if let l = triple(tok, i) { found.append(l); i += 3 } else { i += 1 }
        }
        guard let first = found.first, found.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// A repeated line on an AGN request: `3 1310 OK2PBR 015 1310 OK2PBR 015` → (3, line).
    public static func parseIndexedLine(_ s: String) -> (Int, QTCLine)? {
        let tok = tokens(s)
        if tok.count >= 4, tok[0].count <= 2, let idx = Int(tok[0]), (1...10).contains(idx), triple(tok, 1) != nil,
           let l = parseLine(tok.dropFirst().joined(separator: " ")) {
            return (idx, l)
        }
        // line index glued to the preceding text ("BKKA8 0803 BY4AOM 176 0803 BY4AOM 176") – only when the line is
        // repeated twice (that is how AGN is sent), otherwise it could be confused with noise
        guard tok.count >= 7, triple(tok, 1) != nil, let l = parseLine(tok.dropFirst().joined(separator: " ")),
              triple(tok, 4) == l else { return nil }
        let digits = tok[0].reversed().prefix { $0.isNumber }
        guard (1...2).contains(digits.count), digits.count < tok[0].count,
              let idx = Int(String(digits.reversed())), (1...10).contains(idx) else { return nil }
        return (idx, l)
    }

    /// The line looks like a (corrupted) QTC attempt: at least 3 words, the first 2–5 characters mostly digits (time),
    /// the second with characters like a call – in order to preserve the line order.
    public static func looksLikeLine(_ s: String) -> Bool {
        guard !s.uppercased().contains("QTC") else { return false }
        let tok = tokens(s)
        guard tok.count >= 3, (2...5).contains(tok[0].count), tok[0].filter(\.isNumber).count >= 2,
              tok[1].count >= 3, tok[1].contains(where: \.isLetter) else { return false }
        return true
    }
}

/// Storage of QTC series (`qtc.jsonl` in the log directory, one series per line).
public actor QTCStore {
    public enum StoreError: Error, Equatable { case notFound(UUID) }
    public private(set) var series: [QTCSeries] = []
    /// Unreadable lines of the file (e.g. after a crash) – for display in the UI.
    public private(set) var warnings: [String] = []
    private let url: URL
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .deferredToDate; return e }()

    public init(directory: URL, fileName: String = "qtc.jsonl") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(fileName)
        if let d = try? Data(contentsOf: url) {
            let dec = JSONDecoder()
            for (i, line) in d.split(separator: UInt8(ascii: "\n")).enumerated() {
                if let s = try? dec.decode(QTCSeries.self, from: Data(line)) { series.append(s) }
                else { warnings.append("qtc.jsonl řádek \(i + 1) je nečitelný – přeskočen") }
            }
        }
    }

    /// Editing a series (counterpart, lines…) – the file is rewritten atomically.
    public func update(_ s: QTCSeries) throws {
        guard let i = series.firstIndex(where: { $0.id == s.id }) else { throw StoreError.notFound(s.id) }
        var copy = series; copy[i] = s
        try rewrite(copy)
    }

    public func delete(id: UUID) throws {
        guard series.contains(where: { $0.id == id }) else { throw StoreError.notFound(id) }
        try rewrite(series.filter { $0.id != id })
    }

    private func rewrite(_ all: [QTCSeries]) throws {
        var d = Data()
        for s in all { d.append(try Self.encoder.encode(s)); d.append(UInt8(ascii: "\n")) }
        try d.write(to: url, options: .atomic)
        series = all
    }

    public func append(_ s: QTCSeries) throws {
        var line = try Self.encoder.encode(s)
        line.append(UInt8(ascii: "\n"))
        if FileManager.default.fileExists(atPath: url.path) {
            let h = try FileHandle(forUpdating: url)
            defer { try? h.close() }
            let end = try h.seekToEnd()
            if end > 0 {                                   // incomplete last line (a crash) → terminate it first
                try h.seek(toOffset: end - 1)
                if h.readData(ofLength: 1) != Data([UInt8(ascii: "\n")]) { line.insert(UInt8(ascii: "\n"), at: 0) }
                try h.seekToEnd()
            }
            try h.write(contentsOf: line); try h.synchronize()
        } else {
            try line.write(to: url, options: .atomic)
        }
        series.append(s)
    }
}
