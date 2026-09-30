// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Spots

/// Spots from a DX cluster and the Reverse Beacon Network (telnet). The login call = the call from Station.
/// The default state is off – the network is used only on an explicit enable.
public struct SpotSettings: Codable, Sendable, Equatable {
    public var clusterEnabled = false
    public var clusterHost = "dxc.ve7cc.net"
    public var clusterPort = 23
    /// Commands after login, one per line (e.g. `set/skimmer`, `sh/dx 30`).
    public var clusterCommands: [String] = ["sh/dx 30"]
    /// Macros of the DX cluster command buttons (always 10 items); text = command(s), one per line, variables as in transmit macros.
    public var clusterMacros: [Macro] = SpotSettings.defaultClusterMacros
    public var rbnEnabled = false
    public var rbnHost = "telnet.reversebeacon.net"
    public var rbnPort = 7000
    /// Display filter – checked bands (the fixed list `SpotFilter.allBands`). Default: all.
    public var filterBands = SpotFilter.allBandsSet
    /// Display filter – the "other" checkbox for bands (spots outside the fixed list). Default: checked.
    public var filterOtherBands = true
    /// Display filter – checked mode groups. Default only RTTY (like the former "RTTY only").
    public var filterModes: Set<SpotModeGroup> = [.rtty]
    /// The mode selection before turning on "RTTY only" – only for restoring after unchecking; source of truth `filterModes`.
    public var previousFilterModes = SpotFilter.allModes
    /// Spot age in minutes (1…240).
    public var maxAgeMinutes = 30
    /// Offset of the rig frequency against the spot frequency (Hz): a radio in LSB/AFSK with mark 2125 Hz needs +2125.
    public var offsetHz = 0.0
    /// Spot labels (band map) in the waterfall and the spectrum.
    public var showInWaterfall = true

    /// Display filter for the spot list, the band map and the waterfall labels.
    public var filter: SpotFilter { SpotFilter(bands: filterBands, modes: filterModes, otherBands: filterOtherBands) }

    /// The All / None buttons in the "Band filter" window – the "other" checkbox is toggled together with the fixed list,
    /// so that "None" really empties the table and "All" brings back all spots.
    public mutating func setAllBands(_ on: Bool) {
        filterBands = on ? SpotFilter.allBandsSet : []
        filterOtherBands = on
    }

    /// The "RTTY only" checkbox: exactly the RTTY group is displayed. It is computed from `filterModes` (it has no own key),
    /// so it also gets checked after checking RTTY alone in the "Mode filter" window and unchecked after any further group.
    public var rttyOnly: Bool { filterModes == [.rtty] }

    /// Sets the mode filter (checkboxes in the "Mode filter" window, the All / None buttons) and remembers the selection
    /// the user is leaving because of "RTTY only" – unchecking then brings it back.
    public mutating func setFilterModes(_ v: Set<SpotModeGroup>) {
        if v == [.rtty], !rttyOnly { previousFilterModes = filterModes }
        filterModes = v
    }

    /// Checking "RTTY only" leaves just the RTTY group, unchecking brings back the previous mode selection;
    /// when there is nothing to bring back (an empty selection or again only RTTY), all groups get checked.
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
    /// Default DXSpider / CC Cluster commands (language-neutral names, like the commands). "RTTY" (`sh/dx 30 info rtty`) – the `info` qualifier searches the comment.
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

    /// The dropped "RTTY only" setting – it is read only for the migration to `filterModes` (it is no longer saved).
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
        // earlier default Czech names → language-neutral (only unchanged default macros)
        for (i, m) in cm.enumerated() {
            if m == Macro(name: "Slunce", text: "sh/sun") { cm[i].name = "SUN" }
            if m == Macro(name: "Uživatelé", text: "sh/users") { cm[i].name = "USERS" }
        }
        clusterMacros = cm
        rbnEnabled = c.tolerant(.rbnEnabled, x.rbnEnabled, w, s)
        let rh = c.tolerant(.rbnHost, x.rbnHost, w, s).trimmingCharacters(in: .whitespaces)
        rbnHost = Self.validHost(rh) ? rh : x.rbnHost
        let rp = c.tolerant(.rbnPort, x.rbnPort, w, s); rbnPort = (1...65535).contains(rp) ? rp : x.rbnPort
        // bands: unknown names are dropped, an empty list is valid ("None"), an invalid value = the default
        let fb: TolerantArray<String>? = c.tolerant(.filterBands, nil, w, s)
        filterBands = fb.map { Set($0.items.filter(SpotFilter.allBandsSet.contains)) } ?? x.filterBands
        // "other" (spots outside the fixed band list): a missing as well as an invalid value = the default, checked
        filterOtherBands = c.tolerant(.filterOtherBands, x.filterOtherBands, w, s)
        // migration: an older settings.json has only "rttyOnly" (true = only RTTY, false = all modes)
        let fm: TolerantArray<SpotModeGroup>? = c.tolerant(.filterModes, nil, w, s)
        let legacy = try? d.container(keyedBy: LegacyKeys.self)
        if let fm { filterModes = Set(fm.items) }
        else if let legacy, legacy.contains(.rttyOnly) {
            filterModes = legacy.tolerant(.rttyOnly, true, w, s) ? [.rtty] : SpotFilter.allModes
        } else { filterModes = x.filterModes }
        // the remembered selection for unchecking "RTTY only" (an invalid value = the default, an empty list is valid)
        let pm: TolerantArray<SpotModeGroup>? = c.tolerant(.previousFilterModes, nil, w, s)
        previousFilterModes = pm.map { Set($0.items) } ?? x.previousFilterModes
        let a = c.tolerant(.maxAgeMinutes, x.maxAgeMinutes, w, s); maxAgeMinutes = Self.ageRange.contains(a) ? a : x.maxAgeMinutes
        let o = c.tolerant(.offsetHz, x.offsetHz, w, s); offsetHz = Self.offsetRange.contains(o) ? o : x.offsetHz
        showInWaterfall = c.tolerant(.showInWaterfall, x.showInWaterfall, w, s)
    }
}
