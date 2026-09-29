// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import QSOLog
import SwiftUI

struct QSOPanel: View {
    @Bindable var model: AppModel
    /// Místní čas protistanice (hh:mm).
    static let hm: DateFormatter = {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HH:mm 'místně'"; return f
    }()

    /// Popisek v levém sloupci mřížky.
    func label(_ t: String) -> some View {
        Text(t).font(.callout).foregroundStyle(.secondary).gridColumnAlignment(.trailing).lineLimit(1).fixedSize()
    }

    var body: some View {
        // Posuvný sloupec: obsah (příjem QTC s 10 řádky, předchozí spojení) se nesmí vytlačit mimo okno,
        // a do šířky se přizpůsobuje – dlouhé texty se zalamují místo ořezu.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                Text("QSO").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        label("Call")
                        QSOField(model: model, label: "", field: "call").font(.title3.monospaced()).gridCellColumns(3)
                    }
                    if let c = model.dxcc {
                        let local = Date().addingTimeInterval(c.utcOffsetHours * 3600)
                        GridRow {
                            label("Země")
                            Text("\(c.name) · \(c.continent) · CQ \(c.cqZone) · ITU \(c.ituZone) · \(Self.hm.string(from: local))")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .gridCellColumns(3)
                        }
                    }
                    GridRow { label("Name"); QSOField(model: model, label: "", field: "name").gridCellColumns(3) }
                    GridRow { label("QTH"); QSOField(model: model, label: "", field: "qth").gridCellColumns(3) }
                    GridRow { label("Locator"); QSOField(model: model, label: "", field: "locator").gridCellColumns(3) }
                    GridRow {
                        label("RST s"); QSOField(model: model, label: "599", field: "rstSent")
                        label("RST r"); QSOField(model: model, label: "599", field: "rstRcvd")
                    }
                    GridRow {
                        label("Nr s"); QSOField(model: model, label: "", field: "serialSent")
                        label("Nr r"); QSOField(model: model, label: "", field: "serialRcvd")
                    }
                    GridRow { label("Exch r"); QSOField(model: model, label: "", field: "exchangeRcvd").gridCellColumns(3) }
                    GridRow { label("Notes"); QSOField(model: model, label: "", field: "notes").gridCellColumns(3) }
                }
                HStack {
                    Button("Log") { Task { await model.logQSO() } }.help("Zalogovat (⌘L)")
                    Button("Clear") { Task { await model.clearQSO() } }
                }
                if model.qtcEnabled { QTCPanel(model: model) }
                if !model.previousQSOs.isEmpty {
                    Text("Předchozí spojení (\(model.previousQSOs.count))").font(.subheadline.bold())
                    ForEach(model.previousQSOs.prefix(20)) { r in
                        VStack(alignment: .leading) {
                            Text(r.timeOn.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                            Text("\(r.band ?? "?") \(r.mode) \(r.name ?? "")").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Pole QSO s lokální editací: potvrdí se Enterem nebo opuštěním pole (ne po každém znaku),
/// a převezme hodnotu z modelu, když se změní zvenku (klik na slovo, API, Clear).
struct QSOField: View {
    @Bindable var model: AppModel
    let label: String
    let field: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit { commit() }
            .onChange(of: focused) { if !focused { commit() } }
            .onChange(of: model.qso.value(field) ?? "") { _, v in if !focused { text = v } }
            .onAppear { text = model.qso.value(field) ?? "" }
    }

    private func commit() {
        guard text != (model.qso.value(field) ?? "") else { return }
        let v = text
        Task { await model.setQSOField(field, v) }
    }
}
