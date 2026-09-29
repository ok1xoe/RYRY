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
                    WaterfallView(model: model).frame(minHeight: 110, idealHeight: 170)
                    RxTextView(model: model).frame(minHeight: 140)
                    TxEditor(model: model).frame(minHeight: 70, idealHeight: 90)
                }
                MacroBar(model: model)
                StatusBar(model: model)
            }
            .frame(minWidth: 640)
            QSOPanel(model: model).frame(minWidth: 250, idealWidth: 280, maxWidth: 340)
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
