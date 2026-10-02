// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppCore
import AppKit
import AppUI
import QSOLog
import SwiftUI
import Localization

/// QTC for the WAE DX Contest (only in the WAE contest format): status, sending and receiving a series right in the QSO panel,
/// so that words in the receive window can be clicked while receiving.
struct QTCPanel: View {
    @Bindable var model: AppModel
    @State private var sending: [QTCLine]?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                status
                if model.qtcReceive != nil { receiveEditor }
                else if let lines = sending { sendEditor(lines) }
                else { idleButtons }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: { Text("QTC (WAE)").uiFont(.subheadline, weight: .bold) }
        .task(id: model.qso.call) {
            if model.qtcPending == nil { sending = nil }           // the list belongs to the station it was prepared for
            await model.refreshQTC()
        }
    }

    @ViewBuilder var status: some View {
        if let st = model.qtcStatus {
            let call = model.qso.call.isEmpty ? "—" : model.qso.call
            Text(L("S %@: vyměněno %ld/10 · k odeslání %ld · další série %ld", call, st.exchanged, st.available.count, st.nextSeries))
                .uiFont(.caption).fixedSize(horizontal: false, vertical: true)
            if st.differentContinent == false {
                Text(L("Stejný kontinent – v RTTY se QTC vyměňují jen mezi kontinenty.")).uiFont(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L("Body za QTC celkem: %ld", st.points)).uiFont(.caption).foregroundStyle(.secondary)
        }
    }

    var sameContinent: Bool { model.qtcStatus?.differentContinent == false }

    var idleButtons: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Button("QTC?") { Task { await model.qtcPhrase(.ask) } }.hint(L("Zeptat se, zda má protistanice QTC"))
                Button(L("QRV – přijmout")) { Task { await model.qtcQRVReceive() } }
                    .disabled(model.qso.call.isEmpty || sameContinent)
                    .hint(L("Protistanice nabízí QTC: otevřít příjem a odvysílat QRV"))
            }
            HStack(spacing: 4) {
                Button(L("Přijmout…")) { model.startQTCReceive() }.disabled(model.qso.call.isEmpty || sameContinent)
                    .hint(L("Otevřít příjem QTC bez vysílání (série už přišla nebo přijde)"))
                Button(L("Poslat…")) {
                    sending = Array((model.qtcStatus?.available ?? []).prefix(10))
                }
                .disabled(model.qso.call.isEmpty || sameContinent || (model.qtcStatus?.available.isEmpty ?? true))
            }
        }
        .uiControlSize(-1)
    }

    func sendEditor(_ lines: [QTCLine]) -> some View {
        let n = model.qtcPending?.number ?? model.qtcStatus?.nextSeries ?? 1
        return VStack(alignment: .leading, spacing: 4) {
            Text(L("QTC %ld/%ld pro %@", n, lines.count, model.qtcPending?.counterpart ?? model.qso.call)).uiFont(.caption, weight: .bold)
            ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                HStack {
                    Text("\(i + 1). \(QTCText.line(l))").uiFont(.caption, design: .monospaced)
                    Spacer()
                    if model.qtcPending != nil {
                        Button("↻") { Task { await model.qtcRepeat(i + 1) } }.hint(L("Zopakovat řádek (AGN %ld)", i + 1))
                            .uiControlSize(-2)
                    } else {
                        Button { sending?.remove(at: i) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).hint(L("Vynechat"))
                    }
                }
            }
            HStack {
                Button("QRV?") { Task { await model.qtcPhrase(.qrvQuery) } }
                Button(L("Poslat vše")) { Task { await model.qtcSend(lines) } }.disabled(lines.isEmpty)
            }
            HStack {
                Button(L("Potvrzeno – uložit")) {
                    Task { await model.qtcConfirmSent(); if model.qtcPending == nil { sending = nil } }
                }
                    .disabled(model.qtcPending == nil)
                    .hint(L("Protistanice potvrdila příjem (R R ALL OK)"))
                Button(L("Zrušit")) { Task { await model.qtcCancelSent(); sending = nil } }
            }
        }
        .uiControlSize(-1)
    }

    var receiveEditor: some View {
        let d = model.qtcReceive ?? AppModel.QTCReceiveDraft()
        let rows = d.count ?? max(1, d.lines.lastIndex { $0 != nil }.map { $0 + 1 } ?? 1)
        return VStack(alignment: .leading, spacing: 4) {
            Text(L("Od %@", d.counterpart)).uiFont(.caption, weight: .bold)
            HStack {
                Text(L("Série")).uiFont(.caption)
                TextField("n/k", text: Binding(get: { d.number.map { "\($0)/\(d.count ?? 0)" } ?? "" },
                                               set: { model.qtcSetHeader($0) }))
                    .frame(width: 60).uiFont(.caption, design: .monospaced)
                Spacer()
                Button(L("Načíst z příjmu")) { NSApp.keyWindow?.makeFirstResponder(nil); model.qtcFillFromRx() }.hint(L("Rozebrat text přijatý od „Přijmout…“"))
            }
            ForEach(0..<min(rows, 10), id: \.self) { i in
                HStack {
                    Text("\(i + 1).").uiFont(.caption, design: .monospaced).frame(width: 20, alignment: .trailing)
                    TextField("HHMM ZNAČKA NNN", text: Binding(get: { d.lines[i].map(QTCText.line) ?? "" },
                                                              set: { model.qtcSetLine(i, $0) }))
                        .uiFont(.caption, design: .monospaced)
                        // a new field when the content changes from the receive side - a half-typed (empty) field must not overwrite the loaded row
                        .id("\(i)-\(d.lines[i].map(QTCText.line) ?? "")")
                    Button("AGN") { Task { await model.qtcPhrase(.agn(i + 1)) } }.uiControlSize(-2)
                }
            }
            Text(L("Klik na slova v příjmu: série n/k, pak čas, značka, číslo.")).uiFont(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Button("QRV") { Task { await model.qtcPhrase(.qrv) } }
                Button(L("Uložit – R R ALL OK")) {
                    // save first; only send the confirmation when the series was actually written
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    Task { if await model.qtcSaveReceived() { await model.qtcPhrase(.allOK) } }
                }
                .disabled(d.number == nil || !d.lines.contains { $0 != nil })
                Button(L("Zrušit")) { model.cancelQTCReceive() }
            }
        }
        .uiControlSize(-1)
    }
}
