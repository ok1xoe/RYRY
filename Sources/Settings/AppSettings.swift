// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AudioIO
import Engine
import Foundation
import Localization
import Keying
import ModemKit

public struct Station: Codable, Sendable, Equatable {
    public var call = "", locator = "", name = "", qth = ""
    public init() {}
    enum CodingKeys: String, CodingKey { case call, locator, name, qth }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "station", x = Station()
        call = c.tolerant(.call, x.call, w, s); locator = c.tolerant(.locator, x.locator, w, s)
        name = c.tolerant(.name, x.name, w, s); qth = c.tolerant(.qth, x.qth, w, s)
    }
}

public struct AudioSettings: Codable, Sendable, Equatable {
    public var inputUID: String?, outputUID: String?
    public var inputChannel: AudioChannel = .left, outputChannel: AudioChannel = .mono
    public var outputGain: Float = 1.0
    public init() {}
    enum CodingKeys: String, CodingKey { case inputUID, outputUID, inputChannel, outputChannel, outputGain }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "audio", x = AudioSettings()
        inputUID = c.tolerant(.inputUID, x.inputUID, w, s); outputUID = c.tolerant(.outputUID, x.outputUID, w, s)
        inputChannel = c.tolerant(.inputChannel, x.inputChannel, w, s)
        outputChannel = c.tolerant(.outputChannel, x.outputChannel, w, s)
        outputGain = c.tolerant(.outputGain, x.outputGain, w, s)
    }
}

public struct PTTSettings: Codable, Sendable, Equatable {
    public var method: PTTMethod = .none
    public var port: String?
    public var invert = false
    public var txDelayMs = 0, pttTailMs = 200, pttTimeoutS = 600
    public init() {}
    enum CodingKeys: String, CodingKey { case method, port, invert, txDelayMs, pttTailMs, pttTimeoutS }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "ptt", x = PTTSettings()
        method = c.tolerant(.method, x.method, w, s); port = c.tolerant(.port, x.port, w, s)
        invert = c.tolerant(.invert, x.invert, w, s); txDelayMs = c.tolerant(.txDelayMs, x.txDelayMs, w, s)
        pttTailMs = c.tolerant(.pttTailMs, x.pttTailMs, w, s); pttTimeoutS = c.tolerant(.pttTimeoutS, x.pttTimeoutS, w, s)
    }
}

public enum FSKOutputKind: String, Codable, Sendable, CaseIterable { case afsk, fskUART, fskSoft }

public struct FSKSettings: Codable, Sendable, Equatable {
    public var output: FSKOutputKind = .afsk
    public var port: String?
    public var line: FSKLine = .dtr
    public var invert = false
    public var audioDuringFSK = false
    public init() {}
    enum CodingKeys: String, CodingKey { case output, port, line, invert, audioDuringFSK }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "fsk", x = FSKSettings()
        output = c.tolerant(.output, x.output, w, s); port = c.tolerant(.port, x.port, w, s)
        line = c.tolerant(.line, x.line, w, s); invert = c.tolerant(.invert, x.invert, w, s)
        audioDuringFSK = c.tolerant(.audioDuringFSK, x.audioDuringFSK, w, s)
    }
}

/// hamlib/flrig přes síť, vestavěný CAT přes USB sériový port, nebo hamlib spuštěný aplikací.
public enum RigType: String, Codable, Sendable, CaseIterable { case none, hamlib, flrig, cat, hamlibManaged }
/// Protokol vestavěného CAT.
public enum CATKind: String, Codable, Sendable, CaseIterable { case icom, yaesu, kenwood, elecraft }

