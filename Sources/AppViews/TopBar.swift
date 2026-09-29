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
                .help("Přepnout TX/RX (⌘T)")
                Button("Tune") { Task { await model.tune() } }.fixedSize()
                Button("Stop") { Task { await model.rxNow() } }.fixedSize()
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Okamžitě RX (Esc)")
                Text(model.state.rawValue.uppercased())
                    .font(.system(.body, design: .monospaced).bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(stateColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                Picker("Demod", selection: model.choiceBinding("demodType")) {
                    ForEach(["iir", "fir", "pll", "fft"], id: \.self) { Text($0.uppercased()).tag($0) }
                }.labelsHidden().fixedSize().help("Demodulátor")
                Button("HAM") { Task { await model.hamShift() } }.help("Shift 170 Hz")
                ProfileMenu(model: model)
                Spacer()
                Text(model.rig?.frequency.map { String(format: "%.3f kHz", $0 / 1000) } ?? "— kHz")
                    .font(.system(.title3, design: .monospaced))
                    .lineLimit(1).fixedSize()
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
                Text(model.fig ? "FIGS" : "LTRS")
                    .font(.caption.monospaced().bold()).padding(.horizontal, 4).padding(.vertical, 2)
                    .background((model.fig ? Color.orange : Color.secondary).opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                    .help("Stav přijímače LTRS/FIGS")
                Toggle("UOS", isOn: model.boolBinding("uos")).toggleStyle(.button)
                    .help("Unshift on space – po mezeře zpět na písmena")
                Spacer()
                Toggle("BPF", isOn: model.boolBinding("bpf")).toggleStyle(.button).help("Vstupní pásmová propust")
                Toggle(model.param("lmsType") == .string("lms") ? "LMS" : "NOT", isOn: model.boolBinding("lms"))
                    .toggleStyle(.button)
                    .help("Zářez (notch) nebo LMS filtr · pravé tlačítko ve spektru = zářez · kontextová nabídka = typ")
                    .contextMenu {
                        Button("Notch (zářez)") { Task { await model.setParam("lmsType", .string("notch")) } }
                        Button("LMS") { Task { await model.setParam("lmsType", .string("lms")) } }
                        Toggle("Dva zářezy", isOn: model.boolBinding("twoNotch"))
                    }
                Toggle("AA6YQ", isOn: model.boolBinding("aa6yq")).toggleStyle(.button)
                    .help("Filtr AA6YQ (BPF mark–space + zádrž mezi nimi)")
                Toggle("XY", isOn: Binding(get: { model.xyEnabled }, set: { v in Task { await model.setXYScope(v) } }))
                    .toggleStyle(.button).help("XY scope (křížový indikátor ladění)")
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

/// Nabídka 16 profilů parametrů modemu (načíst / uložit aktuální).
struct ProfileMenu: View {
    @Bindable var model: AppModel
    @State private var saveSlot: Int?
    @State private var name = ""

    var body: some View {
        Menu("Profily") {
            Section("Načíst") {
                ForEach(0..<16, id: \.self) { i in
                    let n = i < model.profileNames.count ? model.profileNames[i] : nil
                    Button("\(i + 1): \(n ?? "—")") { Task { await model.loadProfile(i) } }.disabled(n == nil)
                }
            }
            Section("Uložit aktuální do") {
                ForEach(0..<16, id: \.self) { i in
                    let n = i < model.profileNames.count ? model.profileNames[i] : nil
                    Button("\(i + 1): \(n ?? "prázdný")") { name = n ?? ""; saveSlot = i }
                }
            }
        }
        .fixedSize()
        .alert("Název profilu", isPresented: Binding(get: { saveSlot != nil }, set: { if !$0 { saveSlot = nil } })) {
            TextField("Název", text: $name)
            Button("Uložit") { if let s = saveSlot { let n = name; Task { await model.saveProfile(s, name: n.isEmpty ? "Profil \(s + 1)" : n) } }; saveSlot = nil }
            Button("Zrušit", role: .cancel) { saveSlot = nil }
        }
    }
}
