// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import QSOLog
import Settings

/// Záznam ze souboru historie značek (N1MM Logger+ „Call History“).
public struct CallHistoryEntry: Equatable, Sendable {
    public var name = "", loc = "", exch = "", state = ""
    public var cqZone: Int?, ituZone: Int?
    public init(name: String = "", loc: String = "", exch: String = "", cqZone: Int? = nil, ituZone: Int? = nil, state: String = "") {
        self.name = name; self.loc = loc; self.exch = exch; self.cqZone = cqZone; self.ituZone = ituZone; self.state = state
    }
}

/// Historie značek: slovník základní značka → záznam. Čistý parser bez závislosti na GUI.
///
/// Formát N1MM: hlavička `!!Order!!,Call,Name,Loc1,Exch1,CqZone,ItuZone,State,…` určuje pořadí sloupců
/// (názvy bez ohledu na velikost písmen, neznámé sloupce se přeskočí), `#` = komentář, hodnoty mohou být v uvozovkách.
/// Bez hlavičky se čte jednoduché CSV `Call,Name,Exch1`. Duplicitní značka: poslední řádek vyhrává.
public struct CallHistory: Sendable, Equatable {
    public private(set) var entries: [String: CallHistoryEntry] = [:]
    public var count: Int { entries.count }
    public init() {}

    /// Základní značka (bez /P, /M, prefixu země).
    public static func key(_ call: String) -> String { QSORecord.baseCall(call.trimmingCharacters(in: .whitespaces)) }

    /// Záznam pro značku; `DL1ABC/P` i `DL1ABC` najdou stejný záznam (klíč je základní značka).
    public func lookup(_ call: String) -> CallHistoryEntry? { entries[Self.key(call)] }

    // MARK: Parser

    private enum Col { case call, name, loc, exch, cq, itu, state }

    private static func column(_ raw: String) -> Col? {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "call", "callsign": return .call
        case "name": return .name
        case "loc1", "loc", "grid", "gridsquare", "locator": return .loc
        case "exch1", "exch", "exchange": return .exch
        case "cqzone", "cqz", "cq": return .cq
        case "ituzone", "ituz", "itu": return .itu
        case "state", "st": return .state
        default: return nil
        }
    }

    /// Rozdělí řádek CSV (uvozovky, zdvojená uvozovka = uvozovka).
    static func splitCSV(_ line: String, delimiter: Character) -> [String] {
        var out: [String] = [], cur = "", inQuotes = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { cur.append("\""); i += 1 } else { inQuotes = false }
                } else { cur.append(ch) }
            } else if ch == "\"" { inQuotes = true }
            else if ch == delimiter { out.append(cur); cur = "" }
            else { cur.append(ch) }
            i += 1
        }
        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    public static func parse(_ text: String) -> CallHistory {
        var h = CallHistory()
        var order: [Col?] = [.call, .name, .exch]          // bez hlavičky: Call,Name,Exch1
        var delimiter: Character = ","
        for raw in text.split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let lower = line.lowercased()
            let isOrder = lower.hasPrefix("!!order!!")
            if isOrder || isPlainHeader(line) {
                delimiter = [",", "\t", ";"].first { line.contains($0) } ?? ","
                var cols = splitCSV(line, delimiter: delimiter)
                if isOrder { cols.removeFirst() }
                order = cols.map(column)
                continue
            }
            if line.hasPrefix("!") { continue }                  // jiné řídicí řádky
            let f = splitCSV(line, delimiter: delimiter)
            var e = CallHistoryEntry(), call = ""
            for (i, col) in order.enumerated() where i < f.count {
                let v = f[i]
                switch col {
                case .call: call = v.uppercased()
                case .name: e.name = v
                case .loc: e.loc = v.uppercased()
                case .exch: e.exch = v
                case .cq: e.cqZone = Int(v)
                case .itu: e.ituZone = Int(v)
                case .state: e.state = v.uppercased()
                case nil: break
                }
            }
            guard !call.isEmpty else { continue }
            h.entries[key(call)] = e
        }
        return h
    }

    /// Hlavička bez `!!Order!!`: první pole je přesně „Call“ / „Callsign“ (ne značka).
    private static func isPlainHeader(_ line: String) -> Bool {
        guard let first = line.split(whereSeparator: { ",;\t".contains($0) }).first else { return false }
        let f = first.lowercased()
        return f == "call" || f == "callsign"
    }

    /// Načte soubor (UTF-8, jinak Latin-1) a zpracuje ho mimo volající vlákno.
    public static func load(url: URL) async throws -> CallHistory {
        try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            return parse(text)
        }.value
    }

    // MARK: Mapování na pole QSO

    /// Hodnoty pro pole QSO okna (jen neprázdné) podle formátu závodu. `isNorthAmerica` = W/VE (stát ve výměně CQ/RJ);
    /// nil = neznámá země, stát se přidá, pokud v historii je.
    public func fields(for e: CallHistoryEntry, contest c: ContestSettings, isNorthAmerica: Bool?) -> [String: String] {
        var r: [String: String] = [:]
        if !e.name.isEmpty { r["name"] = e.name }
        if !e.loc.isEmpty { r["locator"] = e.loc }
        guard c.enabled else { return r }
        switch c.format {
        case .zone:
            if let z = e.cqZone { r["exchangeRcvd"] = String(z) }
        case .cqrj:
            if let z = e.cqZone {
                var x = String(z)
                if !e.state.isEmpty, isNorthAmerica ?? true { x += " " + e.state }
                r["exchangeRcvd"] = x
            }
        case .serial:
            if !c.exchange.isEmpty, !e.exch.isEmpty { r["exchangeRcvd"] = e.exch }
        case .bartg, .wae, .ped: break
        }
        return r
    }
}