public struct RigSettings: Codable, Sendable, Equatable {
    public var type: RigType = .none
    public var host = "127.0.0.1"
    public var port: Int?                     // nil = výchozí (4532 / 12345)
    /// CAT přes USB (vestavěný i hamlib spuštěný aplikací): sériový port a rychlost.
    public var serialPort = ""
    public var baud = 19200
    public var stopBits = 1
    public var catProtocol = CATKind.icom
    /// Adresa CI-V rádia Icom (IC-7300 = 94h).
    public var civAddress = 0x94
    /// Číslo modelu hamlib (`rigctld -l`), 1 = Dummy.
    public var hamlibModel = 1
    /// RTS na portu CAT zapnuté (nil = podle protokolu: Yaesu ano – menu „CAT RTS“).
    public var catRTS: Bool?
    public var effectiveCatRTS: Bool { catRTS ?? (catProtocol == .yaesu) }
    public init() {}
    public var effectivePort: Int { port ?? (type == .flrig ? 12345 : 4532) }
    public static let baudRates = [4800, 9600, 19200, 38400, 57600, 115200]
    /// Výchozí adresy CI-V běžných rádií Icom.
    public static let icomAddresses: [(String, Int)] = [("IC-7300", 0x94), ("IC-7610", 0x98), ("IC-705", 0xA4), ("IC-9700", 0xA2),
                                                        ("IC-7100", 0x88), ("IC-7851", 0x8E), ("IC-7600", 0x7A), ("IC-7000", 0x70),
                                                        ("IC-7410", 0x80), ("IC-718", 0x5E), ("IC-7300MK2", 0xB6)]
    enum CodingKeys: String, CodingKey { case type, host, port, serialPort, baud, stopBits, catProtocol, civAddress, hamlibModel, catRTS }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "rig", x = RigSettings()
        type = c.tolerant(.type, x.type, w, s); host = c.tolerant(.host, x.host, w, s); port = c.tolerant(.port, x.port, w, s)
        serialPort = c.tolerant(.serialPort, x.serialPort, w, s)
        let b = c.tolerant(.baud, x.baud, w, s); baud = (300...1_000_000).contains(b) ? b : x.baud
        let sb = c.tolerant(.stopBits, x.stopBits, w, s); stopBits = (1...2).contains(sb) ? sb : x.stopBits
        catProtocol = c.tolerant(.catProtocol, x.catProtocol, w, s)
        let a = c.tolerant(.civAddress, x.civAddress, w, s); civAddress = (1...0xDF).contains(a) ? a : x.civAddress
        let m = c.tolerant(.hamlibModel, x.hamlibModel, w, s); hamlibModel = m > 0 ? m : x.hamlibModel
        catRTS = c.tolerant(.catRTS, x.catRTS, w, s)
    }
}

public struct APISettings: Codable, Sendable, Equatable {
    public var fldigiEnabled = true, fldigiPort = 7362
    public var jsonRPCEnabled = true, jsonRPCPort = 7363
    public var allowRemote = false            // false = jen 127.0.0.1
    public init() {}
    enum CodingKeys: String, CodingKey { case fldigiEnabled, fldigiPort, jsonRPCEnabled, jsonRPCPort, allowRemote }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "api", x = APISettings()
        fldigiEnabled = c.tolerant(.fldigiEnabled, x.fldigiEnabled, w, s); fldigiPort = c.tolerant(.fldigiPort, x.fldigiPort, w, s)
        jsonRPCEnabled = c.tolerant(.jsonRPCEnabled, x.jsonRPCEnabled, w, s); jsonRPCPort = c.tolerant(.jsonRPCPort, x.jsonRPCPort, w, s)
        allowRemote = c.tolerant(.allowRemote, x.allowRemote, w, s)
    }
}

public enum CallbookKind: String, Codable, Sendable, CaseIterable { case none, qrz, hamqth }

/// Vyhledání značky v callbooku (QRZ.com / HamQTH). Heslo je v Klíčence, ne tady.
public struct CallbookSettings: Codable, Sendable, Equatable {
    public var service: CallbookKind = .none
    public var username = ""
    public var autoLookup = true
    public var fillEmptyOnly = true
    public init() {}
    enum CodingKeys: String, CodingKey { case service, username, autoLookup, fillEmptyOnly }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "callbook", x = CallbookSettings()
        service = c.tolerant(.service, x.service, w, s); username = c.tolerant(.username, x.username, w, s)
        autoLookup = c.tolerant(.autoLookup, x.autoLookup, w, s); fillEmptyOnly = c.tolerant(.fillEmptyOnly, x.fillEmptyOnly, w, s)
    }
}

