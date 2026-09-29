// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import QSOLog
import SwiftUI

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
        VStack(spacing: 0) {
            Table(filtered, selection: $selection) {
                TableColumn("Čas (UTC)") { r in Text(Self.fmt.string(from: r.timeOn)).monospacedDigit() }.width(min: 120, ideal: 140)
                TableColumn("Značka") { r in Text(r.call).bold() }.width(min: 80, ideal: 100)
                TableColumn("Pásmo") { r in Text(r.band ?? "") }.width(50)
                TableColumn("kHz") { r in Text(r.frequency.map { String(format: "%.1f", $0 / 1000) } ?? "") }.width(70)
                TableColumn("Mód") { r in Text(r.mode) }.width(50)
                TableColumn("RST s/r") { r in Text("\(r.rstSent ?? "")/\(r.rstRcvd ?? "")") }.width(70)
                TableColumn("Jméno") { r in Text(r.name ?? "") }
                TableColumn("QTH") { r in Text(r.qth ?? "") }
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
            DatePicker("Začátek (lokálně)", selection: $record.timeOn)
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
