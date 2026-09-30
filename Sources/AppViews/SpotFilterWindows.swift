// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import Localization
import Settings
import Spots
import SwiftUI

/// Identifikátory oken filtru spotů (`Window(id:)`, `openWindow(id:)`, spouštěcí parametr `-openWindow`).
public enum SpotFilterWindowID {
    public static let bands = "spotbands"
    public static let modes = "spotmodes"
}

/// Okno „Filtr pásem“: zaškrtávátka celého pevného seznamu pásem (`SpotFilter.allBands`) a tlačítka Vše / Nic.
/// Zaškrtnuté = zobrazené v tabulce Spoty; filtruje se jen zobrazení a změna platí hned (uloží se do nastavení).
public struct SpotBandFilterWindow: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }

    /// Řádky zaškrtávátek – dohromady vždy celý seznam pásem.
    public static let rows = SpotFilter.bandRows(perRow: 4)
    /// Popisek zaškrtávátka za pevným seznamem (spoty bez vlastního pásma) – stejné slovo jako u skupin módů.
    public static var otherLabel: String { L("ostatní") }

    private var otherToggle: some View {
        Toggle(Self.otherLabel, isOn: Binding(get: { model.settings.spots.filterOtherBands },
                                              set: { on in model.setSpots { $0.filterOtherBands = on } }))
            .toggleStyle(.checkbox)
            .hint(L("Spoty mimo pevný seznam pásem: 630 m a níž, 4 m a výš i spot, u kterého pásmo nejde poznat"))
    }

    private func toggle(_ b: String) -> some View {
        Toggle(b, isOn: Binding(get: { model.settings.spots.filterBands.contains(b) },
                                set: { on in
                                    model.setSpots { s in
                                        if on { s.filterBands.insert(b) } else { s.filterBands.remove(b) }
                                    }
                                }))
            .toggleStyle(.checkbox)
            .frame(width: 62, alignment: .leading)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { toggle($0) }
                    Spacer(minLength: 0)
                }
            }
            otherToggle
            Divider()
            HStack(spacing: 10) {
                Button(L("Vše")) { model.setSpots { $0.setAllBands(true) } }
                Button(L("Nic")) { model.setSpots { $0.setAllBands(false) } }
                Spacer(minLength: 0)
            }
            Text(L("Zaškrtnutá pásma se zobrazují v tabulce Spoty; „ostatní“ = spoty mimo pevný seznam pásem."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .controlSize(.small)
        .padding(12)
        .frame(width: 300, alignment: .leading)
    }
}

/// Okno „Filtr módů“: zaškrtávátka všech skupin módů (`SpotModeGroup`) a tlačítka Vše / Nic. Zaškrtnuté =
/// zobrazené v tabulce Spoty, band mapě i ve vodopádu; právě RTTY = zaškrtávátko „Jen RTTY“ v okně Spoty.
public struct SpotModeFilterWindow: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }

    /// Řádky zaškrtávátek – dohromady vždy všechny skupiny módů.
    public static let rows: [[SpotModeGroup]] = {
        let all = SpotModeGroup.allCases, perRow = 3
        return stride(from: 0, to: all.count, by: perRow).map { Array(all[$0..<min($0 + perRow, all.count)]) }
    }()

    private func toggle(_ g: SpotModeGroup) -> some View {
        Toggle(SpotFilterBar.modeLabel(g), isOn: Binding(get: { model.settings.spots.filterModes.contains(g) },
                                                        set: { on in
                                                            model.setSpots { s in
                                                                var v = s.filterModes
                                                                if on { v.insert(g) } else { v.remove(g) }
                                                                s.setFilterModes(v)
                                                            }
                                                        }))
            .toggleStyle(.checkbox)
            .frame(width: 76, alignment: .leading)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { toggle($0) }
                    Spacer(minLength: 0)
                }
            }
            Divider()
            HStack(spacing: 10) {
                Button(L("Vše")) { model.setSpots { $0.setFilterModes(SpotFilter.allModes) } }
                Button(L("Nic")) { model.setSpots { $0.setFilterModes([]) } }
                Spacer(minLength: 0)
            }
            Text(L("Skupiny módů spotů; „ostatní“ = i spoty, u kterých mód nejde poznat. Právě RTTY = „Jen RTTY“ v okně Spoty."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .controlSize(.small)
        .padding(12)
        .frame(width: 300, alignment: .leading)
    }
}
