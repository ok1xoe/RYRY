// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import AudioIO
import Keying
import Localization
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
                StationTab(s: $draft).tabItem { Label(L("Stanice"), systemImage: "person.crop.circle") }.tag(0)
                AudioTab(s: $draft, model: model).tabItem { Label(L("Zvuk"), systemImage: "waveform") }.tag(1)
                PTTTab(s: $draft).tabItem { Label("PTT / FSK", systemImage: "cable.connector") }.tag(2)
                RigTab(s: $draft).tabItem { Label("Rig", systemImage: "antenna.radiowaves.left.and.right") }.tag(3)
                ModemTab(model: model, s: $draft).tabItem { Label("Modem", systemImage: "slider.horizontal.3") }.tag(4)
                ContestTab(s: $draft).tabItem { Label(L("Závod"), systemImage: "trophy") }.tag(5)
                DisplayTab(s: $draft).tabItem { Label(L("Zobrazení"), systemImage: "paintpalette") }.tag(6)
                APITab(s: $draft).tabItem { Label(L("API a log"), systemImage: "network") }.tag(7)
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
    var body: some View {
        Form {
            Section {
                Picker(L("Ovládání"), selection: $s.rig.type) {
                    Text(L("Žádné")).tag(RigType.none); Text("hamlib rigctld").tag(RigType.hamlib); Text("flrig").tag(RigType.flrig)
                }
                Group {
                    TextField(L("Adresa"), text: $s.rig.host)
                    TextField(L("Port"), value: $s.rig.port, format: .number.grouping(.never),
                              prompt: Text(s.rig.type == .flrig ? "12345" : "4532"))
                }
                .disabled(s.rig.type == .none)
            } header: { Text("Rig (CAT)") } footer: {
                Text(L("hamlib: spusťte např. „rigctld -m <model> -r /dev/cu.X -s <baud>“. flrig: stačí spuštěný flrig. Prázdný port = výchozí."))
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
            } header: { Text("Log") } footer: { Text(L("Spojení (JSONL + ADIF) a série QTC se ukládají do tohoto adresáře.")) }
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
            } header: { Text(L("Spektrum a vodopád")) } footer: { Text(L("Rozsah a zesílení jdou měnit i v menu v levém horním rohu spektra.")) }
            Section(L("Text")) {
                LabeledContent(L("Velikost písma")) {
                    HStack(spacing: 4) {
                        Text("\(Int(s.display.fontSize)) pt").monospacedDigit()
                        Stepper("", value: $s.display.fontSize, in: 9...32).labelsHidden()
                    }
                }
                Toggle(L("Časové značky UTC při přepnutí TX/RX"), isOn: $s.display.timestamps)
            }
        }
        .formStyle(.grouped)
    }
}
