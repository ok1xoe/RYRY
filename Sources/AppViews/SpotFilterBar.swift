// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import Localization
import Spots
import SwiftUI

/// Ovládání filtru zobrazení spotů v okně Spoty (a v Nastavení → Spoty): tlačítka, která otevřou okna
/// „Filtr pásem“ a „Filtr módů“, a zaškrtávátko „Jen RTTY“. Filtruje se jen zobrazení – přijímají
/// a ukládají se spoty všech pásem a módů. Změna platí hned (bez Použít a bez nového připojení).
public struct SpotFilterBar: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    public init(model: AppModel) { self.model = model }

    /// Popisek skupiny módů (názvy módů se nepřekládají, jen „ostatní“).
    public static func modeLabel(_ g: SpotModeGroup) -> String {
        switch g {
        case .rtty: "RTTY"
        case .cw: "CW"
        case .psk: "PSK"
        case .digi: "FT8/FT4"
        case .ssb: "SSB"
        case .other: L("ostatní")
        }
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(L("Filtry:")).foregroundStyle(.secondary)
            Button(L("Pásma")) { openWindow(id: SpotFilterWindowID.bands) }
                .hint(L("Otevře okno se zaškrtávátky pásem"))
            Button(L("Módy")) { openWindow(id: SpotFilterWindowID.modes) }
                .hint(L("Otevře okno se zaškrtávátky skupin módů"))
            Toggle(L("Jen RTTY"), isOn: Binding(get: { model.settings.spots.rttyOnly },
                                                set: { v in model.setSpots { $0.setRTTYOnly(v) } }))
                .toggleStyle(.checkbox)
                .hint(L("Zobrazí jen RTTY spoty; odškrtnutí vrátí předchozí volbu módů"))
            Spacer(minLength: 0)
        }
        .font(.caption)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
