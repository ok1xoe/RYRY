// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import QSOLog
import SwiftUI
import UniformTypeIdentifiers

/// Uloží log ve formátu Cabrillo: dialog s rozsahem (UTC, výchozí posledních 48 h) a volbou „jen závodní spojení“.
@MainActor public func exportCabrillo(_ model: AppModel) {
    let p = NSSavePanel()
    let base = model.settings.contest.name.isEmpty ? "log" : model.settings.contest.name
    p.nameFieldStringValue = "\(model.settings.station.call.isEmpty ? "mmtty4mac" : model.settings.station.call)-\(base).log"
    p.allowedContentTypes = [UTType(filenameExtension: "log") ?? .plainText, UTType(filenameExtension: "cbr") ?? .plainText, .plainText]
    func picker(_ d: Date) -> NSDatePicker {
        let dp = NSDatePicker(); dp.datePickerStyle = .textFieldAndStepper
        dp.datePickerElements = [.yearMonthDay, .hourMinute]; dp.timeZone = TimeZone(identifier: "UTC"); dp.dateValue = d
        return dp
    }
    let from = picker(Date().addingTimeInterval(-48 * 3600)), to = picker(Date().addingTimeInterval(3600))
    let only = NSButton(checkboxWithTitle: "Jen závodní spojení (s číslem nebo výměnou)", target: nil, action: nil)
    only.state = model.settings.contest.enabled ? .on : .off
    let row1 = NSStackView(views: [NSTextField(labelWithString: "Od (UTC):"), from, NSTextField(labelWithString: "do:"), to])
    let box = NSStackView(views: [row1, only]); box.orientation = .vertical; box.alignment = .leading
    box.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    p.accessoryView = box
    guard p.runModal() == .OK, let url = p.url else { return }
    let f = from.dateValue, t = to.dateValue, c = only.state == .on
    Task { @MainActor in
        let text = await model.cabrilloText(from: f, to: t, contestOnly: c)
        do { try Data(text.utf8).write(to: url, options: .atomic) }
        catch { NSAlert(error: error).runModal() }
    }
}

public struct LogWindow: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var selection: QSORecord.ID?
    @State private var editing: QSORecord?
    @State private var confirmDelete: QSORecord?
    public init(model: AppModel) { self.model = model }

    var filtered: [QSORecord] {
        let s = search.uppercased()
        return s.isEmpty ? model.logRecords : model.logRecords.filter { $0.call.contains(s) || ($0.name ?? "").uppercased().contains(s) }
    }

    public var body: some View {
        TabView {
            qsoList.tabItem { Text("Spojení (\(model.logRecords.count))") }
            QTCLogView(model: model).tabItem { Text("QTC (\(model.qtcSummary.points))") }
        }
    }

    var qsoList: some View {
        VStack(spacing: 0) {
            Table(filtered, selection: $selection) {
                TableColumn("Čas (UTC)") { r in Text(Self.fmt.string(from: r.timeOn)).monospacedDigit() }.width(min: 120, ideal: 140)
                TableColumn("Značka") { r in Text(r.call).bold() }.width(min: 80, ideal: 100)
                TableColumn("Pásmo") { r in Text(r.band ?? "") }.width(50)
                TableColumn("kHz") { r in Text(r.frequency.map { String(format: "%.1f", $0 / 1000) } ?? "") }.width(70)
                TableColumn("Mód") { r in Text(r.mode) }.width(50)
                TableColumn("RST s/r") { r in Text("\(r.rstSent ?? "")/\(r.rstRcvd ?? "")") }.width(70)
                TableColumn("Nr s/r") { r in
                    Text("\(r.serialSent.map { String(format: "%03d", $0) } ?? r.exchangeSent ?? "")/\(r.serialRcvd.map { String(format: "%03d", $0) } ?? r.exchangeRcvd ?? "")")
                }.width(70)
                TableColumn("Jméno") { r in Text(r.name ?? "") }
                TableColumn("QTH") { r in Text(r.qth ?? "") }
                TableColumn("Země") { r in Text(r.country ?? "") }
            }
            .contextMenu(forSelectionType: QSORecord.ID.self) { ids in
                if let id = ids.first, let r = model.logRecords.first(where: { $0.id == id }) {
                    Button("Upravit…") { editing = r }
                    Button("Smazat…", role: .destructive) { confirmDelete = r }
                }
            } primaryAction: { ids in
                if let id = ids.first { editing = model.logRecords.first { $0.id == id } }
            }
            HStack {
                Text("\(filtered.count) spojení").foregroundStyle(.secondary)
                Spacer()
                Button("Exportovat Cabrillo…") { exportCabrillo(model) }
            }.padding(6).font(.caption)
        }
        .searchable(text: $search, prompt: "Značka nebo jméno")
        .sheet(item: $editing) { r in QSOEditor(record: r) { new in Task { await model.updateLog(new) } } }
        .confirmationDialog("Smazat spojení?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            presenting: confirmDelete) { r in
            Button("Smazat \(r.call)", role: .destructive) { Task { await model.deleteLog(r.id) } }
        }
        .frame(minWidth: 700, minHeight: 300)
    }

    static let fmt: DateFormatter = {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()
}

