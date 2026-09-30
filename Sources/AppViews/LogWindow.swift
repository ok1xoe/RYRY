// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import QSOLog
import SwiftUI
import Upload
import UniformTypeIdentifiers
import Localization

/// Saves the log in Cabrillo format: a dialog with a range (UTC, last 48 h by default) and a "contest QSOs only" option.
@MainActor public func exportCabrillo(_ model: AppModel) {
    let p = NSSavePanel()
    let base = model.settings.contest.name.isEmpty ? "log" : model.settings.contest.name
    p.nameFieldStringValue = "\(model.settings.station.call.isEmpty ? "RYRY" : model.settings.station.call)-\(base).log"
    p.allowedContentTypes = [UTType(filenameExtension: "log") ?? .plainText, UTType(filenameExtension: "cbr") ?? .plainText, .plainText]
    func picker(_ d: Date) -> NSDatePicker {
        let dp = NSDatePicker(); dp.datePickerStyle = .textFieldAndStepper
        dp.datePickerElements = [.yearMonthDay, .hourMinute]; dp.timeZone = TimeZone(identifier: "UTC"); dp.dateValue = d
        return dp
    }
    let from = picker(Date().addingTimeInterval(-48 * 3600)), to = picker(Date().addingTimeInterval(3600))
    let only = NSButton(checkboxWithTitle: L("Jen závodní spojení (s číslem nebo výměnou)"), target: nil, action: nil)
    only.state = model.settings.contest.enabled ? .on : .off
    let row1 = NSStackView(views: [NSTextField(labelWithString: L("Od (UTC):")), from, NSTextField(labelWithString: L("do:")), to])
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
    @State private var uploadResult: String?
    public init(model: AppModel) { self.model = model }

    var filtered: [QSORecord] {
        let s = search.uppercased()
        return s.isEmpty ? model.logRecords : model.logRecords.filter { $0.call.contains(s) || ($0.name ?? "").uppercased().contains(s) }
    }

    public var body: some View {
        TabView {
            qsoList.tabItem { Text(L("Spojení (%ld)", model.logRecords.count)) }
            QTCLogView(model: model).tabItem { Text("QTC (\(model.qtcSummary.points))") }
        }
    }

    /// QTCs exchanged with the station (WAE): ↓ received, ↑ sent.
    var qtcByCall: [String: (rx: Int, tx: Int)] {
        var d: [String: (rx: Int, tx: Int)] = [:]
        for s in model.qtcSeries {
            let k = QSORecord.baseCall(s.counterpart)
            var v = d[k] ?? (0, 0)
            if s.direction == .received { v.rx += s.count } else { v.tx += s.count }
            d[k] = v
        }
        return d
    }
    static func timeLabel(_ r: QSORecord) -> String { fmt.string(from: r.timeOn) }
    static func khzLabel(_ r: QSORecord) -> String { r.frequency.map { String(format: "%.1f", $0 / 1000) } ?? "" }
    static func rstLabel(_ r: QSORecord) -> String { (r.rstSent ?? "") + "/" + (r.rstRcvd ?? "") }
    static func nrLabel(_ r: QSORecord) -> String {
        let s = r.serialSent.map { String(format: "%03d", $0) } ?? r.exchangeSent ?? ""
        let v = r.serialRcvd.map { String(format: "%03d", $0) } ?? r.exchangeRcvd ?? ""
        return s + "/" + v
    }
    /// Upload status: L = LoTW, e = eQSL, C = Club Log (green = uploaded).
    @ViewBuilder static func uploadBadges(_ r: QSORecord) -> some View {
        HStack(spacing: 4) {
            ForEach([(UploadTarget.lotw, "L"), (.eqsl, "e"), (.clublog, "C")], id: \.0) { t, letter in
                Text(letter).bold()
                    .foregroundStyle(r.isUploaded(t) ? Color.green : Color.secondary.opacity(0.35))
                    .help(r.isUploaded(t) ? "\(t.title): \(fmt.string(from: r.uploads?[t.rawValue] ?? Date()))" : t.title)
            }
        }
    }
    func qtcLabel(_ call: String) -> String {
        guard let v = qtcByCall[QSORecord.baseCall(call)] else { return "" }
        return [v.rx > 0 ? "↓\(v.rx)" : nil, v.tx > 0 ? "↑\(v.tx)" : nil].compactMap { $0 }.joined(separator: " ")
    }

    var qsoList: some View {
        VStack(spacing: 0) {
            Table(filtered, selection: $selection) {
                Group {
                    TableColumn(L("Čas (UTC)")) { (r: QSORecord) in Text(Self.timeLabel(r)).monospacedDigit() }.width(min: 120, ideal: 140)
                    TableColumn(L("Značka")) { (r: QSORecord) in Text(r.call).bold() }.width(min: 80, ideal: 100)
                    TableColumn(L("Pásmo")) { (r: QSORecord) in Text(r.band ?? "") }.width(50)
                    TableColumn("kHz") { (r: QSORecord) in Text(Self.khzLabel(r)) }.width(70)
                    TableColumn(L("Mód")) { (r: QSORecord) in Text(r.mode) }.width(50)
                }
                Group {
                    TableColumn("RST s/r") { (r: QSORecord) in Text(Self.rstLabel(r)) }.width(70)
                    TableColumn("Nr s/r") { (r: QSORecord) in Text(Self.nrLabel(r)) }.width(70)
                    TableColumn(L("Jméno")) { (r: QSORecord) in Text(r.name ?? "") }
                    TableColumn("QTH") { (r: QSORecord) in Text(r.qth ?? "") }
                    TableColumn(L("Země")) { (r: QSORecord) in Text(r.country ?? "") }
                }
                TableColumn("QTC") { (r: QSORecord) in Text(qtcLabel(r.call)).monospacedDigit() }.width(70)
                TableColumn(L("Nahráno")) { (r: QSORecord) in Self.uploadBadges(r) }.width(min: 60, ideal: 70)
            }
            .contextMenu(forSelectionType: QSORecord.ID.self) { ids in
                if let id = ids.first, let r = model.logRecords.first(where: { $0.id == id }) {
                    Button(L("Upravit…")) { editing = r }
                    Button(L("Smazat…"), role: .destructive) { confirmDelete = r }
                }
            } primaryAction: { ids in
                if let id = ids.first { editing = model.logRecords.first { $0.id == id } }
            }
            HStack {
                Text(L("%ld spojení", filtered.count)).foregroundStyle(.secondary)
                Text(model.logStats.byBand.map { "\($0.band) \($0.count)" }.joined(separator: " · "))
                    .foregroundStyle(.secondary).lineLimit(1)
                    .hint(L("Počty spojení podle pásem (v závodě od začátku závodu)"))
                Text((model.logLocation.displayPath as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    .hint(model.logLocation.displayPath)
                Spacer()
                Menu("Log") {
                    Button(L("Nový log…")) { FileActions.newLog(model) }
                    Button(L("Otevřít log…")) { FileActions.openLog(model) }
                    Button(L("Uložit log jako…")) { FileActions.saveLogAs(model) }
                    Button(L("Exportovat ADIF…")) { FileActions.exportADIF(model) }
                }.fixedSize()
                Menu(L("Nahrát")) {
                    ForEach(UploadTarget.allCases, id: \.self) { t in
                        Button(t.title) { runUpload(t) }
                            .disabled(!UploadCoordinator.isEnabled(t, model.settings.upload) || model.uploadsRunning.contains(t))
                    }
                }.fixedSize().hint(L("Nahraje dosud nenahraná spojení (služby se zapínají v Nastavení → Online)"))
                Button(L("Importovat ADIF…")) { FileActions.importADIF(model) }
                Button(L("Exportovat Cabrillo…")) { exportCabrillo(model) }
            }.padding(6).font(.caption)
        }
        .searchable(text: $search, prompt: L("Značka nebo jméno"))
        .sheet(item: $editing) { r in QSOEditor(record: r) { new in Task { await model.updateLog(new) } } }
        .confirmationDialog(L("Smazat spojení?"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            presenting: confirmDelete) { r in
            Button(L("Smazat %@", r.call), role: .destructive) { Task { await model.deleteLog(r.id) } }
        }
        .alert(L("Nahrávání"), isPresented: Binding(get: { uploadResult != nil }, set: { if !$0 { uploadResult = nil } })) {
            Button("OK") { uploadResult = nil }
        } message: { Text(uploadResult ?? "") }
        // after the message about the file handed to TQSL: did TQSL send it? (only then are the QSOs marked)
        .background(EmptyView().alert(L("Odeslali jste spojení v TQSL do LoTW?"),
                                      isPresented: Binding(get: { model.pendingLoTW != nil && uploadResult == nil },
                                                           set: { if !$0 && model.pendingLoTW != nil { Task { await model.confirmLoTW(false) } } })) {
            Button(L("Ano, označit jako nahraná")) { Task { await model.confirmLoTW(true) } }
            Button(L("Zatím ne"), role: .cancel) { Task { await model.confirmLoTW(false) } }
        } message: { Text(model.pendingLoTW?.file.lastPathComponent ?? "") })
        .frame(minWidth: 700, minHeight: 300)
    }

    func runUpload(_ t: UploadTarget) {
        Task { uploadResult = await model.uploadPending(t) }
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
            TextField(L("Značka"), text: Binding(get: { record.call }, set: { record.call = $0.uppercased() }))
            DatePicker(L("Začátek (UTC)"), selection: $record.timeOn)
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            TextField(L("Frekvence (Hz)"), value: $record.frequency, format: .number)
            TextField(L("Mód"), text: $record.mode)
            TextField(L("RST odeslané"), text: text(\.rstSent))
            TextField(L("RST přijaté"), text: text(\.rstRcvd))
            TextField(L("Jméno"), text: text(\.name))
            TextField("QTH", text: text(\.qth))
            TextField(L("Lokátor"), text: text(\.grid))
            TextField(L("Poznámka"), text: text(\.comment))
            HStack {
                Spacer()
                Button(L("Zrušit")) { dismiss() }
                Button(L("Uložit")) { onSave(record); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420)
    }
}

/// QTC series (WAE): overview, expanding the rows, editing and deleting; points summary.
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
                Text(L("Žádné série QTC. QTC se vyměňují ve formátu závodu WAE (Nastavení → Závod)."))
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
                                Text(s.direction == .sent ? L("Odesláno") : L("Přijato")).frame(width: 70, alignment: .leading)
                                Text("QTC \(s.number)/\(s.groupSize)").monospacedDigit().frame(width: 80, alignment: .leading)
                                Text(s.counterpart).bold().frame(width: 100, alignment: .leading)
                                Text(Self.fmt.string(from: s.time)).monospacedDigit()
                                Text(Bands.band(forHz: s.frequency) ?? "").foregroundStyle(.secondary).frame(width: 50)
                                Spacer()
                                Text(L("%ld b.", s.count)).monospacedDigit()
                            }
                        }
                        .contextMenu {
                            Button(L("Upravit…")) { editing = s }
                            Button(L("Smazat…"), role: .destructive) { confirmDelete = s }
                        }
                    }
                }
            }
            HStack {
                let sum = model.qtcSummary
                Text(L("Série: %ld · odesláno %ld QTC · přijato %ld QTC · body za QTC %ld · QSO %ld", sum.seriesCount, sum.sent, sum.received, sum.points, model.logRecords.count))
                    .foregroundStyle(.secondary)
                Spacer()
            }.padding(6).font(.caption)
        }
        .task { await model.refreshQTCSeries() }
        .sheet(item: $editing) { s in QTCSeriesEditor(series: s) { new in Task { await model.updateQTCSeries(new) } } }
        .confirmationDialog(L("Smazat sérii QTC?"), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            presenting: confirmDelete) { s in
            Button(L("Smazat QTC %ld/%ld (%@)", s.number, s.groupSize, s.counterpart), role: .destructive) { Task { await model.deleteQTCSeries(s.id) } }
        }
    }
}

/// Editing a series: the other station, the series number and the rows (one "HHMM CALL NNN" entry per line).
struct QTCSeriesEditor: View {
    @State var series: QTCSeries
    let onSave: (QTCSeries) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var parsed: [QTCLine?] { text.split(separator: "\n", omittingEmptySubsequences: true).map { QTCText.parseLine(String($0)) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(series.direction == .sent ? L("Odeslaná série QTC") : L("Přijatá série QTC")).font(.headline)
            Form {
                TextField(L("Protistanice"), text: $series.counterpart)
                Stepper(L("Číslo série: %ld", series.number), value: $series.number, in: 1...999)
            }
            Text(L("Řádky (HHMM ZNAČKA NNN):")).font(.caption)
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 180)
            if parsed.contains(where: { $0 == nil }) || parsed.count > 10 || parsed.isEmpty {
                Text(L("Každý řádek musí mít tvar „HHMM ZNAČKA NNN“, 1–10 řádků.")).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(L("Zrušit")) { dismiss() }
                Button(L("Uložit")) {
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
