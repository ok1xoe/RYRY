// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import QSOLog
import Settings
import AppCore
import SwiftUI
import Localization

struct QSOPanel: View {
    @Bindable var model: AppModel
    /// Místní čas protistanice (hh:mm).
    static let hm: DateFormatter = {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HH:mm"; return f
    }()

    static func contestTitle(_ c: ContestSettings) -> String {
        let f: String
        switch c.format {
        case .serial: f = c.exchange.isEmpty ? L("RST + číslo") : L("RST + výměna")
        case .cqrj: f = "CQ/RJ"
        case .bartg: f = "BARTG"
        case .ped: f = "PED"
        case .wae: f = "WAE + QTC"
        case .zone: f = L("RST + CQ zóna")
        }
        return c.name.isEmpty ? L("závod") + " · \(f)" : "\(c.name) · \(f)"
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
                                if field == "call" {
                                    HStack(spacing: 6) {
                                        QSOField(model: model, label: "", field: field,
                                                 onTyping: { model.superCheckPreview($0) })
                                            .font(.title3.monospaced())
                                        if model.isDupe {
                                            Text("DUPE").font(.caption.bold()).foregroundStyle(.white)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(.red, in: RoundedRectangle(cornerRadius: 4))
                                                .hint(L("Duplicita: se stanicí už je v tomto závodě spojení na stejném pásmu a módu"))
                                        }
                                    }.gridCellColumns(3)
                                } else {
                                    QSOField(model: model, label: "", field: field).gridCellColumns(3)
                                }
                            }
                            if field == "call", !model.scpPartial.isEmpty || !model.scpNear.isEmpty {
                                GridRow {
                                    Color.clear.frame(width: 1, height: 1)
                                    SuperCheckList(model: model).gridCellColumns(3)
                                }
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
                                    label(L("Země"))
                                    Text("\(c.name) · \(c.continent) · CQ \(c.cqZone) · ITU \(c.ituZone) · \(Self.hm.string(from: local)) \(L("místně"))")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .gridCellColumns(3)
                                }
                            }
                        }
                    }
                }
                FrequencyRow(model: model)
                if !model.callbookStatus.isEmpty {
                    Text(model.callbookStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack {
                    Button("Log") { Task { await model.logQSO() } }.hint(L("Zalogovat (⌘L)"))
                    Button("Clear") { Task { await model.clearQSO() } }
                }
                if QSOLayout.showsQTC(model.settings.contest) { QTCPanel(model: model) }
                if !model.previousQSOs.isEmpty {
                    Text(L("Předchozí spojení (%ld)", model.previousQSOs.count)).font(.subheadline.bold())
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
    /// Volá se při každé změně textu (Super Check Partial u značky).
    var onTyping: ((String) -> Void)? = nil
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit { commit() }
            .onChange(of: focused) { if !focused { commit() } }
            .onChange(of: text) { _, t in if focused { onTyping?(t) } }
            .onChange(of: model.qso.value(field) ?? "") { _, v in if !focused { text = v } }
            .onAppear { text = model.qso.value(field) ?? "" }
    }

    private func commit() {
        guard text != (model.qso.value(field) ?? "") else { return }
        let v = text
        Task { await model.setQSOField(field, v) }
    }
}

/// Návrhy značek (Super Check Partial): klik vloží značku do QSO okna.
struct SuperCheckList: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !model.scpPartial.isEmpty { chips(model.scpPartial, color: .secondary) }
            if !model.scpNear.isEmpty {
                HStack(spacing: 4) {
                    Text("≈").font(.caption.bold()).foregroundStyle(.orange).hint(L("Značky lišící se o jeden znak"))
                    chips(model.scpNear, color: .orange)
                }
            }
        }
    }

    func chips(_ calls: [String], color: Color) -> some View {
        // jednoduchý zalamovaný seznam (ViewThatFits by nestačil) – po řádcích max. 4 značky
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(stride(from: 0, to: min(calls.count, 12), by: 4)), id: \.self) { i in
                HStack(spacing: 4) {
                    ForEach(calls[i..<min(i + 4, calls.count, 12)], id: \.self) { c in
                        Button(c) { Task { await model.setQSOField("call", c) } }
                            .buttonStyle(.borderless).font(.caption.monospaced()).foregroundStyle(color)
                    }
                }
            }
        }
    }
}

/// Pásmo a frekvence: z rigu, nebo ručně (bez CAT) – zapíše se do logu.
struct FrequencyRow: View {
    @Bindable var model: AppModel
    var body: some View {
        HStack(spacing: 6) {
            Text(L("Pásmo")).font(.callout).foregroundStyle(.secondary)
            if let f = model.rig?.frequency, model.rig?.online == true {
                Text("\(Bands.band(forHz: f) ?? "?") · \(QSOFields.kHzString(f)) kHz").monospacedDigit()
                Text("(rig)").font(.caption).foregroundStyle(.secondary)
            } else {
                Menu(Bands.band(forHz: model.qso.frequency) ?? L("zvolit")) {
                    ForEach(AppModel.bandPresets, id: \.0) { b in
                        Button("\(b.0) (\(Int(b.1)) kHz)") { Task { await model.setQSOField("freq", String(b.1)) } }
                    }
                    Divider()
                    Button(L("Bez frekvence")) { Task { await model.setQSOField("freq", "") } }
                }.fixedSize()
                QSOField(model: model, label: "kHz", field: "freq").frame(width: 90)
                Text("kHz").font(.caption).foregroundStyle(.secondary)
            }
        }
        .hint(L("Bez rigu zadejte pásmo nebo frekvenci ručně – zapíše se do logu"))
    }
}
