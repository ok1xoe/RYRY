// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import QSOLog
import Settings

/// A record from the call history file (N1MM Logger+ "Call History").
public struct CallHistoryEntry: Equatable, Sendable {
    public var name = "", loc = "", exch = "", state = ""
    public var cqZone: Int?, ituZone: Int?
    public init(name: String = "", loc: String = "", exch: String = "", cqZone: Int? = nil, ituZone: Int? = nil, state: String = "") {
        self.name = name; self.loc = loc; self.exch = exch; self.cqZone = cqZone; self.ituZone = ituZone; self.state = state
    }
}

/// Call history: a dictionary base call → record. A pure parser without a dependency on the GUI.
///
/// N1MM format: the header `!!Order!!,Call,Name,Loc1,Exch1,CqZone,ItuZone,State,…` determines the column order
/// (names regardless of case, unknown columns are skipped), `#` = comment, values may be in quotes.
/// Without a header a simple CSV `Call,Name,Exch1` is read. Duplicate call: the last line wins.
public struct CallHistory: Sendable, Equatable {
    public private(set) var entries: [String: CallHistoryEntry] = [:]
    public var count: Int { entries.count }
    public init() {}

    /// Base call (without /P, /M, a country prefix).
    public static func key(_ call: String) -> String { QSORecord.baseCall(call.trimmingCharacters(in: .whitespaces)) }

    /// The record for a call; both `DL1ABC/P` and `DL1ABC` find the same record (the key is the base call).
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

    /// Splits a CSV line (quotes, a doubled quote = a quote).
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
        var order: [Col?] = [.call, .name, .exch]          // without a header: Call,Name,Exch1
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
            if line.hasPrefix("!") { continue }                  // other control lines
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

    /// A header without `!!Order!!`: the first field is exactly "Call" / "Callsign" (not a callsign).
    private static func isPlainHeader(_ line: String) -> Bool {
        guard let first = line.split(whereSeparator: { ",;\t".contains($0) }).first else { return false }
        let f = first.lowercased()
        return f == "call" || f == "callsign"
    }

    /// Loads the file (UTF-8, otherwise Latin-1) and processes it off the calling thread.
    public static func load(url: URL) async throws -> CallHistory {
        try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            return parse(text)
        }.value
    }

    // MARK: Mapping to QSO fields

    /// Values for the QSO window fields (only non-empty) by contest format. `isNorthAmerica` = W/VE (state in the CQ/RJ
    /// and ARRL RU exchange); nil = unknown country, the state is added if it is in the history.
    ///
    /// Loc1 goes into the locator only as a valid Maidenhead locator; otherwise (W/VE contest history) it is a state/province
    /// and is used in the CQ/RJ and ARRL RU exchange.
    public func fields(for e: CallHistoryEntry, contest c: ContestSettings, isNorthAmerica: Bool?) -> [String: String] {
        var r: [String: String] = [:]
        if !e.name.isEmpty { r["name"] = e.name }
        let locIsGrid = !e.loc.isEmpty && Geo.maidenhead(e.loc) != nil
        if locIsGrid { r["locator"] = e.loc }
        let locState = locIsGrid ? "" : e.loc
        guard c.enabled else { return r }
        let na = isNorthAmerica ?? true
        switch c.format {
        case .zone:
            if let z = e.cqZone { r["exchangeRcvd"] = String(z) }
        case .cqrj:
            if let z = e.cqZone {
                var x = String(z)
                let st = !e.state.isEmpty ? e.state : (Multipliers.stateOrProvince(locState) ?? "")
                if !st.isEmpty, na { x += " " + st }
                r["exchangeRcvd"] = x
            }
        case .serial:
            if c.isRoundupStateExchange {
                // W/VE send a state/province (the others a serial number – we do not take that from the history)
                if na, let st = [e.state, locState, e.exch].lazy.compactMap(Multipliers.stateOrProvince).first {
                    r["exchangeRcvd"] = st
                }
            } else if !c.exchange.isEmpty, !e.exch.isEmpty { r["exchangeRcvd"] = e.exch }
        case .serialText, .text:
            if !e.exch.isEmpty { r["exchangeRcvd"] = e.exch }
            else if !e.name.isEmpty, c.selectedPreset?.textIsName == true { r["exchangeRcvd"] = e.name }
        case .bartg, .wae, .ped: break
        }
        return r
    }
}