public struct Macro: Codable, Sendable, Equatable, TolerantFallback {
    public var name: String
    public var text: String
    public var repeatSeconds: Double?
    /// Barva tlačítka `#RRGGBB` (MMTTY: barva tlačítka makra); nil = výchozí.
    public var color: String?
    public init(name: String, text: String, repeatSeconds: Double? = nil, color: String? = nil) {
        self.name = name; self.text = text; self.repeatSeconds = repeatSeconds; self.color = Self.validColor(color)
    }
    static var fallback: Macro { Macro(name: "", text: "") }
    /// Jen `#RRGGBB`, jinak nil.
    public static func validColor(_ c: String?) -> String? {
        guard let c, c.count == 7, c.first == "#", c.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return c.uppercased()
    }
    enum CodingKeys: String, CodingKey { case name, text, repeatSeconds, color }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "macro"
        name = c.tolerant(.name, "", w, s); text = c.tolerant(.text, "", w, s)
        repeatSeconds = c.tolerant(.repeatSeconds, nil, w, s)
        color = Self.validColor(c.tolerant(.color, nil, w, s))
    }
}

public struct LogSettings: Codable, Sendable, Equatable {
    public var directory: String = NSHomeDirectory() + "/Documents/mmtty4mac"
    /// Název logu (soubory `<název>.jsonl`, `<název>.adi`).
    public var name = "mmtty4mac"
    /// Naposledy otevřené logy (cesty k ADIF), nejnovější první.
    public var recent: [String] = []
    public static let recentLimit = 8
    public mutating func remember(_ path: String) {
        recent.removeAll { $0 == path }
        recent.insert(path, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
    }
    static func validName(_ n: String) -> Bool {
        !n.isEmpty && n.count <= 200 && !n.contains("/") && !n.contains(":") && !n.hasPrefix(".")
    }
    /// Průběžný záznam přijatého textu do `<directory>/rx/rx-YYYY-MM-DD.txt` (MMTTY „Log Rx file“).
    public var rxText = false
    /// Časová značka UTC na začátku řádku záznamu příjmu.
    public var rxTimestamps = true
    public init() {}
    public var rxDirectory: URL { URL(fileURLWithPath: directory).appendingPathComponent("rx") }
    enum CodingKeys: String, CodingKey { case directory, name, recent, rxText, rxTimestamps }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), x = LogSettings()
        directory = c.tolerant(.directory, x.directory, d.warningSink, "log")
        let n = c.tolerant(.name, x.name, d.warningSink, "log"); name = Self.validName(n) ? n : x.name
        recent = Array(c.tolerant(.recent, TolerantArray<String>(), d.warningSink, "log").items.prefix(Self.recentLimit))
        rxText = c.tolerant(.rxText, x.rxText, d.warningSink, "log")
        rxTimestamps = c.tolerant(.rxTimestamps, x.rxTimestamps, d.warningSink, "log")
    }
}

/// Korekce hodin zvukové karty v ppm (MMTTY „Clock“/„TX offset“).
public struct ClockSettings: Codable, Sendable, Equatable {
    public var rxPPM = 0.0, txPPM = 0.0
    public init() {}
    public static let limit = 20_000.0                 // jádro přijme ± 2 %
    public var clampedRx: Double { min(Self.limit, max(-Self.limit, rxPPM.isFinite ? rxPPM : 0)) }
    public var clampedTx: Double { min(Self.limit, max(-Self.limit, txPPM.isFinite ? txPPM : 0)) }
    enum CodingKeys: String, CodingKey { case rxPPM, txPPM }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "clock", x = ClockSettings()
        rxPPM = c.tolerant(.rxPPM, x.rxPPM, w, s); txPPM = c.tolerant(.txPPM, x.txPPM, w, s)
    }
}

