// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppUI
import Engine
import QSOLog
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
                        .uiFont(.headline).frame(width: 44)
                }
                .hint(L("Přepnout TX/RX (⌘T)"))
                Button("Tune") { Task { await model.tune() } }.fixedSize()
                Button("Stop") { Task { await model.rxNow() } }.fixedSize()
                    .keyboardShortcut(.escape, modifiers: [])
                    .hint(L("Okamžitě RX (Esc)"))
                Text(Self.stateLabel(model.state))
                    .uiFont(.body, weight: .bold, design: .monospaced).lineLimit(1).fixedSize()
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
                FrequencyControl(model: model)
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
                    .uiFont(.caption, weight: .bold, design: .monospaced).lineLimit(1).fixedSize()
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background((model.fig ? Color.orange : Color.secondary).opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                    .hint(L("Stav přijímače LTRS/FIGS"))
                FilterMenu(model: model)
                Spacer(minLength: 4)
                Group {
                    Toggle("XY", isOn: Binding(get: { model.xyEnabled }, set: { v in Task { await model.setXYScope(v) } }))
                        .hint(L("XY scope (křížový indikátor ladění)"))
                    Toggle(L("2. dek."), isOn: Binding(get: { model.settings.decoders.secondEnabled },
                                                       set: { v in Task { await model.setSecondDecoder(v) } }))
                        .hint(L("2. dekodér: stejný signál jiným demodulátorem, text v panelu pod příjmem"))
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

    /// Short status label (long names would push the bar out in a narrow window).
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

/// Receive filters and UOS in a single menu (saves space); the label shows which ones are on.
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

/// Menu of 16 modem parameter profiles (load / save the current one).
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

/// Controls for WAV playback: rewind, pause, seek, stop (MMTTY Play/Pause/Rewind/Seek).
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
                .uiFont(.caption, digits: true).foregroundStyle(.secondary).fixedSize()
            Button { Task { await model.stopWAV() } } label: { Image(systemName: "stop.fill") }
                .hint(L("Zastavit přehrávání WAV"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        .fixedSize()
    }
}

/// The rig frequency in the top bar: clicking it (or the shortcut) opens a kHz entry, with the band menu next to it.
struct FrequencyControl: View {
    @Bindable var model: AppModel
    @State private var shown = false
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var online: Bool { model.rig?.online == true }

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(AppModel.bandPresets, id: \.0) { b in
                    Button("\(b.0) (\(Int(b.1)) kHz)") { Task { await model.setFrequency(kHz: b.1) } }
                }
            } label: {
                Text(Bands.band(forHz: model.rig?.frequency ?? model.qso.frequency) ?? L("Pásmo")).lineLimit(1)
            }
            .fixedSize().controlSize(.small)
            .hint(model.settings.rig.type == .none ? L("Pásmo do logu (bez rigu)") : L("Přeladit rig na RTTY kmitočet pásma"))
            Button { open() } label: {
                Text(model.rig?.frequency.map { String(format: "%.3f kHz", $0 / 1000) } ?? "— kHz")
                    .uiFont(.title3, design: .monospaced)
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(online ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            .hint((online ? L("Rig online") : L("Rig offline")) + " – " + L("kliknutím zadáte frekvenci (%@)", model.settings.binding(for: .enterFrequency).display))
            .popover(isPresented: $shown, arrowEdge: .bottom) { entry }
        }
        .onChange(of: model.showFrequencyEntry) { _, v in if v { model.showFrequencyEntry = false; open() } }
    }

    func open() {
        if let f = model.rig?.frequency, online { text = String(format: "%.3f", f / 1000) } else { text = "" }
        error = nil; shown = true
    }

    var entry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.settings.rig.type == .none ? L("Frekvence do logu (kHz)") : L("Přeladit rig (kHz)")).uiFont(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("kHz", text: $text)
                    .textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 130)
                    .focused($focused)
                    .onSubmit { submit() }
                    .onChange(of: text) { error = nil }
                Text("kHz").foregroundStyle(.secondary)
            }
            if let error { Text(error).uiFont(.caption).foregroundStyle(.red) }
        }
        .padding(10)
        .onAppear { focused = true }
    }

    func submit() {
        let t = text
        Task {
            let r = await model.setFrequency(text: t)
            switch r {
            case .invalid: error = L("Zadejte kHz, 100 až 500 000")
            case .rejectedTX: error = L("Během vysílání se rig nepřelaďuje")
            case .notRunning: error = L("Engine neběží – rig nelze přeladit")
            case .failed: error = L("Rig frekvenci nepřijal")
            case .rig, .manual: shown = false
            }
        }
    }
}
