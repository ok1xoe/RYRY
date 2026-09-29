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
    /// k z hlavičky „QTC n/k“ u přijaté série (když se nepodařilo přečíst všechny řádky); jinak nil.
    public var declaredCount: Int?
    public var count: Int { lines.count }
    /// Skupina pro Cabrillo „n/k“.
    public var groupSize: Int { declaredCount ?? lines.count }

    public init(id: UUID = UUID(), direction: Direction, number: Int, counterpart: String, time: Date,
                frequency: Double? = nil, lines: [QTCLine], declaredCount: Int? = nil) {
        self.id = id; self.direction = direction; self.number = number
        self.counterpart = counterpart.uppercased(); self.time = time; self.frequency = frequency; self.lines = lines
        self.declaredCount = declaredCount
    }
}

/// Pravidla QTC (WAE RTTY): dvojice stanic ≤ 10 QTC (odeslaná + přijatá), každé QSO nahlásit jen jednou
/// a nikdy stanici, které se týká; do QTC jen spojení s přijatým číslem, nejstarší první.
public struct QTCPlanner: Sendable {
    public static let maxPerPair = 10
    public let records: [QSORecord]
    public let series: [QTCSeries]

    /// `since` = začátek závodu: starší QSO a série se nepočítají (log i qtc.jsonl jsou společné pro všechny závody).
    /// Do QTC jdou jen RTTY spojení s odeslaným i přijatým číslem.
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
        guard let r = s.range(of: #"(?<!\d)(\d{1,4})/(\d{1,2})(?!\d)"#, options: .regularExpression) else { return nil }
        let p = s[r].split(separator: "/")
        guard p.count == 2, let n = Int(p[0]), let k = Int(p[1]), n > 0, k > 0, k <= 10 else { return nil }
        return (n, k)
    }

    static func isTime(_ t: Substring) -> Bool {
        guard t.count == 4, let v = Int(t) else { return false }
        return v / 100 < 24 && v % 100 < 60
    }

    /// Trojice čas–značka–číslo od pozice `i` (nil = neplatná).
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

    /// `1307 DA1AA 431` (i opakovaný) → řádek QTC. Když se opakovaná kopie liší, vrátí nil (vyžádat AGN).
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

    /// Opakovaný řádek na žádost AGN: `3 1310 OK2PBR 015 1310 OK2PBR 015` → (3, řádek).
    public static func parseIndexedLine(_ s: String) -> (Int, QTCLine)? {
        let tok = tokens(s)
        guard tok.count >= 4, tok[0].count <= 2, let idx = Int(tok[0]), (1...10).contains(idx),
              triple(tok, 1) != nil else { return nil }
        guard let l = parseLine(tok.dropFirst().joined(separator: " ")) else { return nil }
        return (idx, l)
    }

    /// Řádek vypadá jako (poškozený) pokus o QTC: aspoň 3 slova, první 2–5 znaků převážně číslic (čas),
    /// druhé se znaky jako značka – pro zachování pořadí řádků.
    public static func looksLikeLine(_ s: String) -> Bool {
        guard !s.uppercased().contains("QTC") else { return false }
        let tok = tokens(s)
        guard tok.count >= 3, (2...5).contains(tok[0].count), tok[0].filter(\.isNumber).count >= 2,
              tok[1].count >= 3, tok[1].contains(where: \.isLetter) else { return false }
        return true
    }
}

/// Úložiště sérií QTC (`qtc.jsonl` v adresáři logu, jedna série na řádek).
public actor QTCStore {
    public private(set) var series: [QTCSeries] = []
    /// Nečitelné řádky souboru (např. po havárii) – pro zobrazení v UI.
    public private(set) var warnings: [String] = []
    private let url: URL
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .deferredToDate; return e }()

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("qtc.jsonl")
        if let d = try? Data(contentsOf: url) {
            let dec = JSONDecoder()
            for (i, line) in d.split(separator: UInt8(ascii: "\n")).enumerated() {
                if let s = try? dec.decode(QTCSeries.self, from: Data(line)) { series.append(s) }
                else { warnings.append("qtc.jsonl řádek \(i + 1) je nečitelný – přeskočen") }
            }
        }
    }

    public func append(_ s: QTCSeries) throws {
        var line = try Self.encoder.encode(s)
        line.append(UInt8(ascii: "\n"))
        if FileManager.default.fileExists(atPath: url.path) {
            let h = try FileHandle(forUpdating: url)
            defer { try? h.close() }
            let end = try h.seekToEnd()
            if end > 0 {                                   // neúplný poslední řádek (havárie) → nejdřív ho ukončit
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
