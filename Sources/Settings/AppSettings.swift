// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AudioIO
import Engine
import Foundation
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

public enum RigType: String, Codable, Sendable, CaseIterable { case none, hamlib, flrig }

public struct RigSettings: Codable, Sendable, Equatable {
    public var type: RigType = .none
    public var host = "127.0.0.1"
    public var port: Int?                     // nil = výchozí (4532 / 12345)
    public init() {}
    public var effectivePort: Int { port ?? (type == .flrig ? 12345 : 4532) }
    enum CodingKeys: String, CodingKey { case type, host, port }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "rig", x = RigSettings()
        type = c.tolerant(.type, x.type, w, s); host = c.tolerant(.host, x.host, w, s); port = c.tolerant(.port, x.port, w, s)
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

public struct Macro: Codable, Sendable, Equatable, TolerantFallback {
    public var name: String
    public var text: String
    public var repeatSeconds: Double?
    public init(name: String, text: String, repeatSeconds: Double? = nil) {
        self.name = name; self.text = text; self.repeatSeconds = repeatSeconds
    }
    static var fallback: Macro { Macro(name: "", text: "") }
    enum CodingKeys: String, CodingKey { case name, text, repeatSeconds }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "macro"
        name = c.tolerant(.name, "", w, s); text = c.tolerant(.text, "", w, s)
        repeatSeconds = c.tolerant(.repeatSeconds, nil, w, s)
    }
}

public struct LogSettings: Codable, Sendable, Equatable {
    public var directory: String = NSHomeDirectory() + "/Documents/mmtty4mac"
    public init() {}
    enum CodingKeys: String, CodingKey { case directory }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        directory = c.tolerant(.directory, LogSettings().directory, d.warningSink, "log")
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

/// Závodní režim: pořadová čísla a hlavička Cabrillo.
public struct ContestSettings: Codable, Sendable, Equatable {
    public var enabled = false
    public var name = ""                   // CONTEST: v Cabrillu
    public var category = ""               // CATEGORY-… (volný text, jeden řádek na „;“)
    public var nextSerial = 1
    public var exchange = ""               // odesílaná výměna místo čísla (prázdné = pořadové číslo)
    public init() {}
    enum CodingKeys: String, CodingKey { case enabled, name, category, nextSerial, exchange }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "contest", x = ContestSettings()
        enabled = c.tolerant(.enabled, x.enabled, w, s); name = c.tolerant(.name, x.name, w, s)
        category = c.tolerant(.category, x.category, w, s); nextSerial = max(1, c.tolerant(.nextSerial, x.nextSerial, w, s))
        exchange = c.tolerant(.exchange, x.exchange, w, s)
    }
}

/// Zobrazení: rozsah a zesílení spektra/vodopádu, písmo, časové značky.
public struct DisplaySettings: Codable, Sendable, Equatable {
    public var fromHz = 0.0, toHz = 3000.0
    public var gainDB = 0.0
    public var autoGain = true
    public var timestamps = false
    public var fontSize = 14.0
    public init() {}
    /// FFT jádra pokrývá 0–4000 Hz (TSound m_FFTWINDOW).
    public static let maxHz = 4000.0
    enum CodingKeys: String, CodingKey { case fromHz, toHz, gainDB, autoGain, timestamps, fontSize }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "display", x = DisplaySettings()
        fromHz = c.tolerant(.fromHz, x.fromHz, w, s); toHz = c.tolerant(.toHz, x.toHz, w, s)
        if !(fromHz >= 0 && toHz <= Self.maxHz && toHz - fromHz >= 200) { fromHz = x.fromHz; toHz = x.toHz }
        gainDB = min(30, max(-30, c.tolerant(.gainDB, x.gainDB, w, s)))
        autoGain = c.tolerant(.autoGain, x.autoGain, w, s); timestamps = c.tolerant(.timestamps, x.timestamps, w, s)
        fontSize = min(40, max(8, c.tolerant(.fontSize, x.fontSize, w, s)))
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
    public var rtty: [String: ParameterValue] = [:]
    public var macros: [Macro] = AppSettings.defaultMacros
    public var log = LogSettings()
    public var clock = ClockSettings()
    public var rttyCore = RTTYCoreSettings()
    public var contest = ContestSettings()
    public var display = DisplaySettings()
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

    enum CodingKeys: String, CodingKey { case schemaVersion, station, audio, ptt, fsk, rig, api, rtty, macros, log,
                                             clock, rttyCore, contest, display }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "settings", x = AppSettings()
        schemaVersion = c.tolerant(.schemaVersion, x.schemaVersion, w, s)
        station = c.tolerant(.station, x.station, w, s); audio = c.tolerant(.audio, x.audio, w, s)
        ptt = c.tolerant(.ptt, x.ptt, w, s); fsk = c.tolerant(.fsk, x.fsk, w, s)
        rig = c.tolerant(.rig, x.rig, w, s); api = c.tolerant(.api, x.api, w, s)
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
