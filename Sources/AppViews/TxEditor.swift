// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import Engine
import SwiftUI

struct TxEditor: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("TX").font(.caption.bold()).foregroundStyle(.secondary)
                Picker("", selection: $model.sendMode) {
                    Text("po znacích").tag(SendMode.char)
                    Text("po slovech").tag(SendMode.word)
                    Text("po řádcích").tag(SendMode.line)
                }.pickerStyle(.segmented).frame(width: 260)
                Spacer()
                Button("Odeslat vše") { Task { await model.sendDraft(mode: .char) } }
                Button("Smazat") { model.txDraft = "" }
            }
            TextEditor(text: $model.txDraft)
                .font(.system(size: model.settings.display.fontSize, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: model.txDraft) {
                    // při vysílání se text posílá průběžně podle režimu (jako MMTTY)
                    if model.state != .rx && model.state != .stopped {
                        Task { await model.sendDraft(mode: model.sendMode) }
                    }
                }
        }
        .padding(6)
    }
}