/// Nastavení jádra RTTY, která vyžadují restart modemu (MMTTY sys.m_CodeSet, m_dblsft, m_txuos).
public struct RTTYCoreSettings: Codable, Sendable, Equatable {
    public var japanese = false            // J-BELL místo US (S-BELL)
    public var doubleShift = false         // LTRS/FIGS posílat 2×
    public var txUOS = true                // unshift on space při vysílání
    public init() {}
    enum CodingKeys: String, CodingKey { case japanese, doubleShift, txUOS }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "rttyCore", x = RTTYCoreSettings()
        japanese = c.tolerant(.japanese, x.japanese, w, s); doubleShift = c.tolerant(.doubleShift, x.doubleShift, w, s)
        txUOS = c.tolerant(.txUOS, x.txUOS, w, s)
    }
}

/// Závodní formát (MMTTY Log m_Contest): ON = RST + číslo, CQ/RJ = zóna + QTH, BARTG = číslo + čas UTC,
/// PED = klik na slovo vždy vyplní značku, bez čísel. WAE = RST + číslo a výměna QTC (WAE DX Contest).
/// ZONE = RST + CQ zóna (OK DX RTTY Contest).
public enum ContestFormat: String, Codable, Sendable, CaseIterable { case serial, cqrj, bartg, ped, wae, zone }

/// Předvolby známých RTTY závodů (název pro Cabrillo, formát, začátek) – v pořadí kalendářního roku.
/// Termíny podle obvyklých pravidel; přesné datum je třeba ověřit v pravidlech závodu.
public enum ContestPreset: String, CaseIterable, Codable, Sendable {
    case arrlRoundup, cqwpxRTTY, bartgHF, sartgRTTY, cqwwRTTY, makrothen, jartsRTTY, waeRTTY, okDXRTTY
    public var title: String {
        switch self {
        case .arrlRoundup: return "ARRL RTTY Roundup"
        case .cqwpxRTTY: return "CQ WPX RTTY"
        case .bartgHF: return "BARTG HF RTTY"
        case .sartgRTTY: return "SARTG WW RTTY"
        case .cqwwRTTY: return "CQ WW RTTY"
        case .makrothen: return "Makrothen RTTY"
        case .jartsRTTY: return "JARTS WW RTTY"
        case .waeRTTY: return "WAE DX Contest RTTY"
        case .okDXRTTY: return "OK DX RTTY Contest"
        }
    }
    /// CONTEST: v Cabrillu.
    public var cabrilloName: String {
        switch self {
        case .arrlRoundup: return "ARRL-RTTY"
        case .cqwpxRTTY: return "CQ-WPX-RTTY"
        case .bartgHF: return "BARTG-RTTY"
        case .sartgRTTY: return "SARTG-RTTY"
        case .cqwwRTTY: return "CQ-WW-RTTY"
        case .makrothen: return "MAKROTHEN-RTTY"
        case .jartsRTTY: return "JARTS-WW-RTTY"
        case .waeRTTY: return "WAEDC"
        case .okDXRTTY: return "OK-DX-RTTY"
        }
    }
    public var format: ContestFormat {
        switch self {
        case .cqwwRTTY: return .cqrj
        case .bartgHF: return .bartg
        case .waeRTTY: return .wae
        case .okDXRTTY: return .zone
        case .arrlRoundup, .cqwpxRTTY, .sartgRTTY, .makrothen, .jartsRTTY: return .serial
        }
    }
    /// Termín: měsíc, kolikátý celý víkend (0 = poslední) a hodina začátku v sobotu (UTC).
    var schedule: (month: Int, weekend: Int, hour: Int) {
        switch self {
        case .arrlRoundup: return (1, 1, 18)
        case .cqwpxRTTY: return (2, 2, 0)
        case .bartgHF: return (3, 3, 2)
        case .sartgRTTY: return (8, 3, 0)
        case .cqwwRTTY: return (9, 0, 0)
        case .makrothen: return (10, 2, 0)
        case .jartsRTTY: return (10, 3, 0)
        case .waeRTTY: return (11, 2, 0)
        case .okDXRTTY: return (12, 3, 0)
        }
    }
    /// Termín a výměna jedním řádkem (pro nabídku a popisek v Nastavení).
    public var summary: String {
        switch self {
        case .arrlRoundup: return L("1. celý víkend v lednu · RST + číslo (W/VE stát)")
        case .cqwpxRTTY: return L("2. celý víkend v únoru · RST + číslo")
        case .bartgHF: return L("3. celý víkend v březnu · RST + číslo + čas")
        case .sartgRTTY: return L("3. celý víkend v srpnu · RST + číslo, tři etapy")
        case .cqwwRTTY: return L("poslední celý víkend v září · RST + CQ zóna (W/VE + stát)")
        case .makrothen: return L("2. celý víkend v říjnu · RST + lokátor (4 znaky), tři etapy")
        case .jartsRTTY: return L("3. celý víkend v říjnu · RST + věk operátora (YL 00)")
        case .waeRTTY: return L("2. celý víkend v listopadu · RST + číslo, QTC")
        case .okDXRTTY: return L("3. celý víkend v prosinci · RST + CQ zóna")
        }
    }
    /// Předvolba odpovídající nastavení (podle názvu a formátu); nil = vlastní nastavení.
    public static func matching(_ c: ContestSettings) -> ContestPreset? {
        allCases.first { $0.cabrilloName == c.name && $0.format == c.format }
    }
}

