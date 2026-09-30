// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// The DXCC country for a call (data from cty.dat, AD1C format).
public struct CountryInfo: Sendable, Equatable {
    public var name: String
    public var primaryPrefix: String
    public var continent: String
    public var cqZone: Int
    public var ituZone: Int
    public var latitude: Double
    public var longitude: Double          // east positive
    public var utcOffsetHours: Double     // local time = UTC + offset
}

/// Country database from cty.dat (a replacement for Country.cpp / ARRL.DX from MMTTY).
///
/// It first looks for an exact call (`=CALL`), then for the longest prefix. Portable calls
/// (`OK/DL1ABC`, `DL1ABC/KH6`) are judged by the shorter part, `/P`, `/M`, `/QRP` etc. are ignored,
/// `/MM` and `/AM` have no country.
public struct CountryDB: Sendable {
    public enum Error: Swift.Error, Equatable { case noEntities }

    private struct Override: Sendable {
        var cq: Int?, itu: Int?, cont: String?, lat: Double?, lon: Double?, offset: Double?
    }
    private let entities: [CountryInfo]
    private var prefixes: [String: (Int, Override)] = [:]
    private var exact: [String: (Int, Override)] = [:]
    /// Countries only in the WAE list ("*" in cty.dat: Sicily, Shetlands, European Turkey, …) – indexes into `entities`.
    private var waePrefixes: [String: (Int, Override)] = [:]
    private var waeExact: [String: (Int, Override)] = [:]
    private let dxccCount: Int

