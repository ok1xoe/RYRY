// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import AppKit
import AppUI
import QSOLog
import SwiftUI

/// QTC pro WAE DX Contest (jen ve formátu závodu WAE): stav, odeslání a příjem série přímo v QSO panelu,
/// aby šlo během příjmu klikat na slova v okně příjmu.
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
        } label: { Text("QTC (WAE)").font(.subheadline.bold()) }
        .task(id: model.qso.call) {
            if model.qtcPending == nil { sending = nil }           // seznam patří stanici, pro kterou byl připraven
            await model.refreshQTC()
        }
    }

    @ViewBuilder var status: some View {
        if let st = model.qtcStatus {
            let call = model.qso.call.isEmpty ? "—" : model.qso.call
            Text("S \(call): vyměněno \(st.exchanged)/10 · k odeslání \(st.available.count) · další série \(st.nextSeries)")
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            if st.differentContinent == false {
                Text("Stejný kontinent – v RTTY se QTC vyměňují jen mezi kontinenty.").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Body za QTC celkem: \(st.points)").font(.caption).foregroundStyle(.secondary)
        }
    }

    var sameContinent: Bool { model.qtcStatus?.differentContinent == false }

    var idleButtons: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Button("QTC?") { Task { await model.qtcPhrase(.ask) } }.help("Zeptat se, zda má protistanice QTC")
                Button("QRV – přijmout") { Task { await model.qtcQRVReceive() } }
                    .disabled(model.qso.call.isEmpty || sameContinent)
                    .help("Protistanice nabízí QTC: otevřít příjem a odvysílat QRV")
            }
            HStack(spacing: 4) {
                Button("Přijmout…") { model.startQTCReceive() }.disabled(model.qso.call.isEmpty || sameContinent)
                    .help("Otevřít příjem QTC bez vysílání (série už přišla nebo přijde)")
                Button("Poslat…") {
                    sending = Array((model.qtcStatus?.available ?? []).prefix(10))
                }
                .disabled(model.qso.call.isEmpty || sameContinent || (model.qtcStatus?.available.isEmpty ?? true))
            }
        }
        .controlSize(.small)
    }

    func sendEditor(_ lines: [QTCLine]) -> some View {
        let n = model.qtcPending?.number ?? model.qtcStatus?.nextSeries ?? 1
        return VStack(alignment: .leading, spacing: 4) {
            Text("QTC \(n)/\(lines.count) pro \(model.qtcPending?.counterpart ?? model.qso.call)").font(.caption.bold())
            ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                HStack {
                    Text("\(i + 1). \(QTCText.line(l))").font(.caption.monospaced())
                    Spacer()
                    if model.qtcPending != nil {
                        Button("↻") { Task { await model.qtcRepeat(i + 1) } }.help("Zopakovat řádek (AGN \(i + 1))")
                            .controlSize(.mini)
                    } else {
                        Button { sending?.remove(at: i) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Vynechat")
                    }
                }
            }
            HStack {
                Button("QRV?") { Task { await model.qtcPhrase(.qrvQuery) } }
                Button("Poslat vše") { Task { await model.qtcSend(lines) } }.disabled(lines.isEmpty)
            }
            HStack {
                Button("Potvrzeno – uložit") {
                    Task { await model.qtcConfirmSent(); if model.qtcPending == nil { sending = nil } }
                }
                    .disabled(model.qtcPending == nil)
                    .help("Protistanice potvrdila příjem (R R ALL OK)")
                Button("Zrušit") { Task { await model.qtcCancelSent(); sending = nil } }
            }
        }
        .controlSize(.small)
    }

    var receiveEditor: some View {
        let d = model.qtcReceive ?? AppModel.QTCReceiveDraft()
        let rows = d.count ?? max(1, d.lines.lastIndex { $0 != nil }.map { $0 + 1 } ?? 1)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Od \(d.counterpart)").font(.caption.bold())
            HStack {
                Text("Série").font(.caption)
                TextField("n/k", text: Binding(get: { d.number.map { "\($0)/\(d.count ?? 0)" } ?? "" },
                                               set: { model.qtcSetHeader($0) }))
                    .frame(width: 60).font(.caption.monospaced())
                Spacer()
                Button("Načíst z příjmu") { NSApp.keyWindow?.makeFirstResponder(nil); model.qtcFillFromRx() }.help("Rozebrat text přijatý od „Přijmout…“")
            }
            ForEach(0..<min(rows, 10), id: \.self) { i in
                HStack {
                    Text("\(i + 1).").font(.caption.monospaced()).frame(width: 20, alignment: .trailing)
                    TextField("HHMM ZNAČKA NNN", text: Binding(get: { d.lines[i].map(QTCText.line) ?? "" },
                                                              set: { model.qtcSetLine(i, $0) }))
                        .font(.caption.monospaced())
                        // nové pole při změně obsahu z příjmu – rozepsané (prázdné) pole nesmí načtený řádek přepsat
                        .id("\(i)-\(d.lines[i].map(QTCText.line) ?? "")")
                    Button("AGN") { Task { await model.qtcPhrase(.agn(i + 1)) } }.controlSize(.mini)
                }
            }
            Text("Klik na slova v příjmu: série n/k, pak čas, značka, číslo.").font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Button("QRV") { Task { await model.qtcPhrase(.qrv) } }
                Button("Uložit – R R ALL OK") {
                    // nejdřív uložit; potvrzení odeslat jen když se série opravdu zapsala
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    Task { if await model.qtcSaveReceived() { await model.qtcPhrase(.allOK) } }
                }
                .disabled(d.number == nil || !d.lines.contains { $0 != nil })
                Button("Zrušit") { model.cancelQTCReceive() }
            }
        }
        .controlSize(.small)
    }
}
