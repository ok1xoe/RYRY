// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Spoty z DX clusteru a Reverse Beacon Network (telnet). Přihlašovací značka = značka ze Stanice.
/// Výchozí stav je vypnuto – síť se použije jen na výslovné zapnutí.
public struct SpotSettings: Codable, Sendable, Equatable {
    public var clusterEnabled = false
    public var clusterHost = "dxc.ve7cc.net"
    public var clusterPort = 23
    /// Příkazy po přihlášení, jeden na řádek (např. `set/skimmer`, `sh/dx 30`).
    public var clusterCommands: [String] = ["sh/dx 30"]
    /// Makra tlačítek příkazů DX clusteru (vždy 10 položek); text = příkaz(y), jeden na řádek, proměnné jako u maker pro vysílání.
    public var clusterMacros: [Macro] = SpotSettings.defaultClusterMacros
    public var rbnEnabled = false
    public var rbnHost = "telnet.reversebeacon.net"
    public var rbnPort = 7000
    /// Jen spoty RTTY.
    public var rttyOnly = true
    /// Stáří spotů v minutách (1…240).
    public var maxAgeMinutes = 30
    /// Posun frekvence rigu proti frekvenci spotu (Hz): rádio v LSB/AFSK s mark 2125 Hz potřebuje +2125.
    public var offsetHz = 0.0
    /// Štítky spotů (band map) ve vodopádu a spektru.
    public var showInWaterfall = true

    public static let ageRange = 1...240
    public static let offsetRange = -10_000.0...10_000.0
    public static let maxCommands = 10
    public static let clusterMacroCount = 10
    /// Výchozí příkazy DXSpider / CC Cluster (názvy jazykově neutrální, jako příkazy). „RTTY“ (`sh/dx 30 info rtty`) – kvalifikátor `info` hledá v komentáři.
    public static let defaultClusterMacros: [Macro] = [
        Macro(name: "SH/DX", text: "sh/dx 30"),
        Macro(name: "RTTY", text: "sh/dx 30 info rtty"),
        Macro(name: "20 m", text: "sh/dx on 20m"),
        Macro(name: "40 m", text: "sh/dx on 40m"),
        Macro(name: "WWV", text: "sh/wwv"),
        Macro(name: "SUN", text: "sh/sun"),
        Macro(name: "Skimmer ON", text: "set/skimmer"),
        Macro(name: "Skimmer OFF", text: "unset/skimmer"),
        Macro(name: "USERS", text: "sh/users"),
        Macro(name: "Spot", text: "dx %k %c RTTY"),
    ]
    public init() {}

    enum CodingKeys: String, CodingKey {
        case clusterEnabled, clusterHost, clusterPort, clusterCommands, clusterMacros, rbnEnabled, rbnHost, rbnPort, rttyOnly, maxAgeMinutes, offsetHz, showInWaterfall
    }

    static func validHost(_ h: String) -> Bool {
        !h.isEmpty && h.count <= 253 && !h.contains(where: { $0.isWhitespace || $0 == "/" })
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "spots", x = SpotSettings()
        clusterEnabled = c.tolerant(.clusterEnabled, x.clusterEnabled, w, s)
        let ch = c.tolerant(.clusterHost, x.clusterHost, w, s).trimmingCharacters(in: .whitespaces)
        clusterHost = Self.validHost(ch) ? ch : x.clusterHost
        let cp = c.tolerant(.clusterPort, x.clusterPort, w, s); clusterPort = (1...65535).contains(cp) ? cp : x.clusterPort
        clusterCommands = c.contains(.clusterCommands)
            ? Array(c.tolerant(.clusterCommands, TolerantArray<String>(), w, s).items
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(Self.maxCommands))
            : x.clusterCommands
        var cm = c.contains(.clusterMacros)
            ? Array(c.tolerant(.clusterMacros, TolerantArray<Macro>(), w, s).items.prefix(Self.clusterMacroCount))
            : x.clusterMacros
        while cm.count < Self.clusterMacroCount { cm.append(Macro(name: "", text: "")) }
        // dřívější výchozí české názvy → jazykově neutrální (jen nezměněná výchozí makra)
        for (i, m) in cm.enumerated() {
            if m == Macro(name: "Slunce", text: "sh/sun") { cm[i].name = "SUN" }
            if m == Macro(name: "Uživatelé", text: "sh/users") { cm[i].name = "USERS" }
        }
        clusterMacros = cm
        rbnEnabled = c.tolerant(.rbnEnabled, x.rbnEnabled, w, s)
        let rh = c.tolerant(.rbnHost, x.rbnHost, w, s).trimmingCharacters(in: .whitespaces)
        rbnHost = Self.validHost(rh) ? rh : x.rbnHost
        let rp = c.tolerant(.rbnPort, x.rbnPort, w, s); rbnPort = (1...65535).contains(rp) ? rp : x.rbnPort
        rttyOnly = c.tolerant(.rttyOnly, x.rttyOnly, w, s)
        let a = c.tolerant(.maxAgeMinutes, x.maxAgeMinutes, w, s); maxAgeMinutes = Self.ageRange.contains(a) ? a : x.maxAgeMinutes
        let o = c.tolerant(.offsetHz, x.offsetHz, w, s); offsetHz = Self.offsetRange.contains(o) ? o : x.offsetHz
        showInWaterfall = c.tolerant(.showInWaterfall, x.showInWaterfall, w, s)
    }
}
