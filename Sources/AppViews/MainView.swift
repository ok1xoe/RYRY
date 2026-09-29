// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
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
    var body: some View {
        HStack(spacing: 8) {
            if let m = model.messages.last {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(m).lineLimit(1).truncationMode(.tail)
                Button("OK") { model.dismissMessages() }.buttonStyle(.borderless)
            }
            Spacer()
            Text(model.apiStatus).foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.bar)
    }
}
