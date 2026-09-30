// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import QSOLog
import Settings
import AppCore
import Foundation
import SwiftUI
import Localization

struct QSOPanel: View {
    @Bindable var model: AppModel
    /// The other station's local time (hh:mm).
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

    static func azimuthInt(_ az: Double) -> Int { Int(az.rounded()) % 360 }

    /// "az 312° · 1 234 km · from the locator" (short path).
    static func beamShort(_ b: Geo.Beam) -> String {
        let src = b.ownSource == .locator && b.remoteSource == .locator ? L("z lokátoru") : L("podle země")
        return L("az %ld° · %@ km · %@", azimuthInt(b.shortAzimuth), Geo.formatKm(b.shortKm), src)
    }

    /// Long path (the opposite direction, the rest of the Earth's circumference).
    static func beamLong(_ b: Geo.Beam) -> String {
        L("dlouhá cesta %ld° · %@ km", azimuthInt(b.longAzimuth), Geo.formatKm(b.longKm))
    }

    static func beamHint(_ b: Geo.Beam) -> String {
        let own = b.ownSource == .locator ? L("z lokátoru ve Stanici") : L("podle země vlastní značky")
        let remote = b.remoteSource == .locator ? L("z lokátoru protistanice") : L("podle země protistanice (přibližně)")
        return L("Vlastní poloha %@, protistanice %@", own, remote)
    }

    /// The label in the grid's left column.
    func label(_ t: String) -> some View {
        Text(t).font(.callout).foregroundStyle(.secondary).gridColumnAlignment(.trailing).lineLimit(1).fixedSize()
    }

