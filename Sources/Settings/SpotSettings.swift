// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Spots

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
    /// Filtr zobrazení – zaškrtnutá pásma (pevný seznam `SpotFilter.allBands`). Výchozí: všechna.
    public var filterBands = SpotFilter.allBandsSet
    /// Filtr zobrazení – zaškrtávátko „ostatní“ u pásem (spoty mimo pevný seznam). Výchozí: zaškrtnuté.
    public var filterOtherBands = true
    /// Filtr zobrazení – zaškrtnuté skupiny módů. Výchozí jen RTTY (jako dřívější „Jen RTTY“).
    public var filterModes: Set<SpotModeGroup> = [.rtty]
    /// Volba módů před zapnutím „Jen RTTY“ – jen pro obnovení po odškrtnutí; zdroj pravdy je `filterModes`.
    public var previousFilterModes = SpotFilter.allModes
    /// Stáří spotů v minutách (1…240).
    public var maxAgeMinutes = 30
    /// Posun frekvence rigu proti frekvenci spotu (Hz): rádio v LSB/AFSK s mark 2125 Hz potřebuje +2125.
    public var offsetHz = 0.0
    /// Štítky spotů (band map) ve vodopádu a spektru.
    public var showInWaterfall = true

    /// Filtr zobrazení pro seznam spotů, band mapu a štítky ve vodopádu.
    public var filter: SpotFilter { SpotFilter(bands: filterBands, modes: filterModes, otherBands: filterOtherBands) }

    /// Tlačítka Vše / Nic v okně „Filtr pásem“ – zaškrtávátko „ostatní“ se přepíná spolu s pevným seznamem,
    /// aby „Nic“ tabulku skutečně vyprázdnilo a „Vše“ vrátilo všechny spoty.
    public mutating func setAllBands(_ on: Bool) {
        filterBands = on ? SpotFilter.allBandsSet : []
        filterOtherBands = on
    }

    /// Zaškrtávátko „Jen RTTY“: zobrazená je právě skupina RTTY. Počítá se z `filterModes` (vlastní klíč nemá),
    /// takže se zaškrtne i po zaškrtnutí samotného RTTY v okně „Filtr módů“ a odškrtne po jakékoli další skupině.
    public var rttyOnly: Bool { filterModes == [.rtty] }

    /// Nastaví filtr módů (zaškrtávátka v okně „Filtr módů“, tlačítka Vše / Nic) a zapamatuje si volbu,
    /// kterou tím uživatel opouští kvůli „Jen RTTY“ – odškrtnutí ji pak vrátí.
    public mutating func setFilterModes(_ v: Set<SpotModeGroup>) {
        if v == [.rtty], !rttyOnly { previousFilterModes = filterModes }
        filterModes = v
    }

    /// Zaškrtnutí „Jen RTTY“ nechá jen skupinu RTTY, odškrtnutí vrátí předchozí volbu módů;
    /// když není co vracet (prázdná volba nebo zase jen RTTY), zaškrtnou se všechny skupiny.
    public mutating func setRTTYOnly(_ on: Bool) {
        if on { setFilterModes([.rtty]) }
        else if rttyOnly {
            let p = previousFilterModes
            filterModes = (p.isEmpty || p == [.rtty]) ? SpotFilter.allModes : p
        }
    }

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
        case clusterEnabled, clusterHost, clusterPort, clusterCommands, clusterMacros, rbnEnabled, rbnHost, rbnPort
        case filterBands, filterOtherBands, filterModes, previousFilterModes, maxAgeMinutes, offsetHz, showInWaterfall
    }

    /// Zrušené nastavení „Jen RTTY“ – čte se jen kvůli migraci na `filterModes` (už se neukládá).
    enum LegacyKeys: String, CodingKey { case rttyOnly }

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
        // pásma: neznámé názvy se vynechají, prázdný seznam je platný („Nic“), neplatná hodnota = výchozí
        let fb: TolerantArray<String>? = c.tolerant(.filterBands, nil, w, s)
        filterBands = fb.map { Set($0.items.filter(SpotFilter.allBandsSet.contains)) } ?? x.filterBands
        // „ostatní“ (spoty mimo pevný seznam pásem): chybějící i neplatná hodnota = výchozí zaškrtnuto
        filterOtherBands = c.tolerant(.filterOtherBands, x.filterOtherBands, w, s)
        // migrace: starší settings.json má jen „rttyOnly“ (true = jen RTTY, false = všechny módy)
        let fm: TolerantArray<SpotModeGroup>? = c.tolerant(.filterModes, nil, w, s)
        let legacy = try? d.container(keyedBy: LegacyKeys.self)
        if let fm { filterModes = Set(fm.items) }
        else if let legacy, legacy.contains(.rttyOnly) {
            filterModes = legacy.tolerant(.rttyOnly, true, w, s) ? [.rtty] : SpotFilter.allModes
        } else { filterModes = x.filterModes }
        // pamatovaná volba pro odškrtnutí „Jen RTTY“ (neplatná hodnota = výchozí, prázdný seznam je platný)
        let pm: TolerantArray<SpotModeGroup>? = c.tolerant(.previousFilterModes, nil, w, s)
        previousFilterModes = pm.map { Set($0.items) } ?? x.previousFilterModes
        let a = c.tolerant(.maxAgeMinutes, x.maxAgeMinutes, w, s); maxAgeMinutes = Self.ageRange.contains(a) ? a : x.maxAgeMinutes
        let o = c.tolerant(.offsetHz, x.offsetHz, w, s); offsetHz = Self.offsetRange.contains(o) ? o : x.offsetHz
        showInWaterfall = c.tolerant(.showInWaterfall, x.showInWaterfall, w, s)
    }
}
