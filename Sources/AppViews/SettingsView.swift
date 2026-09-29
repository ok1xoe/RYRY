// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import AudioIO
import Keying
import Localization
import ModemKit
import Settings
import RigControl
import AppCore
import SwiftUI

public struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var draft = AppSettings()
    @State private var baseline = AppSettings()       // stav, ze kterého koncept vyšel
    @State private var loaded = false
    /// Vybraná záložka (spouštěcí parametr `-settingsTab N` pro snímky obrazovky).
    @State private var tab = UserDefaults.standard.integer(forKey: "settingsTab")
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                StationTab(s: $draft).tabItem { Label(L("Stanice"), systemImage: "person.crop.circle") }.tag(0)
                AudioTab(s: $draft, model: model).tabItem { Label(L("Zvuk"), systemImage: "waveform") }.tag(1)
                PTTTab(s: $draft).tabItem { Label("PTT / FSK", systemImage: "cable.connector") }.tag(2)
                RigTab(s: $draft).tabItem { Label("Rig", systemImage: "antenna.radiowaves.left.and.right") }.tag(3)
                ModemTab(model: model, s: $draft).tabItem { Label("Modem", systemImage: "slider.horizontal.3") }.tag(4)
                ContestTab(s: $draft).tabItem { Label(L("Závod"), systemImage: "trophy") }.tag(5)
                DisplayTab(s: $draft).tabItem { Label(L("Zobrazení"), systemImage: "paintpalette") }.tag(6)
                APITab(s: $draft).tabItem { Label(L("API a log"), systemImage: "network") }.tag(7)
                KeysTab(s: $draft).tabItem { Label(L("Klávesy"), systemImage: "keyboard") }.tag(8)
                DecodersTab(s: $draft).tabItem { Label(L("Dekodéry"), systemImage: "square.stack.3d.down.right") }.tag(9)
            }
            Divider()
            HStack {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(L("Změny se projeví po Použít (restart zvuku, rigu a API). Parametry modemu platí hned."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Vrátit")) { draft = model.settings; baseline = draft }
                Button(L("Použít")) {
                    let d = draft, b = baseline
                    Task { await model.applySettings(d, baseline: b); draft = model.settings; baseline = draft }
                }.keyboardShortcut(.defaultAction)
            }.padding(12)
        }
        .frame(width: 720, height: 640)
        .onAppear { if !loaded { draft = model.settings; baseline = draft; loaded = true } }
        .onDisappear { loaded = false }                  // příště načíst aktuální stav
    }
}

/// Řádek s číslem, jednotkou a krokovačem (hodnota vidět v poli, ne v popisku).
struct NumberRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var unit = ""
    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("", value: $value, format: .number.grouping(.never)).multilineTextAlignment(.trailing).frame(width: 70)
                Text(unit).foregroundStyle(.secondary).frame(minWidth: 18, alignment: .leading)
                Stepper("", value: $value, in: range, step: step).labelsHidden()
            }
        }
    }
}

struct StationTab: View {
    @Binding var s: AppSettings
    var body: some View {
        Form {
            Section {
                TextField(L("Značka"), text: $s.station.call, prompt: Text("OK1ABC"))
                TextField(L("Lokátor"), text: $s.station.locator, prompt: Text("JO70FB"))
                TextField(L("Jméno"), text: $s.station.name, prompt: Text("Tomáš"))
                TextField("QTH", text: $s.station.qth, prompt: Text("Praha"))
            } header: { Text(L("Moje stanice")) } footer: {
                Text(L("Značka se posílá v makrech (%m) a podle ní se určuje zóna a kontinent (DXCC)."))
            }
        }
        .formStyle(.grouped)
    }
}

