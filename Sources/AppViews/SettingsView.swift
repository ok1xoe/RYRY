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
    /// Vybraná záložka (spouštěcí parametr `-settingsTab N` pro snímky obrazovky).
    @State private var tab = UserDefaults.standard.integer(forKey: "settingsTab")
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                StationTab(s: $draft).tabItem { Label("Stanice", systemImage: "person.crop.circle") }.tag(0)
                AudioTab(s: $draft, model: model).tabItem { Label("Zvuk", systemImage: "waveform") }.tag(1)
                PTTTab(s: $draft).tabItem { Label("PTT / FSK", systemImage: "cable.connector") }.tag(2)
                RigTab(s: $draft).tabItem { Label("Rig", systemImage: "antenna.radiowaves.left.and.right") }.tag(3)
                ModemTab(model: model, s: $draft).tabItem { Label("Modem", systemImage: "slider.horizontal.3") }.tag(4)
                ContestTab(s: $draft).tabItem { Label("Závod", systemImage: "trophy") }.tag(5)
                DisplayTab(s: $draft).tabItem { Label("Zobrazení", systemImage: "paintpalette") }.tag(6)
                APITab(s: $draft).tabItem { Label("API a log", systemImage: "network") }.tag(7)
            }
            Divider()
            HStack {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("Změny se projeví po Použít (restart zvuku, rigu a API). Parametry modemu platí hned.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Vrátit") { draft = model.settings; baseline = draft }
                Button("Použít") {
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
                TextField("Značka", text: $s.station.call, prompt: Text("OK1ABC"))
                TextField("Lokátor", text: $s.station.locator, prompt: Text("JO70FB"))
                TextField("Jméno", text: $s.station.name, prompt: Text("Tomáš"))
                TextField("QTH", text: $s.station.qth, prompt: Text("Praha"))
            } header: { Text("Moje stanice") } footer: {
                Text("Značka se posílá v makrech (%m) a podle ní se určuje zóna a kontinent (DXCC).")
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
            Section("Příjem") {
                Picker("Vstup", selection: $s.audio.inputUID) {
                    Text("Výchozí").tag(String?.none)
                    ForEach(devices.filter { $0.inputChannels > 0 }, id: \.uid) { Text($0.name).tag(String?.some($0.uid)) }
                }
                Picker("Kanál", selection: $s.audio.inputChannel) {
                    Text("Levý").tag(AudioChannel.left); Text("Pravý").tag(AudioChannel.right); Text("Mono").tag(AudioChannel.mono)
                }
            }
            Section("Vysílání") {
                Picker("Výstup", selection: $s.audio.outputUID) {
                    Text("Výchozí").tag(String?.none)
                    ForEach(devices.filter { $0.outputChannels > 0 }, id: \.uid) { Text($0.name).tag(String?.some($0.uid)) }
                }
                Picker("Kanál", selection: $s.audio.outputChannel) {
                    Text("Levý").tag(AudioChannel.left); Text("Pravý").tag(AudioChannel.right); Text("Oba").tag(AudioChannel.mono)
                }
                LabeledContent("Hlasitost") {
                    HStack {
                        Slider(value: $s.audio.outputGain, in: 0...1)
                        Text("\(Int(s.audio.outputGain * 100)) %").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section {
                LabeledContent("Korekce RX") {
                    HStack(spacing: 4) {
                        TextField("", value: $s.clock.rxPPM, format: .number.precision(.fractionLength(0...2)))
                            .multilineTextAlignment(.trailing).frame(width: 90)
                        Text("ppm").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Korekce TX") {
                    HStack(spacing: 4) {
                        TextField("", value: $s.clock.txPPM, format: .number.precision(.fractionLength(0...2)))
                            .multilineTextAlignment(.trailing).frame(width: 90)
                        Text("ppm").foregroundStyle(.secondary)
                    }
                }
                LabeledContent {
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
                } label: { Text(result.isEmpty ? "Měření" : result).foregroundStyle(result.isEmpty ? .primary : .secondary) }
            } header: { Text("Kalibrace hodin zvukové karty") } footer: {
                Text("Core Audio měří skutečnou vzorkovací frekvenci zařízení proti hodinám systému (NTP). Rozsah ± 20 000 ppm.")
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
                Picker("Metoda", selection: $s.ptt.method) {
                    Text("Žádná (VOX)").tag(PTTMethod.none); Text("CAT (rig)").tag(PTTMethod.cat)
                    Text("RTS").tag(PTTMethod.rts); Text("DTR").tag(PTTMethod.dtr); Text("RTS + DTR").tag(PTTMethod.rtsDtr)
                }
                Picker("Sériový port", selection: $s.ptt.port) {
                    Text("—").tag(String?.none)
                    ForEach(ports, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .disabled(![.rts, .dtr, .rtsDtr].contains(s.ptt.method))
                Toggle("Invertovat", isOn: $s.ptt.invert)
            } header: { Text("PTT") }
            Section {
                NumberRow(title: "Zpoždění TX", value: $s.ptt.txDelayMs, range: 0...2000, step: 10, unit: "ms")
                NumberRow(title: "Doběh PTT", value: $s.ptt.pttTailMs, range: 0...2000, step: 10, unit: "ms")
                NumberRow(title: "Bezpečnostní časovač", value: $s.ptt.pttTimeoutS, range: 10...3600, step: 10, unit: "s")
            } header: { Text("Časování") } footer: {
                Text("Časovač vypne vysílání, pokud trvá déle (ochrana proti zaseknutému PTT).")
            }
            Section {
                Picker("Režim", selection: $s.fsk.output) {
                    Text("AFSK (zvuk)").tag(FSKOutputKind.afsk)
                    Text("FSK – UART TxD (FTDI)").tag(FSKOutputKind.fskUART)
                    Text("FSK – softwarové časování").tag(FSKOutputKind.fskSoft)
                }
                Group {
                    Picker("Port FSK", selection: $s.fsk.port) {
                        Text("—").tag(String?.none)
                        ForEach(ports, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    Picker("Linka", selection: $s.fsk.line) {
                        Text("TxD (break)").tag(FSKLine.txdBreak); Text("DTR").tag(FSKLine.dtr); Text("RTS").tag(FSKLine.rts)
                    }
                    .disabled(s.fsk.output != .fskSoft)
                    Toggle("Invertovat FSK", isOn: $s.fsk.invert)
                    Toggle("Zvuk i při FSK", isOn: $s.fsk.audioDuringFSK)
                }
                .disabled(s.fsk.output == .afsk)
            } header: { Text("Klíčování") } footer: {
                Text("AFSK = RTTY zvukem (rádio v SSB/DATA). FSK = klíčování sériovou linkou (rádio v režimu FSK/RTTY).")
            }
        }
        .formStyle(.grouped)
        .onAppear { ports = POSIXSerialPort.availablePorts() }
    }
}

struct RigTab: View {
    @Binding var s: AppSettings
    var body: some View {
        Form {
            Section {
                Picker("Ovládání", selection: $s.rig.type) {
                    Text("Žádné").tag(RigType.none); Text("hamlib rigctld").tag(RigType.hamlib); Text("flrig").tag(RigType.flrig)
                }
                Group {
                    TextField("Adresa", text: $s.rig.host)
                    TextField("Port", value: $s.rig.port, format: .number.grouping(.never),
                              prompt: Text(s.rig.type == .flrig ? "12345" : "4532"))
                }
                .disabled(s.rig.type == .none)
            } header: { Text("Rig (CAT)") } footer: {
                Text("hamlib: spusťte např. „rigctld -m <model> -r /dev/cu.X -s <baud>“. flrig: stačí spuštěný flrig. Prázdný port = výchozí.")
            }
        }
        .formStyle(.grouped)
    }
}

struct APITab: View {
    @Binding var s: AppSettings
    var body: some View {
        Form {
            Section {
                Toggle("fldigi XML-RPC", isOn: $s.api.fldigiEnabled)
                LabeledContent("Port") {
                    TextField("", value: $s.api.fldigiPort, format: .number.grouping(.never)).multilineTextAlignment(.trailing).frame(width: 80)
                }.disabled(!s.api.fldigiEnabled)
                Toggle("JSON-RPC (WebSocket)", isOn: $s.api.jsonRPCEnabled)
                LabeledContent("Port") {
                    TextField("", value: $s.api.jsonRPCPort, format: .number.grouping(.never)).multilineTextAlignment(.trailing).frame(width: 80)
                }.disabled(!s.api.jsonRPCEnabled)
                Toggle("Povolit přístup ze sítě", isOn: $s.api.allowRemote)
            } header: { Text("API pro loggery") } footer: {
                Text(s.api.allowRemote ? "Pozor: API nemá autentizaci a umí zapnout vysílač – zapínejte jen v důvěryhodné síti."
                                       : "API naslouchá jen na tomto Macu (127.0.0.1).")
                    .foregroundStyle(s.api.allowRemote ? .orange : .secondary)
            }
            Section {
                LabeledContent("Adresář") {
                    HStack {
                        Text(s.log.directory).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Vybrat…") {
                            let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
                            if p.runModal() == .OK, let u = p.url { s.log.directory = u.path }
                        }
                    }
                }
            } header: { Text("Log") } footer: { Text("Spojení (JSONL + ADIF) a série QTC se ukládají do tohoto adresáře.") }
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

    func descriptors(_ f: (String) -> Bool) -> [ParameterDescriptor] { model.descriptors.filter { f($0.id) } }

    /// České popisky parametrů (popisy z jádra jsou anglicky kvůli API).
    static let czech: [String: String] = [
        "baud": "Rychlost", "mark": "Mark", "shift": "Shift", "reverse": "Reverse (prohodit mark/space)",
        "afc": "AFC", "afcMode": "Režim AFC", "afcSquelch": "Práh AFC", "afcTime": "Časová konstanta AFC",
        "afcSweep": "Rozsah hledání AFC", "afcMaxDev": "Max. odchylka AFC (0 = bez omezení)", "afcGate": "AFC jen při otevřeném squelchi",
        "net": "NET (TX na kmitočtu RX)", "atc": "ATC", "squelch": "Squelch", "squelchLevel": "Úroveň squelche",
        "demodType": "Demodulátor", "iirBandwidth": "Šířka IIR", "firTaps": "Odbočky FIR", "integrator": "Integrátor",
        "smoothFreq": "Vyhlazení", "lpfFreq": "Mez LPF", "lpfOrder": "Řád LPF", "majority": "Majoritní logika",
        "ignoreFraming": "Ignorovat chyby rámce", "bitLength": "Délka znaku (bity)", "stopBits": "Stop bity", "parity": "Parita",
        "limiterAGC": "AGC limiteru", "limiterOversampling": "Převzorkování limiteru", "uos": "Unshift on space (RX)",
        "diddle": "Diddle", "echo": "Echo vysílání", "bpf": "Vstupní BPF", "bpfWidth": "Přesah BPF",
        "lms": "Zářez / LMS", "txGain": "Úroveň TX výstupu",
        "aa6yq": "Filtr AA6YQ", "aa6yqBpfTaps": "AA6YQ – odbočky BPF", "aa6yqBpfWidth": "AA6YQ – přesah BPF",
        "aa6yqBefTaps": "AA6YQ – odbočky zádrže", "aa6yqBefWidth": "AA6YQ – polovina šířky zádrže",
        "lmsType": "Typ (zářez / LMS)", "notchFreq": "Zářez", "notch2Freq": "Druhý zářez", "twoNotch": "Dva zářezy",
        "notchTaps": "Odbočky zářezu", "lmsTaps": "Odbočky LMS", "lmsMu2": "LMS 2μ", "lmsGamma": "LMS γ", "lmsDelay": "Zpoždění LMS",
        "lmsAGC": "AGC LMS", "lmsInvert": "Invertovat výstup LMS", "lmsBPF": "LMS s BPF",
        "pllVcoGain": "Zisk VCO", "pllLoopOrder": "Řád smyčkového LPF", "pllLoopFc": "Mez smyčkového LPF",
        "pllOutOrder": "Řád výstupního LPF", "pllOutFc": "Mez výstupního LPF",
        "txBPF": "TX BPF", "txLPF": "TX LPF (tvarování)", "txLPFFreq": "Mez TX LPF", "charWait": "Čekání mezi znaky",
        "charWaitDiddle": "Čekání vyplnit diddle", "randomDiddle": "Náhodný diddle",
    ]

    static func choiceName(_ id: String, _ v: String) -> String {
        switch (id, v) {
        case ("afcMode", "free"): return "volný"
        case ("afcMode", "fixed"): return "pevný shift"
        case ("afcMode", "ham"): return "HAM (170 Hz)"
        case ("afcMode", "fsk"): return "FSK"
        case ("integrator", "average"): return "klouzavý průměr"
        case ("integrator", "lpf"): return "IIR LPF"
        case ("diddle", "off"): return "vypnuto"
        case ("lmsType", "notch"): return "zářez"
        case ("parity", "none"): return "žádná"
        case ("parity", "even"): return "sudá"
        case ("parity", "odd"): return "lichá"
        default: return v.uppercased() == v ? v : v.uppercased()
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Japonský Baudot (J-BELL)", isOn: $s.rttyCore.japanese)
                Toggle("LTRS/FIGS posílat dvakrát", isOn: $s.rttyCore.doubleShift)
                Toggle("TX unshift on space", isOn: $s.rttyCore.txUOS)
            } header: { Text("Jádro") } footer: { Text("Tato tři nastavení se projeví po Použít (modem se vytvoří znovu).") }
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
                let title = Self.czech[d.id] ?? d.label
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
                    }.help("\(r.lowerBound.formatted())…\(r.upperBound.formatted())")
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
        case .serial: return "Prázdné = posílá se pořadové číslo; jinak tento text (např. stát)."
        case .cqrj: return "Prázdné = moje CQ zóna podle značky; W/VE přidají stát, např. „05 NY“."
        case .zone: return "Prázdné = moje CQ zóna podle značky (DXCC)."
        case .bartg, .wae, .ped: return "V tomto formátu se nepoužívá."
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Závodní režim", isOn: $s.contest.enabled)
                Picker("Předvolba", selection: presetBinding) {
                    Text("Vlastní nastavení").tag(ContestPreset?.none)
                    Divider()
                    ForEach(ContestPreset.allCases, id: \.self) { p in Text(p.title).tag(ContestPreset?.some(p)) }
                }
            } footer: {
                if let p = s.contest.selectedPreset {
                    Text("\(p.summary). Termín ověř v pravidlech závodu.")
                } else {
                    Text("Předvolba nastaví název, formát výměny a nejbližší začátek známého závodu.")
                }
            }
            Section {
                Picker("Formát výměny", selection: $s.contest.format) {
                    Text("RST + pořadové číslo").tag(ContestFormat.serial)
                    Text("RST + CQ zóna (OK DX RTTY)").tag(ContestFormat.zone)
                    Text("CQ/RJ – zóna + QTH (CQ WW)").tag(ContestFormat.cqrj)
                    Text("BARTG – číslo + čas UTC").tag(ContestFormat.bartg)
                    Text("WAE – číslo + QTC").tag(ContestFormat.wae)
                    Text("PED – klik = značka").tag(ContestFormat.ped)
                }
                TextField("Odesílaná výměna", text: $s.contest.exchange, prompt: Text("automaticky"))
                    .disabled([.bartg, .wae, .ped].contains(s.contest.format))
                NumberRow(title: "Další pořadové číslo", value: $s.contest.nextSerial, range: 1...99_999)
                    .disabled(!s.contest.sendsSerial)
            } header: { Text("Výměna") } footer: { Text(exchangeHint) }
            .disabled(!s.contest.enabled)
            Section {
                TextField("Název (CONTEST)", text: $s.contest.name, prompt: Text("např. OK-DX-RTTY"))
                TextField("Kategorie", text: $s.contest.category, prompt: Text("OPERATOR: SINGLE-OP; POWER: LOW"))
                LabeledContent("Začátek (UTC)") {
                    HStack {
                        if s.contest.start != nil {
                            DatePicker("", selection: Binding(get: { s.contest.start ?? Date() }, set: { s.contest.start = $0 }))
                                .labelsHidden().environment(\.timeZone, TimeZone(identifier: "UTC")!)
                            Button("Zrušit") { s.contest.start = nil }
                        } else {
                            Text("posledních 72 h").foregroundStyle(.secondary)
                        }
                        Button("Teď") { s.contest.start = Date() }
                    }
                }
            } header: { Text("Cabrillo a začátek") } footer: {
                Text("Kategorie jako „KLÍČ: hodnota“ oddělené středníkem. QTC (WAE) počítá jen spojení od začátku závodu. Export: Log → Exportovat Cabrillo…")
            }
            .disabled(!s.contest.enabled)
            Section {
                Text("%N odesílané číslo nebo výměna · %M přijaté · %x / %y číslo a čas (BARTG) · %r / %s RST").font(.callout)
            } header: { Text("Makra") }
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
            Section {
                Picker("Rozsah", selection: Binding(get: { "\(Int(s.display.fromHz))-\(Int(s.display.toHz))" },
                                                    set: { v in
                    if let r = Self.ranges.first(where: { "\(Int($0.1))-\(Int($0.2))" == v }) { s.display.fromHz = r.1; s.display.toHz = r.2 }
                })) {
                    ForEach(Self.ranges, id: \.0) { r in Text(r.0).tag("\(Int(r.1))-\(Int(r.2))") }
                }
                Toggle("Automatické zesílení", isOn: $s.display.autoGain)
                LabeledContent("Zesílení") {
                    HStack {
                        Slider(value: $s.display.gainDB, in: -30...30, step: 1)
                        Text("\(Int(s.display.gainDB)) dB").monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
                    }
                }
            } header: { Text("Spektrum a vodopád") } footer: { Text("Rozsah a zesílení jdou měnit i v menu v levém horním rohu spektra.") }
            Section("Text") {
                LabeledContent("Velikost písma") {
                    HStack(spacing: 4) {
                        Text("\(Int(s.display.fontSize)) pt").monospacedDigit()
                        Stepper("", value: $s.display.fontSize, in: 9...32).labelsHidden()
                    }
                }
                Toggle("Časové značky UTC při přepnutí TX/RX", isOn: $s.display.timestamps)
            }
        }
        .formStyle(.grouped)
    }
}
