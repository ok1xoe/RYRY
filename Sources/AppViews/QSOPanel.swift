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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QSO").font(.headline)
            Form {
                QSOField(model: model, label: "Call", field: "call").font(.title3.monospaced())
                if let c = model.dxcc {
                    let local = Date().addingTimeInterval(c.utcOffsetHours * 3600)
                    LabeledContent("Země") {
                        Text("\(c.name) · \(c.continent) · CQ \(c.cqZone) · ITU \(c.ituZone) · \(Self.hm.string(from: local))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                QSOField(model: model, label: "Name", field: "name")
                QSOField(model: model, label: "QTH", field: "qth")
                QSOField(model: model, label: "Locator", field: "locator")
                HStack {
                    QSOField(model: model, label: "RST s", field: "rstSent")
                    QSOField(model: model, label: "RST r", field: "rstRcvd")
                }
                HStack {
                    QSOField(model: model, label: "Nr s", field: "serialSent")
                    QSOField(model: model, label: "Nr r", field: "serialRcvd")
                }
                QSOField(model: model, label: "Exch r", field: "exchangeRcvd")
                QSOField(model: model, label: "Notes", field: "notes")
            }
            HStack {
                Button("Log") { Task { await model.logQSO() } }.help("Zalogovat (⌘L)")
                Button("Clear") { Task { await model.clearQSO() } }
            }
            if model.qtcEnabled { QTCPanel(model: model) }
            if !model.previousQSOs.isEmpty {
                Text("Předchozí spojení (\(model.previousQSOs.count))").font(.subheadline.bold())
                List(model.previousQSOs.prefix(20)) { r in
                    VStack(alignment: .leading) {
                        Text(r.timeOn.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                        Text("\(r.band ?? "?") \(r.mode) \(r.name ?? "")").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 80)
            }
            Spacer()
        }
        .padding(10)
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
