// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import QSOLog
import SwiftUI

struct QSOPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QSO").font(.headline)
            Form {
                TextField("Call", text: model.qsoBinding("call")).font(.title3.monospaced())
                TextField("Name", text: model.qsoBinding("name"))
                TextField("QTH", text: model.qsoBinding("qth"))
                TextField("Locator", text: model.qsoBinding("locator"))
                HStack {
                    TextField("RST s", text: model.qsoBinding("rstSent"))
                    TextField("RST r", text: model.qsoBinding("rstRcvd"))
                }
                HStack {
                    TextField("Nr s", text: model.qsoBinding("serialSent"))
                    TextField("Nr r", text: model.qsoBinding("serialRcvd"))
                }
                TextField("Exch r", text: model.qsoBinding("exchangeRcvd"))
                TextField("Notes", text: model.qsoBinding("notes"))
            }
            HStack {
                Button("Log") { Task { await model.logQSO() } }.keyboardShortcut("l", modifiers: .command)
                Button("Clear") { Task { await model.clearQSO() } }
            }
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