struct AudioTab: View {
    @Binding var s: AppSettings
    @Bindable var model: AppModel
    @State private var devices: [AudioDevice] = []
    @State private var measuring = false
    @State private var result = ""
    var body: some View {
        Form {
            Section(L("Příjem")) {
                Picker(L("Vstup"), selection: $s.audio.inputUID) {
                    Text(L("Výchozí")).tag(String?.none)
                    ForEach(devices.filter { $0.inputChannels > 0 }, id: \.uid) { Text($0.name).tag(String?.some($0.uid)) }
                }
                Picker(L("Kanál"), selection: $s.audio.inputChannel) {
                    Text(L("Levý")).tag(AudioChannel.left); Text(L("Pravý")).tag(AudioChannel.right); Text("Mono").tag(AudioChannel.mono)
                }
            }
            Section(L("Vysílání")) {
                Picker(L("Výstup"), selection: $s.audio.outputUID) {
                    Text(L("Výchozí")).tag(String?.none)
                    ForEach(devices.filter { $0.outputChannels > 0 }, id: \.uid) { Text($0.name).tag(String?.some($0.uid)) }
                }
                Picker(L("Kanál"), selection: $s.audio.outputChannel) {
                    Text(L("Levý")).tag(AudioChannel.left); Text(L("Pravý")).tag(AudioChannel.right); Text(L("Oba")).tag(AudioChannel.mono)
                }
                LabeledContent(L("Hlasitost")) {
                    HStack {
                        Slider(value: $s.audio.outputGain, in: 0...1)
                        Text("\(Int(s.audio.outputGain * 100)) %").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section {
                LabeledContent(L("Korekce RX")) {
                    HStack(spacing: 4) {
                        TextField("", value: $s.clock.rxPPM, format: .number.precision(.fractionLength(0...2)))
                            .multilineTextAlignment(.trailing).frame(width: 90)
                        Text("ppm").foregroundStyle(.secondary)
                    }
                }
                LabeledContent(L("Korekce TX")) {
                    HStack(spacing: 4) {
                        TextField("", value: $s.clock.txPPM, format: .number.precision(.fractionLength(0...2)))
                            .multilineTextAlignment(.trailing).frame(width: 90)
                        Text("ppm").foregroundStyle(.secondary)
                    }
                }
                LabeledContent {
                    Button(measuring ? L("Měřím…") : L("Změřit (30 s)")) {
                        measuring = true; result = ""
                        Task {
                            let r = await model.measureClock(seconds: 30, inputUID: s.audio.inputUID, outputUID: s.audio.outputUID)
                            measuring = false
                            if let rx = r.rx { s.clock.rxPPM = (rx * 10).rounded() / 10 }
                            if let tx = r.tx { s.clock.txPPM = (tx * 10).rounded() / 10 }
                            result = r.rx == nil && r.tx == nil ? L("Zařízení neběží – spusťte příjem.")
                                : L("RX %@ ppm, TX %@ ppm – potvrďte Použít.",
                                         r.rx.map { String(format: "%.1f", $0) } ?? "—", r.tx.map { String(format: "%.1f", $0) } ?? "—")
                        }
                    }.disabled(measuring)
                } label: { Text(result.isEmpty ? L("Měření") : result).foregroundStyle(result.isEmpty ? .primary : .secondary) }
            } header: { Text(L("Kalibrace hodin zvukové karty")) } footer: {
                Text(L("Core Audio měří skutečnou vzorkovací frekvenci zařízení proti hodinám systému (NTP). Rozsah ± 20 000 ppm."))
            }
        }
        .formStyle(.grouped)
        .onAppear { devices = AudioDevices.all() }
    }
}

struct PTTTab: View {
    @Binding var s: AppSettings
    @State private var ports: [String] = []
    var body: some View {
        Form {
            Section {
                Picker(L("Metoda"), selection: $s.ptt.method) {
                    Text(L("Žádná (VOX)")).tag(PTTMethod.none); Text("CAT (rig)").tag(PTTMethod.cat)
                    Text("RTS").tag(PTTMethod.rts); Text("DTR").tag(PTTMethod.dtr); Text("RTS + DTR").tag(PTTMethod.rtsDtr)
                }
                Picker(L("Sériový port"), selection: $s.ptt.port) {
                    Text("—").tag(String?.none)
                    ForEach(ports, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .disabled(![.rts, .dtr, .rtsDtr].contains(s.ptt.method))
                Toggle(L("Invertovat"), isOn: $s.ptt.invert)
            } header: { Text("PTT") }
            Section {
                NumberRow(title: L("Zpoždění TX"), value: $s.ptt.txDelayMs, range: 0...2000, step: 10, unit: "ms")
                NumberRow(title: L("Doběh PTT"), value: $s.ptt.pttTailMs, range: 0...2000, step: 10, unit: "ms")
                NumberRow(title: L("Bezpečnostní časovač"), value: $s.ptt.pttTimeoutS, range: 10...3600, step: 10, unit: "s")
            } header: { Text(L("Časování")) } footer: {
                Text(L("Časovač vypne vysílání, pokud trvá déle (ochrana proti zaseknutému PTT)."))
            }
            Section {
                Picker(L("Režim"), selection: $s.fsk.output) {
                    Text(L("AFSK (zvuk)")).tag(FSKOutputKind.afsk)
                    Text(L("FSK – UART TxD (FTDI)")).tag(FSKOutputKind.fskUART)
                    Text(L("FSK – softwarové časování")).tag(FSKOutputKind.fskSoft)
                }
                Group {
                    Picker(L("Port FSK"), selection: $s.fsk.port) {
                        Text("—").tag(String?.none)
                        ForEach(ports, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    Picker(L("Linka"), selection: $s.fsk.line) {
                        Text("TxD (break)").tag(FSKLine.txdBreak); Text("DTR").tag(FSKLine.dtr); Text("RTS").tag(FSKLine.rts)
                    }
                    .disabled(s.fsk.output != .fskSoft)
                    Toggle(L("Invertovat FSK"), isOn: $s.fsk.invert)
                    Toggle(L("Zvuk i při FSK"), isOn: $s.fsk.audioDuringFSK)
                }
                .disabled(s.fsk.output == .afsk)
            } header: { Text(L("Klíčování")) } footer: {
                Text(L("AFSK = RTTY zvukem (rádio v SSB/DATA). FSK = klíčování sériovou linkou (rádio v režimu FSK/RTTY)."))
            }
        }
        .formStyle(.grouped)
        .onAppear { ports = POSIXSerialPort.availablePorts() }
    }
}

struct RigTab: View {
    @Binding var s: AppSettings
    @State private var ports: [String] = POSIXSerialPort.availablePorts()
    @State private var models: [HamlibModel] = []
    @State private var rigctld: String? = ManagedHamlibRig.findRigctld()
    @State private var testResult: String?
    @State private var testing = false

    var usesSerial: Bool { s.rig.type == .cat || s.rig.type == .hamlibManaged }

    var body: some View {
        Form {
            Section {
                Picker(L("Ovládání"), selection: $s.rig.type) {
                    Text(L("Žádné")).tag(RigType.none)
                    Text(L("CAT přes USB (vestavěný)")).tag(RigType.cat)
                    Text(L("hamlib – spustit automaticky")).tag(RigType.hamlibManaged)
                    Text(L("hamlib rigctld (síť)")).tag(RigType.hamlib)
                    Text("flrig").tag(RigType.flrig)
                }
            } header: { Text("Rig (CAT)") } footer: { Text(typeHint) }

            if s.rig.type == .cat {
                Section(L("Rádio")) {
                    Picker(L("Protokol"), selection: $s.rig.catProtocol) {
                        Text("Icom CI-V").tag(CATKind.icom)
                        Text(L("Yaesu (FT-991, FTDX10/101, FT-710…)")).tag(CATKind.yaesu)
                        Text(L("Kenwood (TS-590, TS-890…)")).tag(CATKind.kenwood)
                        Text(L("Elecraft (K3, K4, KX3…)")).tag(CATKind.elecraft)
                    }
                    if s.rig.catProtocol == .icom {
                        Picker(L("Model Icom"), selection: $s.rig.civAddress) {
                            ForEach(RigSettings.icomAddresses, id: \.0) { m in Text(String(format: "%@ (%02Xh)", m.0, m.1)).tag(m.1) }
                            if !RigSettings.icomAddresses.contains(where: { $0.1 == s.rig.civAddress }) {
                                Text(String(format: L("vlastní (%02Xh)"), s.rig.civAddress)).tag(s.rig.civAddress)
                            }
                        }
                        LabeledContent(L("Adresa CI-V (hex)")) {
                            TextField("", text: Binding(get: { String(format: "%02X", s.rig.civAddress) },
                                                        set: { if let v = Int($0, radix: 16), (1...0xDF).contains(v) { s.rig.civAddress = v } }))
                                .multilineTextAlignment(.trailing).frame(width: 60)
                        }
                    }
                }
            }

            if s.rig.type == .hamlibManaged {
                Section(L("Model hamlib")) {
                    if rigctld == nil {
                        Text(L("rigctld nenalezen – nainstaluj hamlib: brew install hamlib")).foregroundStyle(.orange)
                    } else if models.isEmpty {
                        ProgressView().controlSize(.small)
                    } else {
                        Picker(L("Model"), selection: $s.rig.hamlibModel) {
                            ForEach(models) { m in Text("\(m.title) (#\(m.id))").tag(m.id) }
                        }
                    }
                    TextField(L("Místní TCP port"), value: $s.rig.port, format: .number.grouping(.never), prompt: Text("4534"))
                }
            }

            if usesSerial {
                Section {
                    LabeledContent(L("Sériový port")) {
                        HStack {
                            Picker("", selection: $s.rig.serialPort) {
                                Text(L("— vyber —")).tag("")
                                ForEach(ports, id: \.self) { p in Text(p.replacingOccurrences(of: "/dev/", with: "")).tag(p) }
                                if !s.rig.serialPort.isEmpty, !ports.contains(s.rig.serialPort) {
                                    Text(s.rig.serialPort + " " + L("(nepřipojen)")).tag(s.rig.serialPort)
                                }
                            }.labelsHidden()
                            Button { ports = POSIXSerialPort.availablePorts() } label: { Image(systemName: "arrow.clockwise") }
                                .hint(L("Znovu načíst porty"))
                        }
                    }
                    Picker(L("Rychlost"), selection: $s.rig.baud) {
                        ForEach(RigSettings.baudRates, id: \.self) { b in Text("\(b) Bd").tag(b) }
                    }
                    Picker(L("Stop bity"), selection: $s.rig.stopBits) { Text("1").tag(1); Text("2").tag(2) }
                    if s.rig.type == .cat {
                        Toggle(L("RTS zapnuté (Yaesu „CAT RTS“)"),
                               isOn: Binding(get: { s.rig.effectiveCatRTS }, set: { s.rig.catRTS = $0 }))
                    }
                } header: { Text(L("Připojení")) } footer: {
                    Text(L("Rychlost a stop bity musí odpovídat nastavení CAT v menu rádia. Pro PTT přes CAT zvol v záložce PTT / FSK metodu CAT – port CAT nejde sdílet s PTT přes RTS/DTR."))
                }
            }

            if s.rig.type == .hamlib || s.rig.type == .flrig {
                Section(L("Síť")) {
                    TextField(L("Adresa"), text: $s.rig.host)
                    TextField(L("Port"), value: $s.rig.port, format: .number.grouping(.never),
                              prompt: Text(s.rig.type == .flrig ? "12345" : "4532"))
                }
            }

            if s.rig.type != .none {
                Section {
                    HStack {
                        Button(testing ? L("Zkouším…") : L("Vyzkoušet spojení")) { test() }.disabled(testing)
                        if let testResult { Text(testResult).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                } footer: { Text(L("Zkouška otevře port zvlášť – když ho právě používá běžící aplikace, zkouška selže na obsazeném portu.")) }
            }
        }
        .formStyle(.grouped)
        .task(id: s.rig.type) {
            guard s.rig.type == .hamlibManaged, models.isEmpty, let bin = rigctld else { return }
            models = await Task.detached { ManagedHamlibRig.availableModels(binary: bin) }.value
        }
    }

    var typeHint: String {
        switch s.rig.type {
        case .none: return L("Frekvence se nečte a PTT přes CAT není k dispozici.")
        case .cat: return L("Vestavěné ovládání bez dalších programů: frekvence, mód a PTT přímo přes USB kabel rádia.")
        case .hamlibManaged: return L("Pro ostatní rádia: aplikace sama spustí rigctld se zvoleným modelem a portem (hamlib z Homebrew).")
        case .hamlib: return L("hamlib: spusťte např. „rigctld -m <model> -r /dev/cu.X -s <baud>“. flrig: stačí spuštěný flrig. Prázdný port = výchozí.")
        case .flrig: return L("flrig musí běžet a mít povolené XML-RPC (výchozí port 12345).")
        }
    }

    private func test() {
        testing = true; testResult = nil
        let r = s.rig
        Task {
            let rig = RigFactory.make(r)
            var out: String
            do {
                try await rig.connect()
                let f = try await rig.frequency()
                let m = (try? await rig.mode()) ?? "?"
                out = L("OK: %@ kHz, mód %@", String(format: "%.3f", f / 1000), m)
            } catch { out = L("Chyba: %@", "\(error)") }
            await rig.disconnect()
            testResult = out; testing = false
        }
    }
}

struct APITab: View {
    @Binding var s: AppSettings
    var body: some View {
        Form {
            Section {
                Toggle("fldigi XML-RPC", isOn: $s.api.fldigiEnabled)
                LabeledContent(L("Port")) {
                    TextField("", value: $s.api.fldigiPort, format: .number.grouping(.never)).multilineTextAlignment(.trailing).frame(width: 80)
                }.disabled(!s.api.fldigiEnabled)
                Toggle("JSON-RPC (WebSocket)", isOn: $s.api.jsonRPCEnabled)
                LabeledContent(L("Port")) {
                    TextField("", value: $s.api.jsonRPCPort, format: .number.grouping(.never)).multilineTextAlignment(.trailing).frame(width: 80)
                }.disabled(!s.api.jsonRPCEnabled)
                Toggle(L("Povolit přístup ze sítě"), isOn: $s.api.allowRemote)
            } header: { Text(L("API pro loggery")) } footer: {
                Text(s.api.allowRemote ? L("Pozor: API nemá autentizaci a umí zapnout vysílač – zapínejte jen v důvěryhodné síti.")
                                       : L("API naslouchá jen na tomto Macu (127.0.0.1)."))
                    .foregroundStyle(s.api.allowRemote ? .orange : .secondary)
            }
            Section {
                LabeledContent(L("Adresář")) {
                    HStack {
                        Text(s.log.directory).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button(L("Vybrat…")) {
                            let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
                            if p.runModal() == .OK, let u = p.url { s.log.directory = u.path }
                        }
                    }
                }
                LabeledContent(L("Otevřený log")) {
                    Text(s.log.name + ".adi").foregroundStyle(.secondary)
                }
            } header: { Text("Log") } footer: { Text(L("Spojení (JSONL + ADIF) a série QTC se ukládají do tohoto adresáře. Jiný log založíte nebo otevřete v menu Soubor (Nový log…, Otevřít log…).")) }
            Section {
                Toggle(L("Průběžně zapisovat příjem do souboru"), isOn: $s.log.rxText)
                Toggle(L("Časová značka UTC na začátku řádku"), isOn: $s.log.rxTimestamps).disabled(!s.log.rxText)
                LabeledContent(L("Složka")) {
                    HStack {
                        Text(s.log.rxDirectory.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button { try? FileManager.default.createDirectory(at: s.log.rxDirectory, withIntermediateDirectories: true)
                                 NSWorkspace.shared.open(s.log.rxDirectory) } label: { Image(systemName: "folder") }
                            .hint(L("Otevřít složku"))
                    }
                }
            } header: { Text(L("Záznam příjmu")) } footer: {
                Text(L("Každý den UTC jeden soubor rx-RRRR-MM-DD.txt. Přepínač je i v menu Soubor. Obsah okna příjmu uložíš přes Soubor → Uložit příjem do souboru…"))
            }
        }
        .formStyle(.grouped)
    }
}

/// Parametry modemu generované z popisu (mění se hned, bez restartu) + nastavení jádra (po Použít).
struct ModemTab: View {
    @Bindable var model: AppModel
    @Binding var s: AppSettings

    static let groups: [(String, (String) -> Bool)] = [
        ("Demodulátor", { ["demodType", "iirBandwidth", "firTaps", "integrator", "smoothFreq", "lpfFreq", "lpfOrder",
                           "majority", "ignoreFraming", "limiterAGC", "limiterOversampling", "atc"].contains($0) }),
        ("Rychlost a formát", { ["baud", "mark", "shift", "reverse", "bitLength", "stopBits", "parity", "uos"].contains($0) }),
        ("AFC, NET a squelch", { $0.hasPrefix("afc") || ["net", "squelch", "squelchLevel"].contains($0) }),
        ("Filtry (BPF, AA6YQ, notch/LMS)", { $0.hasPrefix("aa6yq") || $0.hasPrefix("lms") || $0.hasPrefix("notch")
            || ["bpf", "bpfWidth", "twoNotch"].contains($0) }),
        ("PLL", { $0.hasPrefix("pll") }),
        ("Vysílání", { ["diddle", "echo", "txGain", "txBPF", "txLPF", "txLPFFreq", "charWait", "charWaitDiddle",
                        "randomDiddle"].contains($0) }),
    ]

    static func groupTitle(_ id: String) -> String {
        switch id {
        case "Demodulátor": return L("Demodulátor")
        case "Rychlost a formát": return L("Rychlost a formát")
        case "AFC, NET a squelch": return L("AFC, NET a squelch")
        case "Filtry (BPF, AA6YQ, notch/LMS)": return L("Filtry (BPF, AA6YQ, notch/LMS)")
        case "PLL": return "PLL"
        case "Vysílání": return L("Vysílání")
        default: return id
        }
    }

    func descriptors(_ f: (String) -> Bool) -> [ParameterDescriptor] { model.descriptors.filter { f($0.id) } }

    /// České popisky parametrů (popisy z jádra jsou anglicky kvůli API); nil = použít popis z jádra.
    static func paramName(_ id: String) -> String? {
        switch id {
        case "baud": return L("Rychlost")
        case "mark": return "Mark"
        case "shift": return "Shift"
        case "reverse": return L("Reverse (prohodit mark/space)")
        case "afc": return "AFC"
        case "afcMode": return L("Režim AFC")
        case "afcSquelch": return L("Práh AFC")
        case "afcTime": return L("Časová konstanta AFC")
        case "afcSweep": return L("Rozsah hledání AFC")
        case "afcMaxDev": return L("Max. odchylka AFC (0 = bez omezení)")
        case "afcGate": return L("AFC jen při otevřeném squelchi")
        case "net": return L("NET (TX na kmitočtu RX)")
        case "atc": return "ATC"
        case "squelch": return L("Squelch")
        case "squelchLevel": return L("Úroveň squelche")
        case "demodType": return L("Demodulátor")
        case "iirBandwidth": return L("Šířka IIR")
        case "firTaps": return L("Odbočky FIR")
        case "integrator": return L("Integrátor")
        case "smoothFreq": return L("Vyhlazení")
        case "lpfFreq": return L("Mez LPF")
        case "lpfOrder": return L("Řád LPF")
        case "majority": return L("Majoritní logika")
        case "ignoreFraming": return L("Ignorovat chyby rámce")
        case "bitLength": return L("Délka znaku (bity)")
        case "stopBits": return L("Stop bity")
        case "parity": return L("Parita")
        case "limiterAGC": return L("AGC limiteru")
        case "limiterOversampling": return L("Převzorkování limiteru")
        case "uos": return L("Unshift on space (RX)")
        case "diddle": return "Diddle"
        case "echo": return L("Echo vysílání")
        case "bpf": return L("Vstupní BPF")
        case "bpfWidth": return L("Přesah BPF")
        case "lms": return L("Zářez / LMS")
        case "txGain": return L("Úroveň TX výstupu")
        case "aa6yq": return L("Filtr AA6YQ")
        case "aa6yqBpfTaps": return L("AA6YQ – odbočky BPF")
        case "aa6yqBpfWidth": return L("AA6YQ – přesah BPF")
        case "aa6yqBefTaps": return L("AA6YQ – odbočky zádrže")
        case "aa6yqBefWidth": return L("AA6YQ – polovina šířky zádrže")
        case "lmsType": return L("Typ (zářez / LMS)")
        case "notchFreq": return L("Zářez")
        case "notch2Freq": return L("Druhý zářez")
        case "twoNotch": return L("Dva zářezy")
        case "notchTaps": return L("Odbočky zářezu")
        case "lmsTaps": return L("Odbočky LMS")
        case "lmsMu2": return L("LMS 2μ")
        case "lmsGamma": return L("LMS γ")
        case "lmsDelay": return L("Zpoždění LMS")
        case "lmsAGC": return L("AGC LMS")
        case "lmsInvert": return L("Invertovat výstup LMS")
        case "lmsBPF": return L("LMS s BPF")
        case "pllVcoGain": return L("Zisk VCO")
        case "pllLoopOrder": return L("Řád smyčkového LPF")
        case "pllLoopFc": return L("Mez smyčkového LPF")
        case "pllOutOrder": return L("Řád výstupního LPF")
        case "pllOutFc": return L("Mez výstupního LPF")
        case "txBPF": return "TX BPF"
        case "txLPF": return L("TX LPF (tvarování)")
        case "txLPFFreq": return L("Mez TX LPF")
        case "charWait": return L("Čekání mezi znaky")
        case "charWaitDiddle": return L("Čekání vyplnit diddle")
        case "randomDiddle": return L("Náhodný diddle")
        default: return nil
        }
    }

    static func choiceName(_ id: String, _ v: String) -> String {
        switch (id, v) {
        case ("afcMode", "free"): return L("volný")
        case ("afcMode", "fixed"): return L("pevný shift")
        case ("afcMode", "ham"): return "HAM (170 Hz)"
        case ("afcMode", "fsk"): return "FSK"
        case ("integrator", "average"): return L("klouzavý průměr")
        case ("integrator", "lpf"): return "IIR LPF"
        case ("diddle", "off"): return L("vypnuto")
        case ("lmsType", "notch"): return L("zářez")
        case ("parity", "none"): return L("žádná")
        case ("parity", "even"): return L("sudá")
        case ("parity", "odd"): return L("lichá")
        default: return v.uppercased() == v ? v : v.uppercased()
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(L("Japonský Baudot (J-BELL)"), isOn: $s.rttyCore.japanese)
                Toggle(L("LTRS/FIGS posílat dvakrát"), isOn: $s.rttyCore.doubleShift)
                Toggle("TX unshift on space", isOn: $s.rttyCore.txUOS)
            } header: { Text(L("Jádro")) } footer: { Text(L("Tato tři nastavení se projeví po Použít (modem se vytvoří znovu).")) }
            ForEach(Self.groups, id: \.0) { g in
                Section(Self.groupTitle(g.0)) { ForEach(descriptors(g.1), id: \.id) { d in row(d) } }
            }
            let known = Set(Self.groups.flatMap { g in descriptors(g.1).map(\.id) })
            let rest = model.descriptors.filter { !known.contains($0.id) }
            if !rest.isEmpty { Section(L("Ostatní")) { ForEach(rest, id: \.id) { d in row(d) } } }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder func row(_ d: ParameterDescriptor) -> some View {
                let title = Self.paramName(d.id) ?? d.label
                switch d.kind {
                case .bool: Toggle(title, isOn: model.boolBinding(d.id))
                case .choice(let opts):
                    Picker(title, selection: model.choiceBinding(d.id)) { ForEach(opts, id: \.self) { Text(Self.choiceName(d.id, $0)).tag($0) } }
                case .double(let r, let unit):
                    LabeledContent(title) {
                        HStack(spacing: 4) {
                            TextField("", value: model.doubleBinding(d.id), format: .number).multilineTextAlignment(.trailing).frame(width: 90)
                            Text(unit ?? "").foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                        }
                    }.hint("\(r.lowerBound.formatted())…\(r.upperBound.formatted())")
                case .int(let r):
                    LabeledContent(title) {
                        HStack(spacing: 4) {
                            TextField("", value: intBinding(d.id), format: .number).multilineTextAlignment(.trailing).frame(width: 70)
                            Stepper("", value: intBinding(d.id), in: r).labelsHidden()
                        }
                    }
                }
    }
    func intValue(_ id: String) -> Int { if case .int(let i)? = model.param(id) { return i }; return 0 }
    func intBinding(_ id: String) -> Binding<Int> {
        Binding(get: { intValue(id) }, set: { v in Task { await model.setParam(id, .int(v)) } })
    }
}

struct ContestTab: View {
    @Binding var s: AppSettings

    /// Vybraná předvolba; výběr závodu nastaví jeho nejbližší termín, „Vlastní“ nechá hodnoty k ruční úpravě.
    var presetBinding: Binding<ContestPreset?> {
        Binding(get: { s.contest.selectedPreset }, set: { p in
            guard let p else { s.contest.preset = nil; return }
            let serial = s.contest.nextSerial
            s.contest = ContestSettings.upcoming(p, locator: s.station.locator)
            if p == .waeRTTY { s.contest.nextSerial = max(1, serial) }
        })
    }

    var exchangeHint: String {
        switch s.contest.format {
        case .serial: return L("Prázdné = posílá se pořadové číslo; jinak tento text (např. stát).")
        case .cqrj: return L("Prázdné = moje CQ zóna podle značky; W/VE přidají stát, např. „05 NY“.")
        case .zone: return L("Prázdné = moje CQ zóna podle značky (DXCC).")
        case .bartg, .wae, .ped: return L("V tomto formátu se nepoužívá.")
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(L("Závodní režim"), isOn: $s.contest.enabled)
                Picker(L("Předvolba"), selection: presetBinding) {
                    Text(L("Vlastní nastavení")).tag(ContestPreset?.none)
                    Divider()
                    ForEach(ContestPreset.allCases, id: \.self) { p in Text(p.title).tag(ContestPreset?.some(p)) }
                }
            } footer: {
                if let p = s.contest.selectedPreset {
                    Text(L("%@. Termín ověř v pravidlech závodu.", p.summary))
                } else {
                    Text(L("Předvolba nastaví název, formát výměny a nejbližší začátek známého závodu."))
                }
            }
            Section {
                Picker(L("Formát výměny"), selection: $s.contest.format) {
                    Text(L("RST + pořadové číslo")).tag(ContestFormat.serial)
                    Text(L("RST + CQ zóna (OK DX RTTY)")).tag(ContestFormat.zone)
                    Text(L("CQ/RJ – zóna + QTH (CQ WW)")).tag(ContestFormat.cqrj)
                    Text(L("BARTG – číslo + čas UTC")).tag(ContestFormat.bartg)
                    Text(L("WAE – číslo + QTC")).tag(ContestFormat.wae)
                    Text(L("PED – klik = značka")).tag(ContestFormat.ped)
                }
                TextField(L("Odesílaná výměna"), text: $s.contest.exchange, prompt: Text(L("automaticky")))
                    .disabled([.bartg, .wae, .ped].contains(s.contest.format))
                NumberRow(title: L("Další pořadové číslo"), value: $s.contest.nextSerial, range: 1...99_999)
                    .disabled(!s.contest.sendsSerial)
            } header: { Text(L("Výměna")) } footer: { Text(exchangeHint) }
            .disabled(!s.contest.enabled)
            Section {
                TextField(L("Název (CONTEST)"), text: $s.contest.name, prompt: Text(L("např. OK-DX-RTTY")))
                TextField(L("Kategorie"), text: $s.contest.category, prompt: Text("OPERATOR: SINGLE-OP; POWER: LOW"))
                LabeledContent(L("Začátek (UTC)")) {
                    HStack {
                        if s.contest.start != nil {
                            DatePicker("", selection: Binding(get: { s.contest.start ?? Date() }, set: { s.contest.start = $0 }))
                                .labelsHidden().environment(\.timeZone, TimeZone(identifier: "UTC")!)
                            Button(L("Zrušit")) { s.contest.start = nil }
                        } else {
                            Text(L("posledních 72 h")).foregroundStyle(.secondary)
                        }
                        Button(L("Teď")) { s.contest.start = Date() }
                    }
                }
            } header: { Text(L("Cabrillo a začátek")) } footer: {
                Text(L("Kategorie jako „KLÍČ: hodnota“ oddělené středníkem. QTC (WAE) počítá jen spojení od začátku závodu. Export: Log → Exportovat Cabrillo…"))
            }
            .disabled(!s.contest.enabled)
            Section {
                Text(L("%N odesílané číslo nebo výměna · %M přijaté · %x / %y číslo a čas (BARTG) · %r / %s RST")).font(.callout)
            } header: { Text(L("Makra")) }
        }
        .formStyle(.grouped)
    }
}

struct DisplayTab: View {
    @Binding var s: AppSettings
    static let ranges: [(String, Double, Double)] = [("0–3000 Hz", 0, 3000), ("300–2700 Hz", 300, 2700),
                                                     ("1000–3000 Hz", 1000, 3000), ("1500–2800 Hz", 1500, 2800),
                                                     ("0–4000 Hz", 0, 4000)]
    var body: some View {
        Form {
            LanguageSection()
            Section {
                Picker(L("Rozsah"), selection: Binding(get: { "\(Int(s.display.fromHz))-\(Int(s.display.toHz))" },
                                                    set: { v in
                    if let r = Self.ranges.first(where: { "\(Int($0.1))-\(Int($0.2))" == v }) { s.display.fromHz = r.1; s.display.toHz = r.2 }
                })) {
                    ForEach(Self.ranges, id: \.0) { r in Text(r.0).tag("\(Int(r.1))-\(Int(r.2))") }
                }
                Toggle(L("Automatické zesílení"), isOn: $s.display.autoGain)
                LabeledContent(L("Zesílení")) {
                    HStack {
                        Slider(value: $s.display.gainDB, in: -30...30, step: 1)
                        Text("\(Int(s.display.gainDB)) dB").monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
                    }
                }
                Picker(L("Paleta vodopádu"), selection: $s.display.palette) {
                    ForEach(WaterfallPalette.allCases, id: \.self) { p in Text(Self.paletteName(p)).tag(p) }
                }
                Picker(L("Odezva spektra"), selection: $s.display.fftResponse) {
                    Text(L("rychlá")).tag(FFTResponse.fast)
                    Text(L("střední")).tag(FFTResponse.normal)
                    Text(L("pomalá")).tag(FFTResponse.slow)
                }
            } header: { Text(L("Spektrum a vodopád")) } footer: { Text(L("Rozsah a zesílení jdou měnit i v menu v levém horním rohu spektra.")) }
            Section("XY scope") {
                Picker(L("Velikost"), selection: $s.display.xySize) {
                    Text(L("malá")).tag(XYScopeSize.small)
                    Text(L("střední")).tag(XYScopeSize.medium)
                    Text(L("velká")).tag(XYScopeSize.large)
                }
                Picker(L("Kvalita"), selection: $s.display.xyQuality) {
                    Text(L("nízká (méně bodů)")).tag(XYScopeQuality.low)
                    Text(L("vysoká")).tag(XYScopeQuality.high)
                }
            }
            Section {
                Picker(L("Písmo"), selection: $s.display.rxFont) {
                    Text(L("Systémové neproporcionální")).tag("")
                    ForEach(Self.monospacedFamilies, id: \.self) { f in Text(f).tag(f) }
                }
                LabeledContent(L("Velikost písma")) {
                    HStack(spacing: 4) {
                        Text("\(Int(s.display.fontSize)) pt").monospacedDigit()
                        Stepper("", value: $s.display.fontSize, in: 9...32).labelsHidden()
                    }
                }
                ColorRow(title: L("Pozadí příjmu"), hex: $s.display.rxBackground, fallback: Color(nsColor: .textBackgroundColor))
                ColorRow(title: L("Text příjmu"), hex: $s.display.rxTextColor, fallback: Color(nsColor: .textColor))
                ColorRow(title: L("Echo vysílání v příjmu"), hex: $s.display.rxEchoColor, fallback: .red)
                ColorRow(title: L("Pozadí vysílání"), hex: $s.display.txBackground, fallback: Color(nsColor: .textBackgroundColor))
                ColorRow(title: L("Text vysílání"), hex: $s.display.txTextColor, fallback: Color(nsColor: .textColor))
            } header: { Text(L("Písmo a barvy oken")) } footer: { Text(L("„Výchozí“ vrátí systémovou barvu (přizpůsobí se tmavému režimu).")) }
            Section {
                Toggle(L("CR/LF na začátku vysílání tlačítkem TX"), isOn: $s.txWindow.autoCRLF)
                Toggle(L("Zalamovat psaný text"), isOn: Binding(get: { s.txWindow.wrapColumn > 0 },
                                                             set: { s.txWindow.wrapColumn = $0 ? 64 : 0 }))
                if s.txWindow.wrapColumn > 0 {
                    NumberRow(title: L("Délka řádku"), value: $s.txWindow.wrapColumn, range: TxWindowSettings.wrapRange, unit: L("znaků"))
                }
            } header: { Text(L("Okno vysílání")) }
            Section(L("Ostatní")) {
                Toggle(L("Časové značky UTC při přepnutí TX/RX"), isOn: $s.display.timestamps)
                Toggle(L("Bublinová nápověda tlačítek"), isOn: $s.display.showHints)
            }
        }
        .formStyle(.grouped)
    }

    static func paletteName(_ p: WaterfallPalette) -> String {
        switch p {
        case .classic: return L("Klasická (modrá–žlutá)")
        case .gray: return L("Šedá")
        case .heat: return L("Teplotní (červená–žlutá)")
        case .green: return L("Zelená")
        case .blue: return L("Modrá")
        }
    }

    /// Rodiny neproporcionálních písem nainstalované v systému.
    static let monospacedFamilies: [String] = {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        return Array(Set(names.compactMap { NSFont(name: $0, size: 12)?.familyName }))
            .filter { !$0.hasPrefix(".") }.sorted()
    }()
}

/// Výběr barvy s návratem na výchozí (systémovou) barvu.
struct ColorRow: View {
    let title: String
    @Binding var hex: String?
    let fallback: Color
    var body: some View {
        LabeledContent(title) {
            HStack {
                if hex != nil { Button(L("Výchozí")) { hex = nil }.controlSize(.small) }
                ColorPicker("", selection: Binding(get: { Color(hex: hex) ?? fallback }, set: { hex = $0.hexString }),
                            supportsOpacity: false).labelsHidden()
            }
        }
    }
}

/// Klávesové zkratky maker a příkazů (MMTTY „Assign ShortCut Keys“).
struct KeysTab: View {
    @Binding var s: AppSettings
    var body: some View {
        Form {
            Section {
                ForEach(ShortcutCommand.allCases, id: \.id) { c in
                    LabeledContent(title(c)) {
                        HStack {
                            if s.shortcuts[c.id] != nil {
                                Button(L("Výchozí")) { s.shortcuts[c.id] = nil }.controlSize(.small)
                            }
                            KeyRecorder(binding: Binding(get: { s.binding(for: c) },
                                                         set: { s.shortcuts[c.id] = $0 == c.defaultBinding ? nil : $0 }))
                        }
                    }
                }
            } header: { Text(L("Klávesové zkratky")) } footer: {
                let conflicts = s.conflictingShortcuts()
                if conflicts.isEmpty {
                    Text(L("Klikni na zkratku a stiskni novou kombinaci kláves. Delete = bez zkratky, Esc = zrušit. Samotné písmeno bez modifikátoru nejde (kolize s psaním)."))
                } else {
                    Text(L("Stejná zkratka u více příkazů: %@", conflicts.map { $0.map(title).joined(separator: " = ") }.joined(separator: "; ")))
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    func title(_ c: ShortcutCommand) -> String {
        switch c {
        case .macro(let i):
            let n = i < s.macros.count ? s.macros[i].name : ""
            return n.isEmpty ? L("Makro %ld", i + 1) : L("Makro %ld – %@", i + 1, n)
        case .toggleTx: return "TX / RX"
        case .rxNow: return L("Okamžitě RX")
        case .tune: return L("Ladění (tune)")
        case .logQSO: return L("Zalogovat QSO")
        case .clearQSO: return L("Vymazat QSO")
        case .clearRx: return L("Vymazat příjem")
        case .stopMacro: return L("Zastavit opakování makra")
        case .openLog: return L("Otevřít log")
        }
    }
}

/// Pole pro záznam zkratky: po kliknutí čeká na stisk kláves.
struct KeyRecorder: View {
    @Binding var binding: KeyBinding
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? L("Stiskni klávesy…") : binding.display) { recording ? stop() : start() }
            .monospaced()
            .frame(minWidth: 110)
            .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53, e.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty { stop(); return nil }
            if e.keyCode == 51 || e.keyCode == 117, e.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
                binding = .none; stop(); return nil
            }
            if let b = KeyBinding.from(e) { binding = b; stop() } else { NSSound.beep() }
            return nil
        }
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil; recording = false
    }
}