/// Závodní režim: pořadová čísla a hlavička Cabrillo.
public struct ContestSettings: Codable, Sendable, Equatable {
    public var enabled = false
    public var format: ContestFormat = .serial
    public var name = ""                   // CONTEST: v Cabrillu
    public var category = ""               // CATEGORY-… (volný text, jeden řádek na „;“)
    public var nextSerial = 1
    public var exchange = ""               // odesílaná výměna místo čísla (prázdné = pořadové číslo)
    /// Začátek závodu (UTC) – QTC (WAE) počítá jen spojení a série od tohoto okamžiku; nil = posledních 72 h.
    public var start: Date?
    /// Zvolená předvolba; nil = vlastní nastavení.
    public var preset: ContestPreset?
    public init() {}
    /// Předvolba platná pro UI: jen dokud formát odpovídá předvolbě.
    public var selectedPreset: ContestPreset? { preset.flatMap { $0.format == format ? $0 : nil } }
    public var effectiveStart: Date { start ?? Date().addingTimeInterval(-72 * 3600) }

    /// Nastavení podle předvolby závodu v daném roce. `locator` = vlastní lokátor (výměna Makrothenu).
    public static func preset(_ p: ContestPreset, year: Int, locator: String = "") -> ContestSettings {
        var c = ContestSettings()
        c.enabled = true; c.nextSerial = 1
        c.name = p.cabrilloName; c.format = p.format; c.preset = p
        if p == .makrothen { c.exchange = String(locator.uppercased().prefix(4)) }
        let s = p.schedule
        c.start = fullWeekendSaturday(year: year, month: s.month, n: s.weekend)
            .map { $0.addingTimeInterval(Double(s.hour) * 3600) }
        return c
    }

    /// Nejbližší termín: letošní, pokud ještě neskončil (začátek + 48 h), jinak příští rok.
    public static func upcoming(_ p: ContestPreset, now: Date = Date(), locator: String = "") -> ContestSettings {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let y = cal.component(.year, from: now)
        let c = preset(p, year: y, locator: locator)
        if let st = c.start, st.addingTimeInterval(48 * 3600) > now { return c }
        return preset(p, year: y + 1, locator: locator)
    }

