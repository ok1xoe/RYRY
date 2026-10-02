// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import Localization
import Spots
import SwiftUI

/// Controls for the spot display filter in the Spots window (and in Settings → Spots): buttons that open the
/// "Band filter" and "Mode filter" windows, and the "RTTY only" checkbox. Only the display is filtered - spots of
/// all bands and modes are received and stored. A change takes effect immediately (no Apply and no reconnect).
public struct SpotFilterBar: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    public init(model: AppModel) { self.model = model }

    /// Label of a mode group (mode names are not translated, only "other" is).
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
