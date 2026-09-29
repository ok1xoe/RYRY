// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import AudioIO
import Keying
import ModemKit
import Settings
import SwiftUI

public struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var draft = AppSettings()
    @State private var loaded = false
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            TabView {
                StationTab(s: $draft).tabItem { Text("Stanice") }
                AudioTab(s: $draft).tabItem { Text("Zvuk") }
                PTTTab(s: $draft).tabItem { Text("PTT / FSK") }
                RigTab(s: $draft).tabItem { Text("Rig") }
                ModemTab(model: model).tabItem { Text("Modem") }
                APITab(s: $draft).tabItem { Text("API a log") }
            }
            .padding()
            HStack {
                Text("Změny se projeví po Použít (restart zvuku, rigu a API).").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Vrátit") { draft = model.settings }
                Button("Použít") { let d = draft; Task { await model.applySettings(d) } }.keyboardShortcut(.defaultAction)
            }.padding([.horizontal, .bottom])
        }
        .frame(width: 620, height: 480)
        .onAppear { if !loaded { draft = model.settings; loaded = true } }
    }
}

struct StationTab: View {
    @Binding var s: AppSettings
    var body: some View {
        Form {
            TextField("Značka", text: $s.station.call)
            TextField("Lokátor", text: $s.station.locator)
            TextField("Jméno", text: $s.station.name)
            TextField("QTH", text: $s.station.qth)
        }
    }
}

struct AudioTab: View {
    @Binding var s: AppSettings
    @State private var devices: [AudioDevice] = []
    var body: some View {
        Form {
            Picker("Vstup (RX)", selection: $s.audio.inputUID) {
                Text("Výchozí").tag(String?.none)
                ForEach(devices.filter { $0.inputChannels > 0 }, id: \.uid) { Text($0.name).tag(String?.some($0.uid)) }
            }
            Picker("Kanál vstupu", selection: $s.audio.inputChannel) {
                Text("Levý").tag(AudioChannel.left); Text("Pravý").tag(AudioChannel.right); Text("Mono").tag(AudioChannel.mono)
            }
            Picker("Výstup (TX)", selection: $s.audio.outputUID) {
                Text("Výchozí").tag(String?.none)
                ForEach(devices.filter { $0.outputChannels > 0 }, id: \.uid) { Text($0.name).tag(String?.some($0.uid)) }
            }
            Picker("Kanál výstupu", selection: $s.audio.outputChannel) {
                Text("Levý").tag(AudioChannel.left); Text("Pravý").tag(AudioChannel.right); Text("Oba").tag(AudioChannel.mono)
            }
            Slider(value: $s.audio.outputGain, in: 0...1) { Text("Hlasitost TX") }
        }
        .onAppear { devices = AudioDevices.all() }
    }
}

struct PTTTab: View {
    @Binding var s: AppSettings
    @State private var ports: [String] = []
    var body: some View {
        Form {
            Section("PTT") {
                Picker("Metoda", selection: $s.ptt.method) {
                    Text("Žádná (VOX)").tag(PTTMethod.none); Text("CAT (rig)").tag(PTTMethod.cat)
                    Text("RTS").tag(PTTMethod.rts); Text("DTR").tag(PTTMethod.dtr); Text("RTS + DTR").tag(PTTMethod.rtsDtr)
                }
                Picker("Port", selection: $s.ptt.port) {
                    Text("—").tag(String?.none)
                    ForEach(ports, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Toggle("Invertovat", isOn: $s.ptt.invert)
                Stepper("Zpoždění TX: \(s.ptt.txDelayMs) ms", value: $s.ptt.txDelayMs, in: 0...2000, step: 10)
                Stepper("Doběh PTT: \(s.ptt.pttTailMs) ms", value: $s.ptt.pttTailMs, in: 0...2000, step: 10)
                Stepper("PTT časovač: \(s.ptt.pttTimeoutS) s", value: $s.ptt.pttTimeoutS, in: 10...3600, step: 10)
            }
            Section("Výstup") {
                Picker("Režim", selection: $s.fsk.output) {
                    Text("AFSK (zvuk)").tag(FSKOutputKind.afsk)
                    Text("FSK – UART TxD (FTDI)").tag(FSKOutputKind.fskUART)
                    Text("FSK – softwarové časování").tag(FSKOutputKind.fskSoft)
                }
                Picker("FSK port", selection: $s.fsk.port) {
                    Text("—").tag(String?.none)
                    ForEach(ports, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker("Linka (soft)", selection: $s.fsk.line) {
                    Text("TxD (break)").tag(FSKLine.txdBreak); Text("DTR").tag(FSKLine.dtr); Text("RTS").tag(FSKLine.rts)
                }
                Toggle("Invertovat FSK", isOn: $s.fsk.invert)
                Toggle("Zvuk i při FSK", isOn: $s.fsk.audioDuringFSK)
            }
        }
        .onAppear { ports = POSIXSerialPort.availablePorts() }
    }
}

struct RigTab: View {
    @Binding var s: AppSettings
    var body: some View {
        Form {
            Picker("Ovládání rigu", selection: $s.rig.type) {
                Text("Žádné").tag(RigType.none); Text("hamlib rigctld").tag(RigType.hamlib); Text("flrig").tag(RigType.flrig)
            }
            TextField("Host", text: $s.rig.host)
            TextField("Port (prázdné = výchozí)", value: $s.rig.port, format: .number.grouping(.never))
            Text("hamlib: spusťte např. `rigctld -m <model> -r /dev/cu.X -s <baud>`; flrig: spuštěný flrig.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct APITab: View {
    @Binding var s: AppSettings
    var body: some View {
        Form {
            Section("API") {
                Toggle("fldigi XML-RPC", isOn: $s.api.fldigiEnabled)
                TextField("Port", value: $s.api.fldigiPort, format: .number.grouping(.never))
                Toggle("JSON-RPC (WebSocket)", isOn: $s.api.jsonRPCEnabled)
                TextField("Port", value: $s.api.jsonRPCPort, format: .number.grouping(.never))
                Toggle("Povolit přístup ze sítě (bez autentizace!)", isOn: $s.api.allowRemote)
            }
            Section("Log") {
                HStack {
                    TextField("Adresář", text: $s.log.directory)
                    Button("Vybrat…") {
                        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
                        if p.runModal() == .OK, let u = p.url { s.log.directory = u.path }
                    }
                }
            }
        }
    }
}

/// Parametry modemu generované z popisu (mění se hned, bez restartu).
struct ModemTab: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            ForEach(model.descriptors, id: \.id) { d in
                switch d.kind {
                case .bool: Toggle(d.label, isOn: model.boolBinding(d.id))
                case .choice(let opts):
                    Picker(d.label, selection: model.choiceBinding(d.id)) { ForEach(opts, id: \.self) { Text($0).tag($0) } }
                case .double(let r, let unit):
                    HStack {
                        Text(d.label)
                        Spacer()
                        TextField("", value: model.doubleBinding(d.id), format: .number).frame(width: 90)
                        Text(unit ?? "").foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                    }.help("\(r.lowerBound)…\(r.upperBound)")
                case .int(let r):
                    Stepper("\(d.label): \(intValue(d.id))", value: intBinding(d.id), in: r)
                }
            }
        }
    }
    func intValue(_ id: String) -> Int { if case .int(let i)? = model.param(id) { return i }; return 0 }
    func intBinding(_ id: String) -> Binding<Int> {
        Binding(get: { intValue(id) }, set: { v in Task { await model.setParam(id, .int(v)) } })
    }
}