    /// Sobota n-tého celého víkendu (sobota i neděle v měsíci), 00:00 UTC; n = 0 → poslední celý víkend.
    static func fullWeekendSaturday(year: Int, month: Int, n: Int) -> Date? {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        var found: [Date] = []
        for day in 1...31 {
            guard let d = cal.date(from: DateComponents(year: year, month: month, day: day)),
                  cal.component(.month, from: d) == month, cal.component(.weekday, from: d) == 7 else { continue }
            guard let sun = cal.date(byAdding: .day, value: 1, to: d), cal.component(.month, from: sun) == month else { continue }
            found.append(d)
        }
        if n == 0 { return found.last }
        return found.count >= n ? found[n - 1] : nil
    }
    /// Formát posílá pořadové číslo (ON bez pevné výměny, BARTG).
    public var sendsSerial: Bool { format == .bartg || format == .wae || (format == .serial && exchange.isEmpty) }
    /// Formát, kde se zóna protistanice předvyplní z DXCC.
    public var prefillsZone: Bool { format == .zone }
    /// Formát, kde se bez vyplněné výměny posílá moje CQ zóna z DXCC (OK DX RTTY, CQ WW RTTY).
    public var sendsOwnZone: Bool { format == .zone || format == .cqrj }
    enum CodingKeys: String, CodingKey { case enabled, format, name, category, nextSerial, exchange, start, preset }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "contest", x = ContestSettings()
        enabled = c.tolerant(.enabled, x.enabled, w, s); format = c.tolerant(.format, x.format, w, s)
        name = c.tolerant(.name, x.name, w, s)
        category = c.tolerant(.category, x.category, w, s); nextSerial = max(1, c.tolerant(.nextSerial, x.nextSerial, w, s))
        exchange = c.tolerant(.exchange, x.exchange, w, s)
        start = c.tolerant(.start, x.start, w, s)
        // starší soubor bez pole preset: odvodit z názvu a formátu
        preset = c.contains(.preset) ? c.tolerant(.preset, x.preset, w, s) : ContestPreset.matching(self)
    }
    /// preset se zapisuje i jako null – „vlastní“ se tak odliší od starého souboru bez tohoto pole.
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled); try c.encode(format, forKey: .format); try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category); try c.encode(nextSerial, forKey: .nextSerial)
        try c.encode(exchange, forKey: .exchange); try c.encodeIfPresent(start, forKey: .start)
        try c.encode(preset, forKey: .preset)
    }
}

