// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import AppUI
import Localization
import Settings
import Spots
import SwiftUI

/// The "Spots" window: DX cluster and RBN. Double-clicking a spot tunes the rig and puts the call into the QSO window.
public struct SpotsWindow: View {
    @Bindable var model: AppModel
    @State private var selection: Set<Spot.ID> = []
    public init(model: AppModel) { self.model = model }

    static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HH:mm"; return f
    }()

    static func stateText(_ s: TelnetSpotClient.State, enabled: Bool) -> String {
        if !enabled { return L("vypnuto") }
        switch s {
        case .off: return L("vypnuto")
        case .connecting: return L("připojuji…")
        case .connected: return L("připojeno")
        case .reconnecting(let sec): return L("výpadek, další pokus za %ld s", Int(sec.rounded()))
        case .failed: return L("chybí značka nebo adresa")
        }
    }
    static func stateColor(_ s: TelnetSpotClient.State, enabled: Bool) -> Color {
        guard enabled else { return .gray }
        switch s { case .connected: return .green; case .connecting: return .yellow; case .off: return .gray; default: return .red }
    }

    func status(_ title: String, _ s: TelnetSpotClient.State, enabled: Bool) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Self.stateColor(s, enabled: enabled)).frame(width: 8, height: 8)
            Text(title + ": " + Self.stateText(s, enabled: enabled)).font(.caption)
        }
    }

    static func logLabel(_ s: SpotLogIndex.Status) -> String {
        switch s { case .none: ""; case .worked: "✓"; case .workedOnBand: L("✓ pásmo") }
    }

    public var body: some View {
        let feed = model.spotFeed
        let index = model.spotLogIndex
        let rows = feed.visible
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                status("DX cluster", feed.clusterState, enabled: model.settings.spots.clusterEnabled)
                status("RBN", feed.rbnState, enabled: model.settings.spots.rbnEnabled)
                Spacer()
                Text(L("%ld z %ld spotů", rows.count, feed.book.count)).font(.caption).foregroundStyle(.secondary)
                LabeledContent(L("Posun (Hz)")) {
                    TextField("", value: Binding(get: { model.settings.spots.offsetHz },
                                                 set: { v in model.setSpots { $0.offsetHz = min(max(v, SpotSettings.offsetRange.lowerBound), SpotSettings.offsetRange.upperBound) } }),
                              format: .number.grouping(.never)).multilineTextAlignment(.trailing).frame(width: 64)
                }.fixedSize()
            }
            SpotFilterBar(model: model)
            if !model.settings.spots.clusterEnabled && !model.settings.spots.rbnEnabled {
                Text(L("Spoty jsou vypnuté – zapněte DX cluster nebo RBN v Nastavení → Spoty."))
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            Table(rows, selection: $selection) {
                TableColumn(L("UTC")) { s in Text(Self.timeFmt.string(from: s.time)).monospacedDigit() }.width(46)
                TableColumn("kHz") { s in Text(String(format: "%.1f", s.frequencyKHz)).monospacedDigit() }.width(70)
                TableColumn("Call") { s in Text(s.call).fontWeight(.semibold) }.width(90)
                TableColumn(L("Země")) { s in Text(model.app?.country(for: s.call)?.name ?? "") }.width(min: 90, ideal: 130)
                TableColumn("Az") { s in
                    Text(model.beam(call: s.call, locator: "").map { String(QSOPanel.azimuthInt($0.shortAzimuth)) + "°" } ?? "")
                        .monospacedDigit().foregroundStyle(.secondary)
                        .hint(L("Azimut krátkou cestou podle země spotu"))
                }.width(38)
                TableColumn("Log") { s in
                    let st = index.status(of: s)
                    Text(Self.logLabel(st)).foregroundStyle(st == .workedOnBand ? Color.orange : Color.secondary)
                }.width(56)
                TableColumn(L("Potřeba")) { s in
                    let needed = model.neededReasons(for: s)
                    if !needed.isEmpty {
                        Label(L("potřebné"), systemImage: "star.fill").labelStyle(.titleAndIcon).font(.caption)
                            .foregroundStyle(.pink).help(AppModel.neededText(needed))
                    }
                }.width(74)
                TableColumn(L("Komentář")) { s in Text(s.comment).lineLimit(1) }
                TableColumn("Spotter") { s in Text(s.spotter).foregroundStyle(.secondary) }.width(90)
            }
            .contextMenu(forSelectionType: Spot.ID.self) { _ in } primaryAction: { ids in
                guard let id = ids.first, let spot = rows.first(where: { $0.id == id }) else { return }
                Task { await model.useSpot(spot) }
            }
            Text(L("Dvojklik: nastaví rig na frekvenci spotu + posun a vloží značku do QSO okna. Rádio v režimu LSB/AFSK s mark 2125 Hz potřebuje posun +2125 Hz. „✓ pásmo“ = značka je už v logu na tomto pásmu."))
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            ClusterPanel(model: model)
        }
        .padding(8)
        .frame(minWidth: 720, minHeight: 440)
    }
}
