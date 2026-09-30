// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Localization
import Spots
import SwiftUI

/// Zaškrtávátka filtru zobrazení spotů: pevná řada pásem a skupin módů (jako filtry bandmapy N1MM).
/// Zaškrtnuté = zobrazené. Filtruje se jen zobrazení – přijímají a ukládají se spoty všech pásem a módů.
struct SpotFilterBar: View {
    @Binding var bands: Set<String>
    @Binding var modes: Set<SpotModeGroup>

    /// Popisek skupiny módů (názvy módů se nepřekládají, jen „ostatní“).
    static func modeLabel(_ g: SpotModeGroup) -> String {
        switch g {
        case .rtty: "RTTY"
        case .cw: "CW"
        case .psk: "PSK"
        case .digi: "FT8/FT4"
        case .ssb: "SSB"
        case .other: L("ostatní")
        }
    }

    private func bandToggle(_ b: String) -> some View {
        Toggle(b, isOn: Binding(get: { bands.contains(b) },
                               set: { on in if on { bands.insert(b) } else { bands.remove(b) } })).toggleStyle(.checkbox)
    }

    private func modeToggle(_ g: SpotModeGroup) -> some View {
        Toggle(Self.modeLabel(g), isOn: Binding(get: { modes.contains(g) },
                                                set: { on in if on { modes.insert(g) } else { modes.remove(g) } }))
            .toggleStyle(.checkbox)
    }

    /// „Vše“ / „Nic“ za řadou zaškrtávátek.
    private func allNone(_ all: @escaping () -> Void, _ none: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button(L("Vše"), action: all)
            Button(L("Nic"), action: none)
        }
        .buttonStyle(.link)
    }

    private func bandRow(_ list: [String], label: Bool, buttons: Bool) -> some View {
        HStack(spacing: 6) {
            if label { Text(L("Pásma:")).foregroundStyle(.secondary) }
            ForEach(list, id: \.self) { bandToggle($0) }
            if buttons { allNone({ bands = SpotFilter.allBandsSet }, { bands = [] }) }
        }
    }

    private var modeRow: some View {
        HStack(spacing: 6) {
            Text(L("Módy:")).foregroundStyle(.secondary)
            ForEach(SpotModeGroup.allCases, id: \.self) { modeToggle($0) }
            allNone({ modes = SpotFilter.allModes }, { modes = [] })
        }
        .hint(L("Skupiny módů spotů; „ostatní“ = i spoty, u kterých mód nejde poznat"))
    }

    private var allBandRow: some View { bandRow(SpotFilter.allBands, label: true, buttons: true) }

    /// Podle šířky okna: vše na jednom řádku → pásma a módy po řádcích → pásma zalomená na dva řádky.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { allBandRow; modeRow; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 3) { allBandRow; modeRow }
            VStack(alignment: .leading, spacing: 3) {
                bandRow(Array(SpotFilter.allBands.prefix(6)), label: true, buttons: false)
                bandRow(Array(SpotFilter.allBands.dropFirst(6)), label: false, buttons: true)
                modeRow
            }
        }
        .font(.caption)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