/// Zobrazení: rozsah a zesílení spektra/vodopádu, písmo, časové značky.
public struct DisplaySettings: Codable, Sendable, Equatable {
    public var fromHz = 0.0, toHz = 3000.0
    public var gainDB = 0.0
    public var autoGain = true
    public var timestamps = false
    public var fontSize = 14.0
    /// Písmo oken RX a TX (název rodiny; prázdné = systémové neproporcionální).
    public var rxFont = ""
    /// Barvy oken (#RRGGBB; nil = systémové): pozadí a text příjmu, echo vysílání, pozadí a text vysílání.
    public var rxBackground: String?, rxTextColor: String?, rxEchoColor: String?
    public var txBackground: String?, txTextColor: String?
    public var palette = WaterfallPalette.classic
    public var fftResponse = FFTResponse.normal
    public var xySize = XYScopeSize.medium
    public var xyQuality = XYScopeQuality.high
    /// Bublinová nápověda tlačítek (MMTTY „Show Button Hint“).
    public var showHints = true
    public init() {}
    /// FFT jádra pokrývá 0–4000 Hz (TSound m_FFTWINDOW).
    public static let maxHz = 4000.0
    enum CodingKeys: String, CodingKey { case fromHz, toHz, gainDB, autoGain, timestamps, fontSize, rxFont, rxBackground,
                                             rxTextColor, rxEchoColor, txBackground, txTextColor, palette, fftResponse,
                                             xySize, xyQuality, showHints }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "display", x = DisplaySettings()
        fromHz = c.tolerant(.fromHz, x.fromHz, w, s); toHz = c.tolerant(.toHz, x.toHz, w, s)
        if !(fromHz >= 0 && toHz <= Self.maxHz && toHz - fromHz >= 200) { fromHz = x.fromHz; toHz = x.toHz }
        gainDB = min(30, max(-30, c.tolerant(.gainDB, x.gainDB, w, s)))
        autoGain = c.tolerant(.autoGain, x.autoGain, w, s); timestamps = c.tolerant(.timestamps, x.timestamps, w, s)
        fontSize = min(40, max(8, c.tolerant(.fontSize, x.fontSize, w, s)))
        rxFont = c.tolerant(.rxFont, x.rxFont, w, s)
        rxBackground = Macro.validColor(c.tolerant(.rxBackground, nil, w, s))
        rxTextColor = Macro.validColor(c.tolerant(.rxTextColor, nil, w, s))
        rxEchoColor = Macro.validColor(c.tolerant(.rxEchoColor, nil, w, s))
        txBackground = Macro.validColor(c.tolerant(.txBackground, nil, w, s))
        txTextColor = Macro.validColor(c.tolerant(.txTextColor, nil, w, s))
        palette = c.tolerant(.palette, x.palette, w, s); fftResponse = c.tolerant(.fftResponse, x.fftResponse, w, s)
        xySize = c.tolerant(.xySize, x.xySize, w, s); xyQuality = c.tolerant(.xyQuality, x.xyQuality, w, s)
        showHints = c.tolerant(.showHints, x.showHints, w, s)
    }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var station = Station()
    public var audio = AudioSettings()
    public var ptt = PTTSettings()
    public var fsk = FSKSettings()
    public var rig = RigSettings()
    public var api = APISettings()
    public var callbook = CallbookSettings()
    public var rtty: [String: ParameterValue] = [:]
    public var macros: [Macro] = AppSettings.defaultMacros
    public var log = LogSettings()
    public var clock = ClockSettings()
    public var rttyCore = RTTYCoreSettings()
    public var contest = ContestSettings()
    public var display = DisplaySettings()
    /// Seznam zpráv (MMTTY MsgList): pojmenované delší texty se syntaxí maker.
    public var messages: [Macro] = AppSettings.defaultMessages
    public var txWindow = TxWindowSettings()
    /// Vlastní klávesové zkratky (id příkazu → zkratka); chybějící = výchozí.
    public var shortcuts: [String: KeyBinding] = [:]
    public init() {}
    public static let macroCount = 16

    public static let defaultMacros: [Macro] = [
        Macro(name: "CQ", text: "\r\nCQ CQ CQ DE %m %m %m PSE K\r\n\\"),
        Macro(name: "Answer", text: "\r\n%c %c DE %m %m %m K\r\n\\"),
        Macro(name: "Report", text: "\r\n%c DE %m %g TNX FER CALL UR RST %r %r NAME %n\r\nHW? %c DE %m KN\r\n\\"),
        Macro(name: "Contest", text: "\r\n%c 599 %N %N %c\r\n\\"),
        Macro(name: "TU", text: "\r\nTU %c DE %m QRZ?\r\n%l\\"),
        Macro(name: "73", text: "\r\n%c DE %m TNX FER QSO 73 73 %c DE %m SK\r\n%l\\"),
        Macro(name: "QRZ", text: "\r\nQRZ? DE %m K\r\n\\"),
        Macro(name: "BTU", text: "\r\nBTU %c DE %m KN\r\n\\"),
        Macro(name: "RYRY", text: "RYRYRYRYRYRYRYRYRYRY\r\n#"),
        Macro(name: "CW ID", text: "%{DE %m}\\"),
        Macro(name: "AGN", text: "\r\nAGN? AGN?\r\n\\"),
        Macro(name: "NR?", text: "\r\nNR? NR?\r\n\\"),
        Macro(name: "Test CQ", text: "\r\nCQ TEST CQ TEST DE %m %m TEST\r\n\\"),
        Macro(name: "Exch", text: "\r\n%c 599 %N %N\r\n\\"),
        Macro(name: "", text: ""),
        Macro(name: "", text: ""),
    ]

    enum CodingKeys: String, CodingKey { case schemaVersion, station, audio, ptt, fsk, rig, api, callbook, rtty, macros, log,
                                             clock, rttyCore, contest, display, messages, txWindow, shortcuts }

    /// Výchozí zprávy podle MMTTY (sys.m_MsgList), bez údajů autora.
    public static let defaultMessages: [Macro] = [
        Macro(name: "Stanice", text: "\r\nRGR %c DE %m  %g DEAR %n\r\nTHANK YOU FOR THE NICE REPORT.\r\nUR RST %r %r %r\r\nMY NAME IS ...\r\nRIG IS ... ANT IS ...\r\nHOW COPY? BTU %c DE %m KN\r\n\\"),
        Macro(name: "Final", text: "\r\nOK DEAR %n\r\nMANY THANKS FOR THE NICE QSO.\r\nQSL VIA BURO. CUL AND BEST 73\r\n%c DE %m TU SK SK\r\n%l\\"),
        Macro(name: "Final 2", text: "\r\nTNX AGAIN DEAR %n CU SK\r\n\\"),
    ]
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "settings", x = AppSettings()
        schemaVersion = c.tolerant(.schemaVersion, x.schemaVersion, w, s)
        station = c.tolerant(.station, x.station, w, s); audio = c.tolerant(.audio, x.audio, w, s)
        ptt = c.tolerant(.ptt, x.ptt, w, s); fsk = c.tolerant(.fsk, x.fsk, w, s)
        rig = c.tolerant(.rig, x.rig, w, s); api = c.tolerant(.api, x.api, w, s)
        callbook = c.tolerant(.callbook, x.callbook, w, s)
        rtty = c.tolerant(.rtty, TolerantDict<ParameterValue>(), w, s).items
        macros = c.contains(.macros) ? c.tolerant(.macros, TolerantArray<Macro>(), w, s).items : x.macros
        // dřívější výchozí závodní makro mělo %M (v MMTTY přijaté číslo) místo %N (odesílané)
        for i in macros.indices where macros[i].text == "\r\n%c 599 %M %M %c\r\n\\" {
            macros[i].text = "\r\n%c 599 %N %N %c\r\n\\"
        }
        // starší nastavení s 12 makry (nebo zkrácený seznam) doplnit na 16 prázdnými
        while macros.count < Self.macroCount { macros.append(Macro(name: "", text: "")) }
        log = c.tolerant(.log, x.log, w, s)
        clock = c.tolerant(.clock, x.clock, w, s); rttyCore = c.tolerant(.rttyCore, x.rttyCore, w, s)
        contest = c.tolerant(.contest, x.contest, w, s); display = c.tolerant(.display, x.display, w, s)
        messages = c.contains(.messages) ? c.tolerant(.messages, TolerantArray<Macro>(), w, s).items : x.messages
        txWindow = c.tolerant(.txWindow, x.txWindow, w, s)
        shortcuts = c.tolerant(.shortcuts, TolerantDict<KeyBinding>(), w, s).items.filter { $0.value.isValid }
    }

    /// Konfigurace Engine z nastavení.
    public func engineConfig() -> EngineConfig {
        var e = EngineConfig()
        e.audio.inputUID = audio.inputUID; e.audio.outputUID = audio.outputUID
        e.audio.inputChannel = audio.inputChannel; e.audio.outputChannel = audio.outputChannel
        e.audio.outputGain = audio.outputGain
        e.ptt = ptt.method; e.pttPort = ptt.port; e.pttInvert = ptt.invert
        e.txDelay = .milliseconds(min(max(0, ptt.txDelayMs), 10_000))
        e.pttTail = .milliseconds(min(max(0, ptt.pttTailMs), 10_000))
        e.pttTimeout = .seconds(min(max(1, ptt.pttTimeoutS), 86_400))
        switch (fsk.output, fsk.port) {
        case (.fskUART, let p?): e.txOutput = .fskUART(path: p)
        case (.fskSoft, let p?): e.txOutput = .fskSoft(path: p, line: fsk.line)
        default: e.txOutput = .afsk
        }
        e.fskInvert = fsk.invert; e.audioDuringFSK = fsk.audioDuringFSK
        return e
    }
}
