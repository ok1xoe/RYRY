// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Země DXCC pro značku (údaje z cty.dat, formát AD1C).
public struct CountryInfo: Sendable, Equatable {
    public var name: String
    public var primaryPrefix: String
    public var continent: String
    public var cqZone: Int
    public var ituZone: Int
    public var latitude: Double
    public var longitude: Double          // východ kladně
    public var utcOffsetHours: Double     // místní čas = UTC + offset
}

/// Databáze zemí z cty.dat (náhrada Country.cpp / ARRL.DX z MMTTY).
///
/// Hledá nejdřív přesnou značku (`=CALL`), pak nejdelší prefix. Portable značky
/// (`OK/DL1ABC`, `DL1ABC/KH6`) se hodnotí podle kratší části, `/P`, `/M`, `/QRP` apod. se ignorují,
/// `/MM` a `/AM` nemají zemi.
public struct CountryDB: Sendable {
    public enum Error: Swift.Error, Equatable { case noEntities }

    private struct Override: Sendable {
        var cq: Int?, itu: Int?, cont: String?, lat: Double?, lon: Double?, offset: Double?
    }
    private let entities: [CountryInfo]
    private var prefixes: [String: (Int, Override)] = [:]
    private var exact: [String: (Int, Override)] = [:]
    /// Země jen ze seznamu WAE („*“ v cty.dat: Sicílie, Shetlandy, evropské Turecko, …) – indexy do `entities`.
    private var waePrefixes: [String: (Int, Override)] = [:]
    private var waeExact: [String: (Int, Override)] = [:]
    private let dxccCount: Int

    /// Počet zemí DXCC (bez zemí jen ze seznamu WAE).
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
            // „*“ = entita jen pro WAE/CQ (Sicílie, …), ne země DXCC – běžné hledání ji přeskočí
            // (prefixy spadnou do mateřské země), hledání s `wae: true` ji najde
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

    /// `=W1AW(5)[8]{NA}<41.7/72.7>~5.0~` → přesná?, základ, přepisy.
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

    /// Země pro značku. `wae: true` = i země ze seznamu WAE (CQ WW, WAE DX Contest), jinak jen DXCC.
    public func lookup(_ call: String, wae: Bool = false) -> CountryInfo? {
        let c = call.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !c.isEmpty else { return nil }
        if wae, let e = waeExact[c] { return info(e) }
        if let e = exact[c] { return info(e) }
        var parts = c.split(separator: "/").map(String.init)
        if parts.count > 1, parts.contains(where: Self.noCountry.contains) { return nil }
        // modifikátory (/P, /M, /QRP, /4 …) jen jako přípony – M/, R/, B/ na začátku jsou prefixy zemí
        while parts.count > 1, let last = parts.last,
              Self.modifiers.contains(last) || (last.count == 1 && last.first!.isNumber) {
            parts.removeLast()
        }
        guard !parts.isEmpty else { return nil }
        if parts.count == 1 { return longestPrefix(parts[0], wae: wae) }
        // portable: rozhoduje kratší část (prefix země)
        let p = parts.min { $0.count < $1.count }!
        return longestPrefix(p, wae: wae)
    }
}

public extension CountryDB {
    /// Uživatelský soubor (Application Support/mmtty4mac/cty.dat) má přednost před přibaleným.
    static func defaultURLs() -> [URL] {
        var urls: [URL] = []
        if let sup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            urls.append(sup.appendingPathComponent("mmtty4mac/cty.dat"))
        }
        if let b = Bundle.main.url(forResource: "cty", withExtension: "dat") { urls.append(b) }
        // vývoj (swift run / testy): Resources/cty.dat v repozitáři
        urls.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/cty.dat"))
        return urls
    }

    /// Sdílená databáze (načte se jednou při prvním použití).
    static let shared: CountryDB? = loadDefault()

    /// Načte první použitelný soubor, nebo nil.
    static func loadDefault() -> CountryDB? {
        for u in defaultURLs() where FileManager.default.fileExists(atPath: u.path) {
            if let db = try? CountryDB(contentsOf: u) { return db }
        }
        return nil
    }
}