struct QSOEditor: View {
    @State var record: QSORecord
    let onSave: (QSORecord) -> Void
    @Environment(\.dismiss) private var dismiss

    func text(_ kp: WritableKeyPath<QSORecord, String?>) -> Binding<String> {
        Binding(get: { record[keyPath: kp] ?? "" }, set: { record[keyPath: kp] = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        Form {
            TextField("Značka", text: Binding(get: { record.call }, set: { record.call = $0.uppercased() }))
            DatePicker("Začátek (UTC)", selection: $record.timeOn)
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            TextField("Frekvence (Hz)", value: $record.frequency, format: .number)
            TextField("Mód", text: $record.mode)
            TextField("RST odeslané", text: text(\.rstSent))
            TextField("RST přijaté", text: text(\.rstRcvd))
            TextField("Jméno", text: text(\.name))
            TextField("QTH", text: text(\.qth))
            TextField("Lokátor", text: text(\.grid))
            TextField("Poznámka", text: text(\.comment))
            HStack {
                Spacer()
                Button("Zrušit") { dismiss() }
                Button("Uložit") { onSave(record); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420)
    }
}

/// Série QTC (WAE): přehled, rozbalení řádků, oprava a smazání; souhrn bodů.
struct QTCLogView: View {
    @Bindable var model: AppModel
    @State private var editing: QTCSeries?
    @State private var confirmDelete: QTCSeries?

    static let fmt: DateFormatter = {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if model.qtcSeries.isEmpty {
                Text("Žádné série QTC. QTC se vyměňují ve formátu závodu WAE (Nastavení → Závod).")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.qtcSeries) { s in
                        DisclosureGroup {
                            ForEach(Array(s.lines.enumerated()), id: \.offset) { i, l in
                                Text("\(i + 1). \(QTCText.line(l))").font(.callout.monospaced())
                            }
                        } label: {
                            HStack {
                                Image(systemName: s.direction == .sent ? "arrow.up.right" : "arrow.down.left")
                                    .foregroundStyle(s.direction == .sent ? .orange : .green)
                                Text(s.direction == .sent ? "Odesláno" : "Přijato").frame(width: 70, alignment: .leading)
                                Text("QTC \(s.number)/\(s.groupSize)").monospacedDigit().frame(width: 80, alignment: .leading)
                                Text(s.counterpart).bold().frame(width: 100, alignment: .leading)
                                Text(Self.fmt.string(from: s.time)).monospacedDigit()
                                Text(Bands.band(forHz: s.frequency) ?? "").foregroundStyle(.secondary).frame(width: 50)
                                Spacer()
                                Text("\(s.count) b.").monospacedDigit()
                            }
                        }
                        .contextMenu {
                            Button("Upravit…") { editing = s }
                            Button("Smazat…", role: .destructive) { confirmDelete = s }
                        }
                    }
                }
            }
            HStack {
                let sum = model.qtcSummary
                Text("Série: \(sum.seriesCount) · odesláno \(sum.sent) QTC · přijato \(sum.received) QTC · body za QTC \(sum.points) · QSO \(model.logRecords.count)")
                    .foregroundStyle(.secondary)
                Spacer()
            }.padding(6).font(.caption)
        }
        .task { await model.refreshQTCSeries() }
        .sheet(item: $editing) { s in QTCSeriesEditor(series: s) { new in Task { await model.updateQTCSeries(new) } } }
        .confirmationDialog("Smazat sérii QTC?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            presenting: confirmDelete) { s in
            Button("Smazat QTC \(s.number)/\(s.groupSize) (\(s.counterpart))", role: .destructive) { Task { await model.deleteQTCSeries(s.id) } }
        }
    }
}

/// Oprava série: protistanice, číslo série a řádky (jeden řádek „HHMM ZNAČKA NNN“ na řádek).
struct QTCSeriesEditor: View {
    @State var series: QTCSeries
    let onSave: (QTCSeries) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var parsed: [QTCLine?] { text.split(separator: "\n", omittingEmptySubsequences: true).map { QTCText.parseLine(String($0)) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(series.direction == .sent ? "Odeslaná série QTC" : "Přijatá série QTC").font(.headline)
            Form {
                TextField("Protistanice", text: $series.counterpart)
                Stepper("Číslo série: \(series.number)", value: $series.number, in: 1...999)
            }
            Text("Řádky (HHMM ZNAČKA NNN):").font(.caption)
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 180)
            if parsed.contains(where: { $0 == nil }) || parsed.count > 10 || parsed.isEmpty {
                Text("Každý řádek musí mít tvar „HHMM ZNAČKA NNN“, 1–10 řádků.").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Zrušit") { dismiss() }
                Button("Uložit") {
                    var s = series
                    s.counterpart = s.counterpart.uppercased()
                    s.lines = parsed.compactMap { $0 }
                    onSave(s); dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsed.isEmpty || parsed.count > 10 || parsed.contains { $0 == nil } || series.counterpart.isEmpty)
            }
        }
        .padding()
        .frame(width: 440)
        .onAppear { text = series.lines.map(QTCText.line).joined(separator: "\n") }
    }
}
