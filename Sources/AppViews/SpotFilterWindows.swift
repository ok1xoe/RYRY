// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import Localization
import Settings
import Spots
import SwiftUI

/// Identifiers of the spot filter windows (`Window(id:)`, `openWindow(id:)`, the `-openWindow` launch argument).
public enum SpotFilterWindowID {
    public static let bands = "spotbands"
    public static let modes = "spotmodes"
}

/// The "Band filter" window: checkboxes for the whole fixed list of bands (`SpotFilter.allBands`) and All / None buttons.
/// Checked = shown in the Spots table; only the display is filtered and a change takes effect immediately (it is saved to the settings).
public struct SpotBandFilterWindow: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }

    /// The checkbox rows - together always the whole list of bands.
    public static let rows = SpotFilter.bandRows(perRow: 4)
    /// Label of the checkbox after the fixed list (spots without a band of their own) - the same word as for the mode groups.
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
        .uiControlSize(-1)
        .padding(12)
        .frame(width: 300, alignment: .leading)
    }
}

/// The "Mode filter" window: checkboxes for all the mode groups (`SpotModeGroup`) and All / None buttons. Checked =
/// shown in the Spots table, the band map and the waterfall; RTTY alone = the "RTTY only" checkbox in the Spots window.
public struct SpotModeFilterWindow: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }

    /// The checkbox rows - together always all the mode groups.
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
        .uiControlSize(-1)
        .padding(12)
        .frame(width: 300, alignment: .leading)
    }
}
