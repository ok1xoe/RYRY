// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Jedno QTC (WAE DX Contest): čas, značka a přijaté číslo dřívějšího spojení.
public struct QTCLine: Codable, Sendable, Equatable, Hashable {
    public var time: String        // HHMM UTC
    public var call: String
    public var serial: Int
    public init(time: String, call: String, serial: Int) {
        self.time = time; self.call = call.uppercased(); self.serial = serial
    }
}

/// Série QTC `QTC n/k` odeslaná nebo přijatá od jedné stanice.
public struct QTCSeries: Codable, Sendable, Equatable, Identifiable {
    public enum Direction: String, Codable, Sendable { case sent, received }
    public var id: UUID
    public var direction: Direction
    public var number: Int                 // pořadí série odesílatele (n v n/k)
    public var counterpart: String         // komu posíláno / od koho přijato
    public var time: Date                  // čas přenosu
    public var frequency: Double?          // Hz
    public var lines: [QTCLine]
    public var count: Int { lines.count }

    public init(id: UUID = UUID(), direction: Direction, number: Int, counterpart: String, time: Date,
                frequency: Double? = nil, lines: [QTCLine]) {
        self.id = id; self.direction = direction; self.number = number
        self.counterpart = counterpart.uppercased(); self.time = time; self.frequency = frequency; self.lines = lines
    }
}

/// Pravidla QTC (WAE RTTY): dvojice stanic ≤ 10 QTC (odeslaná + přijatá), každé QSO nahlásit jen jednou
/// a nikdy stanici, které se týká; do QTC jen spojení s přijatým číslem, nejstarší první.
public struct QTCPlanner: Sendable {
    public static let maxPerPair = 10
    public let records: [QSORecord]
    public let series: [QTCSeries]

    public init(records: [QSORecord], series: [QTCSeries]) { self.records = records; self.series = series }

    static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HHmm"; return f
    }()

    /// Kolik QTC už proběhlo s touto stanicí (odeslaná i přijatá, podle základní značky).
    public func exchanged(with call: String) -> Int {
        let b = QSORecord.baseCall(call)
        return series.filter { QSORecord.baseCall($0.counterpart) == b }.reduce(0) { $0 + $1.count }
    }

    /// Řádky, které lze této stanici ještě poslat (nejvýše 10 − už vyměněno).
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

    /// Pořadí příští odesílané série.
    public var nextSeriesNumber: Int { (series.filter { $0.direction == .sent }.map(\.number).max() ?? 0) + 1 }

    /// Body za QTC (1 za každé odeslané i přijaté).
    public var points: Int { series.reduce(0) { $0 + $1.count } }
}

/// Text QTC pro vysílání a rozbor přijatého textu.
public enum QTCText {
    public static func header(number: Int, count: Int) -> String { "QTC \(number)/\(count) QTC \(number)/\(count)" }
    public static func line(_ l: QTCLine) -> String { "\(l.time) \(l.call) \(String(format: "%03d", l.serial))" }
    public static func body(number: Int, lines: [QTCLine]) -> String {
        "\r\n" + header(number: number, count: lines.count) + "\r\n" + lines.map(line).joined(separator: "\r\n") + "\r\n"
    }
    /// Opakování řádku (na žádost AGN N) – pořadí a řádek dvakrát.
    public static func repeatLine(_ l: QTCLine, index: Int) -> String { "\r\n\(index) \(line(l)) \(line(l))\r\n" }

    /// `QTC 3/7` nebo `3/7` → (3, 7).
    public static func parseHeader(_ s: String) -> (Int, Int)? {
        guard let r = s.range(of: #"(\d{1,4})/(\d{1,2})"#, options: .regularExpression) else { return nil }
        let p = s[r].split(separator: "/")
        guard p.count == 2, let n = Int(p[0]), let k = Int(p[1]), n > 0, k > 0, k <= 10 else { return nil }
        return (n, k)
    }

    static func isTime(_ t: Substring) -> Bool {
        guard t.count == 4, let v = Int(t) else { return false }
        return v / 100 < 24 && v % 100 < 60
    }

    /// `1307 DA1AA 431` (i opakovaný) → řádek QTC.
    public static func parseLine(_ s: String) -> QTCLine? {
        let tok = s.uppercased().split(whereSeparator: { $0 == " " || $0 == "\r" || $0 == "\n" || $0 == "\t" })
        guard tok.count >= 3 else { return nil }
        for i in 0..<(tok.count - 2) where isTime(tok[i]) {
            let call = tok[i + 1], nr = tok[i + 2]
            guard call.count >= 3, call.contains(where: \.isLetter), call.contains(where: \.isNumber),
                  call.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "/" }),
                  nr.count <= 5, let n = Int(nr) else { continue }
            return QTCLine(time: String(tok[i]), call: String(call), serial: n)
        }
        return nil
    }
}

/// Úložiště sérií QTC (`qtc.jsonl` v adresáři logu, jedna série na řádek).
public actor QTCStore {
    public private(set) var series: [QTCSeries] = []
    private let url: URL
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .deferredToDate; return e }()

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("qtc.jsonl")
        if let d = try? Data(contentsOf: url) {
            let dec = JSONDecoder()
            series = d.split(separator: UInt8(ascii: "\n")).compactMap { try? dec.decode(QTCSeries.self, from: Data($0)) }
        }
    }

    public func append(_ s: QTCSeries) throws {
        var line = try Self.encoder.encode(s)
        line.append(UInt8(ascii: "\n"))
        if FileManager.default.fileExists(atPath: url.path) {
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.seekToEnd(); try h.write(contentsOf: line); try h.synchronize()
        } else {
            try line.write(to: url, options: .atomic)
        }
        series.append(s)
    }
}
