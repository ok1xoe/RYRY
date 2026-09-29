// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import QSOLog
import Settings
import SwiftUI

struct QSOPanel: View {
    @Bindable var model: AppModel
    /// Místní čas protistanice (hh:mm).
    static let hm: DateFormatter = {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HH:mm 'místně'"; return f
    }()

    static func contestTitle(_ c: ContestSettings) -> String {
        let f: String
        switch c.format {
        case .serial: f = c.exchange.isEmpty ? "RST + číslo" : "RST + výměna"
        case .cqrj: f = "CQ/RJ"
        case .bartg: f = "BARTG"
        case .ped: f = "PED"
        case .wae: f = "WAE + QTC"
        }
        return c.name.isEmpty ? "závod · \(f)" : "\(c.name) · \(f)"
    }

    /// Popisek v levém sloupci mřížky.
    func label(_ t: String) -> some View {
        Text(t).font(.callout).foregroundStyle(.secondary).gridColumnAlignment(.trailing).lineLimit(1).fixedSize()
    }

    var body: some View {
        // Posuvný sloupec: obsah (příjem QTC s 10 řádky, předchozí spojení) se nesmí vytlačit mimo okno,
        // a do šířky se přizpůsobuje – dlouhé texty se zalamují místo ořezu.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("QSO").font(.headline)
                    if model.settings.contest.enabled {
                        Text(Self.contestTitle(model.settings.contest)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                    // pole podle závodu (bez závodu běžné QSO, v závodě jen výměna daného formátu)
                    ForEach(Array(QSOLayout.rows(for: model.settings.contest).enumerated()), id: \.offset) { _, row in
                        switch row {
                        case .single(let field, let title):
                            GridRow {
                                label(title)
                                QSOField(model: model, label: "", field: field)
                                    .font(field == "call" ? .title3.monospaced() : .body).gridCellColumns(3)
                            }
                        case .pair(let f1, let t1, let f2, let t2):
                            GridRow {
                                label(t1); QSOField(model: model, label: "", field: f1)
                                label(t2); QSOField(model: model, label: "", field: f2)
                            }
                        case .country:
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
                        }
                    }
                }
                HStack {
                    Button("Log") { Task { await model.logQSO() } }.help("Zalogovat (⌘L)")
                    Button("Clear") { Task { await model.clearQSO() } }
                }
                if QSOLayout.showsQTC(model.settings.contest) { QTCPanel(model: model) }
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
