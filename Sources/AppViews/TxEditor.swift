// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import Engine
import SwiftUI
import Localization

struct TxEditor: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("TX").font(.caption.bold()).foregroundStyle(.secondary)
                Picker("", selection: $model.sendMode) {
                    Text(L("po znacích")).tag(SendMode.char)
                    Text(L("po slovech")).tag(SendMode.word)
                    Text(L("po řádcích")).tag(SendMode.line)
                }.pickerStyle(.segmented).frame(width: 260)
                Spacer()
                MessagesMenu(model: model)
                Button(L("Odeslat vše")) { Task { await model.sendDraft(mode: .char) } }
                Button(L("Smazat")) { model.txDraft = "" }
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
