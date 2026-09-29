// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import Engine
import AppKit
import Settings
import SwiftUI
import Localization

struct TxEditor: View {
    @Bindable var model: AppModel

    var d: DisplaySettings { model.settings.display }
    var txFont: Font {
        if !d.rxFont.isEmpty, NSFont(name: d.rxFont, size: d.fontSize) != nil { return .custom(d.rxFont, size: d.fontSize) }
        return .system(size: d.fontSize, design: .monospaced)
    }

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
                .font(txFont)
                .foregroundStyle(Color(hex: d.txTextColor) ?? .primary)
                .scrollContentBackground(.hidden)
                .background(Color(hex: d.txBackground) ?? Color(nsColor: .textBackgroundColor))
                .onChange(of: model.txDraft) {
                    // zalamování psaného textu (MMTTY „Word wrap on keyboard“)
                    let col = model.settings.txWindow.wrapColumn
                    if col > 0 {
                        let sending = model.state != .rx && model.state != .stopped
                        let w = TxWrap.wrap(model.txDraft, column: col, startColumn: sending ? model.txSentColumn : 0)
                        if w != model.txDraft { model.txDraft = w; return }
                    }
                    // při vysílání se text posílá průběžně podle režimu (jako MMTTY)
                    if model.state != .rx && model.state != .stopped {
                        Task { await model.sendDraft(mode: model.sendMode) }
                    }
                }
        }
        .padding(6)
    }
}
