// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import Engine
import SwiftUI
import Localization

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
            HStack(spacing: 6) {
                Button { Task { await model.toggleTx() } } label: {
                    Text(model.state == .rx || model.state == .stopped ? "TX" : "RX")
                        .font(.headline).frame(width: 44)
                }
                .hint(L("Přepnout TX/RX (⌘T)"))
                Button("Tune") { Task { await model.tune() } }.fixedSize()
                Button("Stop") { Task { await model.rxNow() } }.fixedSize()
                    .keyboardShortcut(.escape, modifiers: [])
                    .hint(L("Okamžitě RX (Esc)"))
                Text(Self.stateLabel(model.state))
                    .font(.system(.body, design: .monospaced).bold()).lineLimit(1).fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(stateColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                if model.wavPlaying { WAVControls(model: model) }
                if model.recordingURL != nil {
                    Button { Task { await model.stopRecordingWAV() } } label: {
                        Label(String(format: "REC %d:%02d", Int(model.recordingSeconds) / 60, Int(model.recordingSeconds) % 60),
                              systemImage: "record.circle").foregroundStyle(.red).monospacedDigit()
                    }
                    .fixedSize().hint(L("Nahrává se příjem do WAV – kliknutím zastavit"))
                }
                Picker("Demod", selection: model.choiceBinding("demodType")) {
                    ForEach(["iir", "fir", "pll", "fft"], id: \.self) { Text($0.uppercased()).tag($0) }
                }.labelsHidden().fixedSize().hint(L("Demodulátor"))
                Button("HAM") { Task { await model.hamShift() } }.fixedSize().hint("Shift 170 Hz")
                ProfileMenu(model: model)
                Spacer()
                Text(model.rig?.frequency.map { String(format: "%.3f kHz", $0 / 1000) } ?? "— kHz")
                    .font(.system(.title3, design: .monospaced))
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(model.rig?.online == true ? .primary : .secondary)
                    .hint(model.rig?.online == true ? L("Rig online") : L("Rig offline"))
                SignalMeter(level: model.signalLevel, open: model.squelchOpen).frame(width: 56, height: 12)
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
                    .hint(L("Stav přijímače LTRS/FIGS"))
                FilterMenu(model: model)
                Spacer(minLength: 4)
                Group {
                    Toggle("XY", isOn: Binding(get: { model.xyEnabled }, set: { v in Task { await model.setXYScope(v) } }))
                        .hint(L("XY scope (křížový indikátor ladění)"))
                    Toggle("AFC", isOn: model.boolBinding("afc"))
                        .hint(L("AFC · kontextová nabídka: vazba na squelch, omezení rozsahu"))
                        .contextMenu {
                            Toggle(L("Jen při otevřeném squelchi"), isOn: model.boolBinding("afcGate"))
                            Picker(L("Max. odchylka od naladění"), selection: model.doubleBinding("afcMaxDev")) {
                                Text(L("bez omezení")).tag(0.0)
                                ForEach([25.0, 50, 100, 200], id: \.self) { Text("± \(Int($0)) Hz").tag($0) }
                            }
                        }
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
        return a.isEmpty ? L("Filtry") : a.joined(separator: "+")
    }
    var body: some View {
        Menu {
            Toggle(L("BPF – vstupní pásmová propust"), isOn: model.boolBinding("bpf"))
            Toggle(L("Zářez (notch) / LMS"), isOn: model.boolBinding("lms"))
            Picker(L("Typ"), selection: model.choiceBinding("lmsType")) {
                Text(L("Notch (zářez)")).tag("notch"); Text("LMS").tag("lms")
            }
            Toggle(L("Dva zářezy"), isOn: model.boolBinding("twoNotch"))
            Toggle(L("AA6YQ (BPF mark–space + zádrž)"), isOn: model.boolBinding("aa6yq"))
            Divider()
            Toggle(L("UOS – unshift on space"), isOn: model.boolBinding("uos"))
        } label: {
            Text(active).lineLimit(1)
        }
        .fixedSize()
        .hint(L("Filtry příjmu (pravé tlačítko ve spektru = zářez) a UOS"))
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
        .hint(L("Signál %.0f", level))
    }
}

/// Nabídka 16 profilů parametrů modemu (načíst / uložit aktuální).
struct ProfileMenu: View {
    @Bindable var model: AppModel
    @State private var saveSlot: Int?
    @State private var name = ""

    var body: some View {
        Menu(L("Profily")) {
            Section(L("Načíst")) {
                ForEach(0..<16, id: \.self) { i in
                    let n = i < model.profileNames.count ? model.profileNames[i] : nil
                    Button("\(i + 1): \(n ?? "—")") { Task { await model.loadProfile(i) } }.disabled(n == nil)
                }
            }
            Section(L("Uložit aktuální do")) {
                ForEach(0..<16, id: \.self) { i in
                    let n = i < model.profileNames.count ? model.profileNames[i] : nil
                    Button("\(i + 1): \(n ?? L("prázdný"))") { name = n ?? ""; saveSlot = i }
                }
            }
        }
        .fixedSize()
        .alert(L("Název profilu"), isPresented: Binding(get: { saveSlot != nil }, set: { if !$0 { saveSlot = nil } })) {
            TextField(L("Název"), text: $name)
            Button(L("Uložit")) { if let s = saveSlot { let n = name; Task { await model.saveProfile(s, name: n.isEmpty ? L("Profil %ld", s + 1) : n) } }; saveSlot = nil }
            Button(L("Zrušit"), role: .cancel) { saveSlot = nil }
        }
    }
}

/// Ovládání přehrávaného WAV: převinutí, pauza, posun, zastavení (MMTTY Play/Pause/Rewind/Seek).
struct WAVControls: View {
    @Bindable var model: AppModel
    @State private var dragging: Double?

    static func time(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }

    var body: some View {
        HStack(spacing: 4) {
            Button { Task { await model.seekWAV(0) } } label: { Image(systemName: "backward.end.fill") }
                .hint(L("Převinout na začátek"))
            Button { Task { await model.pauseWAV(!model.wavPaused) } } label: {
                Image(systemName: model.wavPaused ? "play.fill" : "pause.fill")
            }.hint(model.wavPaused ? L("Pokračovat v přehrávání") : L("Pozastavit přehrávání"))
            Slider(value: Binding(get: { dragging ?? model.wavProgress }, set: { dragging = $0 }), in: 0...1) { editing in
                if !editing, let f = dragging { Task { await model.seekWAV(f); dragging = nil } }
            }
            .frame(width: 110).controlSize(.small)
            .hint(L("Posun v přehrávaném souboru"))
            Text("\(Self.time((dragging ?? model.wavProgress) * model.wavDuration))/\(Self.time(model.wavDuration))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
            Button { Task { await model.stopWAV() } } label: { Image(systemName: "stop.fill") }
                .hint(L("Zastavit přehrávání WAV"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        .fixedSize()
    }
}