    var body: some View {
        // A scrolling column: the content (QTC reception with 10 rows, previous QSOs) must not be pushed out of the window,
        // and it adapts to the width - long texts wrap instead of being clipped.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("QSO").font(.headline)
                    if model.settings.contest.enabled {
                        Text(Self.contestTitle(model.settings.contest)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.esmActive { ESMBar(model: model) }
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                    // fields according to the contest (an ordinary QSO outside a contest, in a contest only the given format's exchange)
                    ForEach(Array(QSOLayout.rows(for: model.settings.contest).enumerated()), id: \.offset) { _, row in
                        switch row {
                        case .single(let field, let title):
                            GridRow {
                                label(title)
                                if field == "call" {
                                    HStack(spacing: 6) {
                                        QSOField(model: model, label: "", field: field, esm: true,
                                                 onTyping: { model.superCheckPreview($0) })
                                            .font(.title3.monospaced())
                                        if model.isDupe {
                                            Text("DUPE").font(.caption.bold()).foregroundStyle(.white)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(.red, in: RoundedRectangle(cornerRadius: 4))
                                                .hint(L("Duplicita: se stanicí už je v tomto závodě spojení na stejném pásmu (u vlastního závodu i módu)"))
                                        }
                                        if !model.isDupe, !model.newMultiplier.isEmpty {
                                            Text("NEW MULT").font(.caption.bold()).foregroundStyle(.white)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(.green, in: RoundedRectangle(cornerRadius: 4))
                                                .hint(L("Nový násobič: %@", model.newMultiplier.text))
                                            Text(model.newMultiplier.text).font(.caption).foregroundStyle(.secondary)
                                                .lineLimit(1)
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
                                label(t1); QSOField(model: model, label: "", field: f1, esm: true)
                                label(t2); QSOField(model: model, label: "", field: f2, esm: true)
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
                            if let b = model.beamToRemote {
                                GridRow {
                                    label(L("Směr"))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(Self.beamShort(b)).font(.caption.monospacedDigit())
                                        Text(Self.beamLong(b)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .hint(Self.beamHint(b))
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
        // ESM is only triggered by Enter in the Call and exchange fields (onSubmit in QSOField). A panel-level `.onKeyPress(.return)` would
        // also catch Enter in other fields (Notes, name, kHz) and send a macro unintentionally - which is why there is none here.
    }
}

/// ESM: the Run / S&P switch and a hint about what Enter will send.
struct ESMBar: View {
    @Bindable var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { model.settings.esm.mode }, set: { model.setESMMode($0) })) {
                Text("Run").tag(ESMMode.run)
                Text("S&P").tag(ESMMode.sp)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .hint(L("Režim ESM: Run (volám CQ) / S&P (odpovídám) – %@", model.settings.binding(for: .esmMode).display))
            let step = model.esmStep
            let macro = ESM.macro(for: step, model.settings.esm)
            let key = macro.map { " (" + model.settings.binding(for: .macro($0)).display + ")" } ?? ""
            Text("Enter → " + ESM.title(step) + key)
                .font(.callout.bold().monospaced())
                .foregroundStyle(step == .none ? Color.secondary : Color.white)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(step == .none ? Color.clear : color(step), in: RoundedRectangle(cornerRadius: 4))
                .hint(model.state == .rx ? L("Co pošle Enter v poli Call nebo výměny") : L("Během vysílání Enter nic neposílá"))
            if let macro, model.esmMacroIsEmpty(macro) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .hint(L("Makro %@ je prázdné – nastavte ho v Nastavení → Závod → ESM", model.settings.binding(for: .macro(macro)).display))
            }
        }
    }

    func color(_ s: ESM.Step) -> Color {
        switch s {
        case .tu, .exchangeAndLog: .green
        case .agn: .orange
        default: .accentColor
        }
    }
}

/// A QSO field with local editing: it is committed with Enter or by leaving the field (not after every character),
/// and it picks up the value from the model when that changes from the outside (clicking a word, the API, Clear).
struct QSOField: View {
    @Bindable var model: AppModel
    let label: String
    let field: String
    /// Enter triggers ESM (the Call and exchange fields).
    var esm = false
    /// Called on every text change (Super Check Partial for the callsign).
    var onTyping: ((String) -> Void)? = nil
    @State private var text = ""
    /// An ESM action started from this field is running - until it finishes the text is not written into the model (after logging
    /// the old value would carry over into the new QSO).
    @State private var esmPending = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .overlay(alignment: .trailing) {
                // a discreet label next to a value filled in from the call history (it disappears once the field is edited by hand)
                if let v = model.qso.historyFilled[field], !v.isEmpty, model.qso.value(field) == v {
                    Text(L("z historie")).font(.caption2).foregroundStyle(.secondary).padding(.trailing, 6)
                        .allowsHitTesting(false)
                }
            }
            .onSubmit { submit() }
            .onChange(of: focused) { if !focused { commit() } }
            .onChange(of: text) { _, t in if focused { onTyping?(t) } }
            .onChange(of: model.qso.value(field) ?? "") { _, v in if !focused { text = v } }
            .onAppear { text = model.qso.value(field) ?? "" }
            .onChange(of: model.esmFocusField) { _, f in
                if f == field { focused = true; model.esmFocusField = nil }
            }
    }

    /// Enter: commit the field, then (with ESM) send the macro and move the focus to the next empty field.
    private func submit() {
        guard esm, model.esmActive else { commit(); return }
        guard !esmPending, !model.esmBusy else { return }          // Enter held down
        let changed = text != (model.qso.value(field) ?? ""), v = text
        esmPending = true
        Task {
            if changed { await model.setQSOField(field, v) }
            let next = await model.esmEnter()                     // a logging step only returns once the QSO has been logged
            text = model.qso.value(field) ?? ""          // empty after logging - leaving the field must not restore the old value
            esmPending = false
            if let next { model.esmFocusField = next }
        }
    }

    private func commit() {
        guard !esmPending, text != (model.qso.value(field) ?? "") else { return }
        let v = text
        Task { await model.setQSOField(field, v) }
    }
}

/// Callsign suggestions (Super Check Partial): a click puts the call into the QSO window.
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
        // a simple wrapping list (ViewThatFits would not be enough) - at most 4 calls per row
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

/// Band and frequency: from the rig, or manually (without CAT) - it is written into the log.
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
