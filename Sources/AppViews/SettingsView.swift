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
    @State private var baseline = AppSettings()       // stav, ze kterého koncept vyšel
    @State private var loaded = false
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            TabView {
                StationTab(s: $draft).tabItem { Text("Stanice") }
                AudioTab(s: $draft, model: model).tabItem { Text("Zvuk") }
                PTTTab(s: $draft).tabItem { Text("PTT / FSK") }
                RigTab(s: $draft).tabItem { Text("Rig") }
                ModemTab(model: model, s: $draft).tabItem { Text("Modem") }
                ContestTab(s: $draft).tabItem { Text("Závod") }
                DisplayTab(s: $draft).tabItem { Text("Zobrazení") }
                APITab(s: $draft).tabItem { Text("API a log") }
            }
            .padding()
            HStack {
                Text("Změny se projeví po Použít (restart zvuku, rigu a API).").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Vrátit") { draft = model.settings; baseline = draft }
                Button("Použít") {
                    let d = draft, b = baseline
                    Task { await model.applySettings(d, baseline: b); draft = model.settings; baseline = draft }
                }.keyboardShortcut(.defaultAction)
            }.padding([.horizontal, .bottom])
        }
        .frame(width: 680, height: 560)
        .onAppear { if !loaded { draft = model.settings; baseline = draft; loaded = true } }
        .onDisappear { loaded = false }                  // příště načíst aktuální stav
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
    @Bindable var model: AppModel
    @State private var devices: [AudioDevice] = []
    @State private var measuring = false
    @State private var result = ""
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
            Section("Kalibrace hodin zvukové karty") {
                HStack {
                    Text("RX korekce")
                    Spacer()
                    TextField("", value: $s.clock.rxPPM, format: .number.precision(.fractionLength(0...2))).frame(width: 90)
                    Text("ppm").foregroundStyle(.secondary)
                }
                HStack {
                    Text("TX korekce")
                    Spacer()
                    TextField("", value: $s.clock.txPPM, format: .number.precision(.fractionLength(0...2))).frame(width: 90)
                    Text("ppm").foregroundStyle(.secondary)
                }
                HStack {
                    Button(measuring ? "Měřím…" : "Změřit (30 s)") {
                        measuring = true; result = ""
                        Task {
                            let r = await model.measureClock(seconds: 30, inputUID: s.audio.inputUID, outputUID: s.audio.outputUID)
                            measuring = false
                            if let rx = r.rx { s.clock.rxPPM = (rx * 10).rounded() / 10 }
                            if let tx = r.tx { s.clock.txPPM = (tx * 10).rounded() / 10 }
                            result = r.rx == nil && r.tx == nil ? "Zařízení neběží – spusťte příjem."
                                : String(format: "RX %@ ppm, TX %@ ppm – potvrďte Použít.",
                                         r.rx.map { String(format: "%.1f", $0) } ?? "—", r.tx.map { String(format: "%.1f", $0) } ?? "—")
                        }
                    }.disabled(measuring)
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
                Text("Core Audio měří skutečnou vzorkovací frekvenci zařízení proti hodinám systému (NTP). Korekce ± 20 000 ppm.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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

    func descriptors(_ f: (String) -> Bool) -> [ParameterDescriptor] { model.descriptors.filter { f($0.id) } }

    var body: some View {
        Form {
            Section("Jádro (projeví se po Použít)") {
                Toggle("Japonský Baudot (J-BELL)", isOn: $s.rttyCore.japanese)
                Toggle("LTRS/FIGS posílat dvakrát", isOn: $s.rttyCore.doubleShift)
                Toggle("TX unshift on space", isOn: $s.rttyCore.txUOS)
            }
            ForEach(Self.groups, id: \.0) { g in
                Section(g.0) { ForEach(descriptors(g.1), id: \.id) { d in row(d) } }
            }
            let known = Set(Self.groups.flatMap { g in descriptors(g.1).map(\.id) })
            let rest = model.descriptors.filter { !known.contains($0.id) }
            if !rest.isEmpty { Section("Ostatní") { ForEach(rest, id: \.id) { d in row(d) } } }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder func row(_ d: ParameterDescriptor) -> some View {
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
    func intValue(_ id: String) -> Int { if case .int(let i)? = model.param(id) { return i }; return 0 }
    func intBinding(_ id: String) -> Binding<Int> {
        Binding(get: { intValue(id) }, set: { v in Task { await model.setParam(id, .int(v)) } })
    }
}

struct ContestTab: View {
    @Binding var s: AppSettings
    var body: some View {
        Form {
            Menu("Předvolba závodu…") {
                ForEach(ContestPreset.allCases, id: \.self) { p in
                    Button(p.title) {
                        let serial = s.contest.nextSerial
                        s.contest = ContestSettings.preset(p, year: Calendar(identifier: .gregorian).component(.year, from: Date()))
                        if p == .waeRTTY { s.contest.nextSerial = max(1, serial) }
                    }
                }
            }
            .help("Nastaví název, formát výměny a začátek známého závodu")
            Toggle("Závodní režim (pořadová čísla, klik na číslo = přijaté číslo)", isOn: $s.contest.enabled)
            Picker("Formát", selection: $s.contest.format) {
                Text("RST + pořadové číslo (nebo pevná výměna)").tag(ContestFormat.serial)
                Text("CQ/RJ – zóna + QTH (CQ WW RTTY)").tag(ContestFormat.cqrj)
                Text("BARTG – číslo + čas UTC").tag(ContestFormat.bartg)
                Text("PED – klik = vždy značka, bez čísel").tag(ContestFormat.ped)
                Text("WAE – RST + číslo a výměna QTC").tag(ContestFormat.wae)
                Text("RST + CQ zóna (OK DX RTTY)").tag(ContestFormat.zone)
            }
            TextField("Název závodu (Cabrillo CONTEST)", text: $s.contest.name)
            TextField("Kategorie (Cabrillo, oddělit „;“)", text: $s.contest.category)
            Stepper("Další pořadové číslo: \(s.contest.nextSerial)", value: $s.contest.nextSerial, in: 1...99_999)
            HStack {
                DatePicker("Začátek závodu (UTC)", selection: Binding(get: { s.contest.start ?? Date() }, set: { s.contest.start = $0 }))
                    .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                Button("Teď") { s.contest.start = Date() }
                Button("Nenastaveno") { s.contest.start = nil }.disabled(s.contest.start == nil)
            }
            Text(s.contest.start == nil ? "Bez začátku: QTC počítá spojení za posledních 72 h." : "QTC (WAE) počítá jen spojení a série od začátku závodu.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Odesílaná výměna (CQ/RJ: moje zóna/QTH; RST+číslo: místo čísla, prázdné = číslo)", text: $s.contest.exchange)
            Text("BARTG: posílá se číslo a čas začátku QSO, %x = číslo, %y = čas. CQ/RJ: klik na číslo = zóna, na text = QTH. Makra: %N = odesílané číslo (nebo výměna), %M = přijaté (jako MMTTY: %r/%N z HisRST, %s/%M z MyRST). Export: Log → Exportovat Cabrillo…")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DisplayTab: View {
    @Binding var s: AppSettings
    static let ranges: [(String, Double, Double)] = [("0–3000 Hz", 0, 3000), ("300–2700 Hz", 300, 2700),
                                                     ("1000–3000 Hz", 1000, 3000), ("1500–2800 Hz", 1500, 2800),
                                                     ("0–4000 Hz", 0, 4000)]
    var body: some View {
        Form {
            Section("Spektrum a vodopád") {
                Picker("Rozsah", selection: Binding(get: { "\(Int(s.display.fromHz))-\(Int(s.display.toHz))" },
                                                    set: { v in
                    if let r = Self.ranges.first(where: { "\(Int($0.1))-\(Int($0.2))" == v }) { s.display.fromHz = r.1; s.display.toHz = r.2 }
                })) {
                    ForEach(Self.ranges, id: \.0) { r in Text(r.0).tag("\(Int(r.1))-\(Int(r.2))") }
                }
                Toggle("Automatické zesílení", isOn: $s.display.autoGain)
                Slider(value: $s.display.gainDB, in: -30...30, step: 1) { Text("Zesílení \(Int(s.display.gainDB)) dB") }
            }
            Section("Text") {
                Stepper("Velikost písma: \(Int(s.display.fontSize))", value: $s.display.fontSize, in: 9...32)
                Toggle("Časové značky UTC při přepnutí TX/RX", isOn: $s.display.timestamps)
            }
        }
    }
}
