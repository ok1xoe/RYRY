// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import Engine
import SwiftUI

struct TopBar: View {
    @Bindable var model: AppModel

    var stateColor: Color {
        switch model.state {
        case .rx: return .green
        case .stopped: return .gray
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button { Task { await model.toggleTx() } } label: {
                    Text(model.state == .rx || model.state == .stopped ? "TX" : "RX")
                        .font(.headline).frame(width: 44)
                }
                .keyboardShortcut("t", modifiers: .command)
                .help("Přepnout TX/RX (⌘T)")
                Button("Tune") { Task { await model.tune() } }
                Button("Stop") { Task { await model.rxNow() } }
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Okamžitě RX (Esc)")
                Text(model.state.rawValue.uppercased())
                    .font(.system(.body, design: .monospaced).bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(stateColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                Spacer()
                Text(model.rig?.frequency.map { String(format: "%.3f kHz", $0 / 1000) } ?? "— kHz")
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(model.rig?.online == true ? .primary : .secondary)
                    .help(model.rig?.online == true ? "Rig online" : "Rig offline")
                SignalMeter(level: model.signalLevel, open: model.squelchOpen).frame(width: 80, height: 12)
            }
            HStack(spacing: 8) {
                Picker("Baud", selection: baudBinding) {
                    ForEach([45.45, 50, 75, 100, 110], id: \.self) { Text(String(format: "%g", $0)).tag($0) }
                }.fixedSize()
                Picker("Shift", selection: model.doubleBinding("shift")) {
                    ForEach([170.0, 200, 425, 850], id: \.self) { Text(String(format: "%g", $0)).tag($0) }
                }.fixedSize()
                Picker("Demod", selection: model.choiceBinding("demodType")) {
                    ForEach(["iir", "fir", "pll", "fft"], id: \.self) { Text($0.uppercased()).tag($0) }
                }.fixedSize()
                Spacer()
                Toggle("AFC", isOn: model.boolBinding("afc")).toggleStyle(.button)
                Toggle("NET", isOn: model.boolBinding("net")).toggleStyle(.button)
                Toggle("REV", isOn: model.boolBinding("reverse")).toggleStyle(.button)
                Toggle("ATC", isOn: model.boolBinding("atc")).toggleStyle(.button)
                Toggle("SQ", isOn: model.boolBinding("squelch")).toggleStyle(.button)
            }
        }
        .padding(8)
    }

    var baudBinding: Binding<Double> {
        Binding(get: { if case .double(let d)? = model.param("baud") { return d }; return 45.45 },
                set: { v in Task { await model.setParam("baud", .double(v)) } })
    }
}

struct SignalMeter: View {
    let level: Double
    let open: Bool
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(.quaternary)
                RoundedRectangle(cornerRadius: 2).fill(open ? Color.green : Color.gray)
                    .frame(width: g.size.width * min(1, max(0, log10(max(level, 1)) / 4)))
            }
        }
        .help(String(format: "Signál %.0f", level))
    }
}
