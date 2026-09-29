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
                Text(Self.stateLabel(model.state))
                    .font(.system(.body, design: .monospaced).bold()).lineLimit(1).fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(stateColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                if model.wavPlaying {
                    Button("▶ WAV ■") { Task { await model.stopWAV() } }.help("Přehrává se WAV – kliknutím zastavit")
                }
                Picker("Demod", selection: model.choiceBinding("demodType")) {
                    ForEach(["iir", "fir", "pll", "fft"], id: \.self) { Text($0.uppercased()).tag($0) }
                }.labelsHidden().fixedSize().help("Demodulátor")
                Button("HAM") { Task { await model.hamShift() } }.fixedSize().help("Shift 170 Hz")
                ProfileMenu(model: model)
                Spacer()
                Text(model.rig?.frequency.map { String(format: "%.3f kHz", $0 / 1000) } ?? "— kHz")
                    .font(.system(.title3, design: .monospaced))
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(model.rig?.online == true ? .primary : .secondary)
                    .help(model.rig?.online == true ? "Rig online" : "Rig offline")
                SignalMeter(level: model.signalLevel, open: model.squelchOpen).frame(width: 80, height: 12)
            }
            HStack(spacing: 6) {
                Picker("Baud", selection: baudBinding) {
                    ForEach([45.45, 50, 75, 100, 110], id: \.self) { Text(String(format: "%g", $0)).tag($0) }
                }.fixedSize()
                Picker("Shift", selection: model.doubleBinding("shift")) {
                    ForEach([170.0, 200, 425, 850], id: \.self) { Text(String(format: "%g", $0)).tag($0) }
                }.fixedSize()
                Text(model.fig ? "FIGS" : "LTRS")
                    .font(.caption.monospaced().bold()).lineLimit(1).fixedSize()
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background((model.fig ? Color.orange : Color.secondary).opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                    .help("Stav přijímače LTRS/FIGS")
                FilterMenu(model: model)
                Spacer(minLength: 4)
                Group {
                    Toggle("XY", isOn: Binding(get: { model.xyEnabled }, set: { v in Task { await model.setXYScope(v) } }))
                        .help("XY scope (křížový indikátor ladění)")
                    Toggle("AFC", isOn: model.boolBinding("afc"))
                    Toggle("NET", isOn: model.boolBinding("net"))
                    Toggle("REV", isOn: model.boolBinding("reverse"))
                    Toggle("ATC", isOn: model.boolBinding("atc"))
                    Toggle("SQ", isOn: model.boolBinding("squelch"))
                }
                .toggleStyle(.button).fixedSize()
            }
            .controlSize(.small)
        }
        .padding(8)
    }

    /// Krátký štítek stavu (dlouhé názvy by v úzkém okně vytlačily lištu).
    static func stateLabel(_ s: EngineState) -> String {
        switch s {
        case .stopped: return "STOP"
        case .rx: return "RX"
        case .keying: return "PTT…"
        case .pttOn: return "PTT"
        case .tx: return "TX"
        case .drain: return "TX…"
        case .pttOff: return "PTT↓"
        }
    }

    var baudBinding: Binding<Double> {
        Binding(get: { if case .double(let d)? = model.param("baud") { return d }; return 45.45 },
                set: { v in Task { await model.setParam("baud", .double(v)) } })
    }
}

/// Filtry příjmu a UOS v jedné nabídce (šetří místo); popisek ukazuje zapnuté.
struct FilterMenu: View {
    @Bindable var model: AppModel
    var active: String {
        var a: [String] = []
        if model.param("bpf") == .bool(true) { a.append("BPF") }
        if model.param("lms") == .bool(true) { a.append(model.param("lmsType") == .string("lms") ? "LMS" : "NOT") }
        if model.param("aa6yq") == .bool(true) { a.append("AA6YQ") }
        if model.param("uos") == .bool(true) { a.append("UOS") }
        return a.isEmpty ? "Filtry" : a.joined(separator: "+")
    }
    var body: some View {
        Menu {
            Toggle("BPF – vstupní pásmová propust", isOn: model.boolBinding("bpf"))
            Toggle("Zářez (notch) / LMS", isOn: model.boolBinding("lms"))
            Picker("Typ", selection: model.choiceBinding("lmsType")) {
                Text("Notch (zářez)").tag("notch"); Text("LMS").tag("lms")
            }
            Toggle("Dva zářezy", isOn: model.boolBinding("twoNotch"))
            Toggle("AA6YQ (BPF mark–space + zádrž)", isOn: model.boolBinding("aa6yq"))
            Divider()
            Toggle("UOS – unshift on space", isOn: model.boolBinding("uos"))
        } label: {
            Text(active).lineLimit(1)
        }
        .fixedSize()
        .help("Filtry příjmu (pravé tlačítko ve spektru = zářez) a UOS")
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