    /// The number of DXCC countries (excluding those only in the WAE list).
    public var count: Int { dxccCount }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        try self.init(text: String(decoding: data, as: UTF8.self))
    }

    public init(text: String) throws {
        var ents: [CountryInfo] = []
        var pfx: [String: (Int, Override)] = [:], ex: [String: (Int, Override)] = [:]
        var wpfx: [String: (Int, Override)] = [:], wex: [String: (Int, Override)] = [:]
        var dxcc = 0
        for chunk in text.split(separator: ";") {
            let fields = chunk.split(separator: ":", maxSplits: 8, omittingEmptySubsequences: false)
            guard fields.count == 9 else { continue }
            func f(_ i: Int) -> String { fields[i].trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let cq = Int(f(1)), let itu = Int(f(2)), let lat = Double(f(4)), let lonW = Double(f(5)),
                  let off = Double(f(6)) else { continue }
            var primary = f(7)
            // "*" = an entity for WAE/CQ only (Sicily, …), not a DXCC country – the normal lookup skips it
            // (its prefixes fall to the parent country), a lookup with `wae: true` finds it
            let waeOnly = primary.hasPrefix("*")
            if waeOnly { primary.removeFirst() } else { dxcc += 1 }
            let idx = ents.count
            ents.append(CountryInfo(name: f(0), primaryPrefix: primary, continent: f(3), cqZone: cq, ituZone: itu,
                                    latitude: lat, longitude: -lonW, utcOffsetHours: -off))
            for raw in fields[8].split(separator: ",") {
                let tok = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !tok.isEmpty else { continue }
                let (isExact, base, ov) = Self.parseAlias(tok)
                guard !base.isEmpty else { continue }
                if waeOnly {
                    if isExact { wex[base] = (idx, ov) } else { wpfx[base] = (idx, ov) }
                } else if isExact { ex[base] = (idx, ov) } else { pfx[base] = (idx, ov) }
            }
        }
        guard dxcc > 0 else { throw Error.noEntities }
        entities = ents; prefixes = pfx; exact = ex; waePrefixes = wpfx; waeExact = wex; dxccCount = dxcc
    }

    /// `=W1AW(5)[8]{NA}<41.7/72.7>~5.0~` → exact?, base, overrides.
    private static func parseAlias(_ t: String) -> (Bool, String, Override) {
        var s = Substring(t)
        let isExact = s.hasPrefix("=")
        if isExact { s = s.dropFirst() }
        let special: Set<Character> = ["(", "[", "{", "<", "~"]
        let base = String(s.prefix { !special.contains($0) })
        var ov = Override()
        func between(_ o: Character, _ c: Character) -> String? {
            guard let a = s.firstIndex(of: o) else { return nil }
            let rest = s[s.index(after: a)...]
            guard let b = rest.firstIndex(of: c) else { return nil }
            return String(rest[..<b])
        }
        ov.cq = between("(", ")").flatMap { Int($0) }
        ov.itu = between("[", "]").flatMap { Int($0) }
        ov.cont = between("{", "}")
        if let ll = between("<", ">") {
            let p = ll.split(separator: "/")
            if p.count == 2 { ov.lat = Double(p[0]); ov.lon = Double(p[1]).map { -$0 } }
        }
        ov.offset = between("~", "~").flatMap { Double($0) }.map { -$0 }
        return (isExact, base, ov)
    }

    private func info(_ hit: (Int, Override)) -> CountryInfo {
        var i = entities[hit.0]
        let o = hit.1
        if let v = o.cq { i.cqZone = v }
        if let v = o.itu { i.ituZone = v }
        if let v = o.cont { i.continent = v }
        if let v = o.lat { i.latitude = v }
        if let v = o.lon { i.longitude = v }
        if let v = o.offset { i.utcOffsetHours = v }
        return i
    }

    private func longestPrefix(_ s: String, wae: Bool) -> CountryInfo? {
        if wae, let e = waeExact[s] { return info(e) }
        if let e = exact[s] { return info(e) }
        var len = s.count
        while len > 0 {
            let p = String(s.prefix(len))
            if wae, let h = waePrefixes[p] { return info(h) }
            if let h = prefixes[p] { return info(h) }
            len -= 1
        }
        return nil
    }

    static let modifiers: Set<String> = ["P", "M", "QRP", "QRPP", "A", "B", "LH", "J", "R", "T", "X"]
    static let noCountry: Set<String> = ["MM", "AM"]

    /// The country for a call. `wae: true` = WAE-list countries too (CQ WW, WAE DX Contest), otherwise DXCC only.
    public func lookup(_ call: String, wae: Bool = false) -> CountryInfo? {
        let c = call.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !c.isEmpty else { return nil }
        if wae, let e = waeExact[c] { return info(e) }
        if let e = exact[c] { return info(e) }
        var parts = c.split(separator: "/").map(String.init)
        if parts.count > 1, parts.contains(where: Self.noCountry.contains) { return nil }
        // modifiers (/P, /M, /QRP, /4 …) only as suffixes – M/, R/, B/ at the start are country prefixes
        while parts.count > 1, let last = parts.last,
              Self.modifiers.contains(last) || (last.count == 1 && last.first!.isNumber) {
            parts.removeLast()
        }
        guard !parts.isEmpty else { return nil }
        if parts.count == 1 { return longestPrefix(parts[0], wae: wae) }
        // portable: the shorter part decides (the country prefix)
        let p = parts.min { $0.count < $1.count }!
        return longestPrefix(p, wae: wae)
    }
}

public extension CountryDB {
    /// A user file (Application Support/mmtty4mac/cty.dat) takes precedence over the bundled one.
    static func defaultURLs() -> [URL] {
        var urls: [URL] = []
        if let sup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(sup.appendingPathComponent("mmtty4mac/cty.dat"))
        }
        if let b = Bundle.main.url(forResource: "cty", withExtension: "dat") { urls.append(b) }
        // development (swift run / tests): Resources/cty.dat in the repository
        urls.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/cty.dat"))
        return urls
    }

    /// The shared database (loaded once on first use).
    static let shared: CountryDB? = loadDefault()

    /// Loads the first usable file, or nil.
    static func loadDefault() -> CountryDB? {
        for u in defaultURLs() where FileManager.default.fileExists(atPath: u.path) {
            if let db = try? CountryDB(contentsOf: u) { return db }
        }
        return nil
    }
}
