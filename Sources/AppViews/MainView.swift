// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppCore
import AppUI
import Localization
import SwiftUI

public struct MainView: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                TopBar(model: model)
                Divider()
                VSplitView {
                    SpectrumView(model: model).frame(minHeight: 50, idealHeight: 80)
                    WaterfallView(model: model).frame(minHeight: 90, idealHeight: 150)
                    RxTextView(model: model).frame(minHeight: 140)
                    if model.settings.decoders.secondEnabled {
                        SecondDecoderPanel(model: model).frame(minHeight: 60, idealHeight: 90)
                    }
                    TxEditor(model: model).frame(minHeight: 70, idealHeight: 90)
                }
                MacroBar(model: model)
                StatusBar(model: model)
            }
            .frame(minWidth: 640)
            QSOPanel(model: model).frame(minWidth: 270, idealWidth: 310, maxWidth: 420)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

struct StatusBar: View {
    @Bindable var model: AppModel
    /// A fixed start for the rate timer; `.now` in the schedule would create a new schedule on every render.
    @State private var timelineStart = Date()
    var body: some View {
        HStack(spacing: 8) {
            if let m = model.messages.last {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(m).lineLimit(1).truncationMode(.tail)
                Button("OK") { model.dismissMessages() }.buttonStyle(.borderless)
            }
            Spacer()
            if model.settings.contest.enabled {
                // recompute every 30 s - the rate drops even without new QSOs
                TimelineView(.periodic(from: timelineStart, by: 30)) { tl in
                    let st = model.logStats(now: tl.date)
                    Text(L("QSO %ld · 10 min: %ld/h · 60 min: %ld/h", st.total, st.rate10, st.rate60))
                        .monospacedDigit().foregroundStyle(.secondary)
                        .hint(L("Rychlost závodu: počet spojení za posledních 10 a 60 minut přepočtený na hodinu"))
                }
                if let s = model.score {
                    Divider().frame(height: 12)
                    Text(L("Skóre %@", ScoreTally.format(s.score))).monospacedDigit().foregroundStyle(.secondary)
                        .hint(L("Odhad skóre závodu podle pravidel předvolby (okno Okno → Skóre)"))
                }
                Divider().frame(height: 12)
            }
            Text(model.apiStatus).foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.bar)
    }
}
