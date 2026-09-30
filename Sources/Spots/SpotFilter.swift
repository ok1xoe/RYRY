// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import QSOLog

/// Skupina módů pro zaškrtávátka filtru spotů (jako filtry v bandmapě N1MM). Každý mód, který `SpotParser`
/// umí vyrobit, patří do přesně jedné skupiny; nerozpoznaný mód (nil) i módy bez vlastní skupiny do `.other`.
public enum SpotModeGroup: String, Codable, Sendable, Hashable, CaseIterable {
    case rtty = "RTTY"
    case cw = "CW"
    case psk = "PSK"
    /// WSJT-X a příbuzné (FT8, FT4, JT65…).
    case digi = "DIGI"
    /// Fonie s jednou postranní nosnou (SSB, USB, LSB).
    case ssb = "SSB"
    /// Ostatní a neznámé (FM, AM, SSTV, OLIVIA… a spot, u kterého mód nejde poznat).
    case other = "OTHER"

    /// Módy skupiny velkými písmeny, jak je vrací `SpotParser`; `.other` v tabulce není (bere zbytek).
    static let modes: [SpotModeGroup: Set<String>] = [
        .rtty: ["RTTY"],
        .cw: ["CW"],
        .psk: ["PSK", "PSK31", "PSK63", "PSK125"],
        .digi: ["FT8", "FT4", "JT65", "JT9", "MSK144", "Q65", "WSPR", "FSK441"],
        .ssb: ["SSB", "USB", "LSB"],
    ]

    /// Skupina módu spotu; nil, prázdný nebo neznámý mód → `.other`.
    public static func group(for mode: String?) -> SpotModeGroup {
        guard let m = mode?.trimmingCharacters(in: .whitespaces).uppercased(), !m.isEmpty else { return .other }
        return allCases.first { modes[$0]?.contains(m) == true } ?? .other
    }
}

/// Filtr zobrazení spotů: zaškrtnutá pásma a skupiny módů. Uplatní se **jen při zobrazení** (tabulka Spoty,
/// band mapa, štítky ve vodopádu) – při příjmu se nic nezahazuje a seznam drží spoty všech pásem a módů.
public struct SpotFilter: Sendable, Equatable, Codable {
    /// Zaškrtnutá pásma (názvy z `Bands`, viz `allBands`).
    public var bands: Set<String>
    /// Zaškrtnuté skupiny módů.
    public var modes: Set<SpotModeGroup>

    /// Pevný seznam pásem se zaškrtávátky (nezávisí na tom, co přišlo ve spotech).
    public static let allBands = Bands.hfAnd6m
    public static let allBandsSet = Set(Bands.hfAnd6m)
    public static let allModes = Set(SpotModeGroup.allCases)
    /// Vše zaškrtnuté (tlačítka „Vše“).
    public static let all = SpotFilter(bands: allBandsSet, modes: allModes)

    /// Výchozí stav: všechna pásma, jen RTTY (stejné zobrazení jako dřívější zaškrtávátko „Jen RTTY“).
    public init(bands: Set<String> = SpotFilter.allBandsSet, modes: Set<SpotModeGroup> = [.rtty]) {
        self.bands = bands; self.modes = modes
    }

    /// Pásmo spotu projde, jen když je zaškrtnuté. Spot mimo seznam pásem (VHF/UHF nebo neznámé pásmo) žádné
    /// zaškrtávátko nemá, proto se zobrazí vždy – filtr nesmí schovat spot, který se jím nedá zapnout zpátky.
    public func matchesBand(_ s: Spot) -> Bool {
        guard let b = s.band, Self.allBandsSet.contains(b) else { return true }
        return bands.contains(b)
    }

    public func matchesMode(_ s: Spot) -> Bool { modes.contains(SpotModeGroup.group(for: s.mode)) }

    public func matches(_ s: Spot) -> Bool { matchesBand(s) && matchesMode(s) }

    /// Spoty, které filtrem projdou; nejnovější první.
    public func apply(to spots: some Sequence<Spot>) -> [Spot] { spots.filter(matches).sorted(by: Self.newestFirst) }

    /// Jen filtr módů – pro band mapu a štítky ve vodopádu, kde pásmo určuje okno nebo rig.
    public func applyModes(to spots: some Sequence<Spot>) -> [Spot] { spots.filter(matchesMode).sorted(by: Self.newestFirst) }

    /// Řazení seznamu spotů: nejnovější první, při stejném čase nižší kmitočet dřív.
    public static func newestFirst(_ a: Spot, _ b: Spot) -> Bool {
        a.time != b.time ? a.time > b.time : a.frequencyKHz < b.frequencyKHz
    }
}
