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

/// hamlib (rigctld) or flrig over the network, or the built-in CAT over a USB serial port.
/// The App Store sandbox cannot launch rigctld, so the former `hamlibManaged` loads as `hamlib`.
public enum RigType: String, Codable, Sendable, CaseIterable { case none, hamlib, flrig, cat }
/// Protocol of the built-in CAT.
public enum CATKind: String, Codable, Sendable, CaseIterable { case icom, yaesu, kenwood, elecraft }

public struct RigSettings: Codable, Sendable, Equatable {
    public var type: RigType = .none
    public var host = "127.0.0.1"
    public var port: Int?                     // nil = default (4532 / 12345)
    /// The built-in CAT over USB: serial port and speed.
    public var serialPort = ""
    public var baud = 19200
    public var stopBits = 1
    public var catProtocol = CATKind.icom
    /// CI-V address of an Icom radio (IC-7300 = 94h).
    public var civAddress = 0x94
    /// RTS on the CAT port enabled (nil = according to the protocol: Yaesu yes – the "CAT RTS" menu).
    public var catRTS: Bool?
    public var effectiveCatRTS: Bool { catRTS ?? (catProtocol == .yaesu) }
    public init() {}
    public var effectivePort: Int { port ?? (type == .flrig ? 12345 : 4532) }
    public static let baudRates = [4800, 9600, 19200, 38400, 57600, 115200]
    /// Default CI-V addresses of common Icom radios.
    public static let icomAddresses: [(String, Int)] = [("IC-7300", 0x94), ("IC-7610", 0x98), ("IC-705", 0xA4), ("IC-9700", 0xA2),
                                                        ("IC-7100", 0x88), ("IC-7851", 0x8E), ("IC-7600", 0x7A), ("IC-7000", 0x70),
                                                        ("IC-7410", 0x80), ("IC-718", 0x5E), ("IC-7300MK2", 0xB6)]
    enum CodingKeys: String, CodingKey { case type, host, port, serialPort, baud, stopBits, catProtocol, civAddress, catRTS }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "rig", x = RigSettings()
        if (try? c.decodeIfPresent(String.self, forKey: .type)) == "hamlibManaged" {
            type = .hamlib
            w?.add(L("Spouštění rigctld aplikací už není k dispozici (App Store). Spusťte rigctld sami, RYRY se k němu připojí na 127.0.0.1:4532."))
        } else {
            type = c.tolerant(.type, x.type, w, s)
        }
        host = c.tolerant(.host, x.host, w, s); port = c.tolerant(.port, x.port, w, s)
        serialPort = c.tolerant(.serialPort, x.serialPort, w, s)
        let b = c.tolerant(.baud, x.baud, w, s); baud = (300...1_000_000).contains(b) ? b : x.baud
        let sb = c.tolerant(.stopBits, x.stopBits, w, s); stopBits = (1...2).contains(sb) ? sb : x.stopBits
        catProtocol = c.tolerant(.catProtocol, x.catProtocol, w, s)
        let a = c.tolerant(.civAddress, x.civAddress, w, s); civAddress = (1...0xDF).contains(a) ? a : x.civAddress
        catRTS = c.tolerant(.catRTS, x.catRTS, w, s)
    }
}

public struct APISettings: Codable, Sendable, Equatable {
    public var fldigiEnabled = true, fldigiPort = 7362
    public var jsonRPCEnabled = true, jsonRPCPort = 7363
    public var allowRemote = false            // false = only 127.0.0.1
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

/// Callsign lookup in a callbook (QRZ.com / HamQTH). The password is in the Keychain, not here.
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

/// Call history file (N1MM Call History): prefilling the other station's name, locator and exchange.
public struct CallHistorySettings: Codable, Sendable, Equatable {
    public var enabled = false
    public var path = ""
    /// Security-scoped bookmark of the file: in the sandbox the only way to read it again after a relaunch.
    public var bookmark: Data?
    public var fillEmptyOnly = true
    public init() {}
    enum CodingKeys: String, CodingKey { case enabled, path, bookmark, fillEmptyOnly }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "callHistory", x = CallHistorySettings()
        enabled = c.tolerant(.enabled, x.enabled, w, s); path = c.tolerant(.path, x.path, w, s)
        fillEmptyOnly = c.tolerant(.fillEmptyOnly, x.fillEmptyOnly, w, s)
        bookmark = c.tolerant(.bookmark, x.bookmark, w, s)
    }
}

public struct Macro: Codable, Sendable, Equatable, TolerantFallback {
    public var name: String
    public var text: String
    public var repeatSeconds: Double?
    /// Button color `#RRGGBB` (MMTTY: macro button color); nil = default.
    public var color: String?
    public init(name: String, text: String, repeatSeconds: Double? = nil, color: String? = nil) {
        self.name = name; self.text = text; self.repeatSeconds = Self.validRepeat(repeatSeconds); self.color = Self.validColor(color)
    }
    static var fallback: Macro { Macro(name: "", text: "") }
    /// The macro contains nothing (only whitespace) – running it would transmit nothing.
    public var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Allowed macro repeat interval (s).
    public static let repeatRange = 0.1...3600.0
    /// Repeat interval in the range 0.1–3600 s, otherwise nil (infinity, NaN, negative, huge values).
    public static func validRepeat(_ s: Double?) -> Double? {
        guard let s, s.isFinite, repeatRange.contains(s) else { return nil }
        return s
    }
    /// Only `#RRGGBB`, otherwise nil.
    public static func validColor(_ c: String?) -> String? {
        guard let c, c.count == 7, c.first == "#", c.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return c.uppercased()
    }
    enum CodingKeys: String, CodingKey { case name, text, repeatSeconds, color }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "macro"
        name = c.tolerant(.name, "", w, s); text = c.tolerant(.text, "", w, s)
        repeatSeconds = Self.validRepeat(c.tolerant(.repeatSeconds, nil, w, s))
        color = Self.validColor(c.tolerant(.color, nil, w, s))
    }
}

public struct LogSettings: Codable, Sendable, Equatable {
    public var directory: String = HomeDirectory.real + "/Documents/RYRY"
    /// Log name (the files `<name>.jsonl`, `<name>.adi`).
    public var name = "mmtty4mac"
    /// Most recently opened logs (paths to the ADIF), newest first.
    public var recent: [String] = []
    /// Access to folders outside the sandbox container (the log folder, folders of recent logs).
    public var bookmarks = FolderBookmarks()
    /// Manually entered frequency (Hz) for QSOs without a rig – remembered between runs.
    public var manualFrequency: Double?
    /// Super Check Partial (MASTER.SCP + calls from the log) under the Call field.
    public var superCheck = true
    /// Automatic daily log backup (the backup folder next to the log) and how many backups to keep.
    public var backup = true
    public var backupKeep = 10
    public static let recentLimit = 8
    public mutating func remember(_ path: String) {
        recent.removeAll { $0 == path }
        recent.insert(path, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
    }
    static func validName(_ n: String) -> Bool {
        !n.isEmpty && n.count <= 200 && !n.contains("/") && !n.contains(":") && !n.hasPrefix(".")
    }
    /// Continuous recording of the received text into `<directory>/rx/rx-YYYY-MM-DD.txt` (MMTTY "Log Rx file").
    public var rxText = false
    /// UTC timestamp at the start of a line of the receive log.
    public var rxTimestamps = true
    public init() {}
    public var rxDirectory: URL { URL(fileURLWithPath: directory).appendingPathComponent("rx") }
    enum CodingKeys: String, CodingKey { case directory, name, recent, rxText, rxTimestamps, manualFrequency, superCheck, backup,
                                             backupKeep, bookmarks }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), x = LogSettings()
        directory = c.tolerant(.directory, x.directory, d.warningSink, "log")
        let n = c.tolerant(.name, x.name, d.warningSink, "log"); name = Self.validName(n) ? n : x.name
        recent = Array(c.tolerant(.recent, TolerantArray<String>(), d.warningSink, "log").items.prefix(Self.recentLimit))
        let mf: Double? = c.tolerant(.manualFrequency, nil, d.warningSink, "log")
        manualFrequency = mf.flatMap { $0.isFinite && $0 > 10_000 && $0 < 10e9 ? $0 : nil }
        superCheck = c.tolerant(.superCheck, x.superCheck, d.warningSink, "log")
        backup = c.tolerant(.backup, x.backup, d.warningSink, "log")
        backupKeep = min(100, max(1, c.tolerant(.backupKeep, x.backupKeep, d.warningSink, "log")))
        rxText = c.tolerant(.rxText, x.rxText, d.warningSink, "log")
        rxTimestamps = c.tolerant(.rxTimestamps, x.rxTimestamps, d.warningSink, "log")
        bookmarks = c.tolerant(.bookmarks, x.bookmarks, d.warningSink, "log")
    }
}

/// Sound card clock correction in ppm (MMTTY "Clock"/"TX offset").
public struct ClockSettings: Codable, Sendable, Equatable {
    public var rxPPM = 0.0, txPPM = 0.0
    public init() {}
    public static let limit = 20_000.0                 // the core accepts ± 2 %
    public var clampedRx: Double { min(Self.limit, max(-Self.limit, rxPPM.isFinite ? rxPPM : 0)) }
    public var clampedTx: Double { min(Self.limit, max(-Self.limit, txPPM.isFinite ? txPPM : 0)) }
    enum CodingKeys: String, CodingKey { case rxPPM, txPPM }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "clock", x = ClockSettings()
        rxPPM = c.tolerant(.rxPPM, x.rxPPM, w, s); txPPM = c.tolerant(.txPPM, x.txPPM, w, s)
    }
}

/// RTTY core settings that require a modem restart (MMTTY sys.m_CodeSet, m_dblsft, m_txuos).
public struct RTTYCoreSettings: Codable, Sendable, Equatable {
    public var japanese = false            // J-BELL instead of US (S-BELL)
    public var doubleShift = false         // send LTRS/FIGS twice
    public var txUOS = true                // unshift on space when transmitting
    public init() {}
    enum CodingKeys: String, CodingKey { case japanese, doubleShift, txUOS }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "rttyCore", x = RTTYCoreSettings()
        japanese = c.tolerant(.japanese, x.japanese, w, s); doubleShift = c.tolerant(.doubleShift, x.doubleShift, w, s)
        txUOS = c.tolerant(.txUOS, x.txUOS, w, s)
    }
}

/// Additional decoders: a second decoder (a different demodulator) and multi-channel decoding.
public struct DecoderSettings: Codable, Sendable, Equatable {
    public var secondEnabled = false
    /// Demodulator of the second decoder (iir/fir/pll/fft); nil = automatically a different one from the main one.
    public var secondDemod: String?
    public var channelsEnabled = false
    public var maxChannels = 4              // 1…8
    public var channelTimeoutS = 15.0       // a channel expires after this many s without a signal
    public var showChannelMarks = true      // channel marks in the waterfall
    public init() {}
    public static let channelRange = 1...8
    public static let timeoutRange = 2.0...300.0
    enum CodingKeys: String, CodingKey { case secondEnabled, secondDemod, channelsEnabled, maxChannels, channelTimeoutS, showChannelMarks }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "decoders", x = DecoderSettings()
        secondEnabled = c.tolerant(.secondEnabled, x.secondEnabled, w, s)
        let dm: String? = c.tolerant(.secondDemod, x.secondDemod, w, s)
        secondDemod = dm.flatMap { AuxDecoderConfig.demodTypes.contains($0) ? $0 : nil }
        channelsEnabled = c.tolerant(.channelsEnabled, x.channelsEnabled, w, s)
        let n = c.tolerant(.maxChannels, x.maxChannels, w, s); maxChannels = Self.channelRange.contains(n) ? n : x.maxChannels
        let t = c.tolerant(.channelTimeoutS, x.channelTimeoutS, w, s)
        channelTimeoutS = Self.timeoutRange.contains(t) ? t : x.channelTimeoutS
        showChannelMarks = c.tolerant(.showChannelMarks, x.showChannelMarks, w, s)
    }

    /// Configuration of the additional decoders for Engine.
    public func auxConfig() -> AuxDecoderConfig {
        var a = AuxDecoderConfig()
        a.secondEnabled = secondEnabled; a.secondDemod = secondDemod
        a.channelsEnabled = channelsEnabled
        a.maxChannels = min(Self.channelRange.upperBound, max(Self.channelRange.lowerBound, maxChannels))
        a.channelTimeout = min(Self.timeoutRange.upperBound, max(Self.timeoutRange.lowerBound, channelTimeoutS.isFinite ? channelTimeoutS : 15))
        return a
    }
}

/// Contest format (MMTTY Log m_Contest): ON = RST + serial, CQ/RJ = zone + QTH, BARTG = serial + UTC time,
/// PED = a click on a word always fills the call, without serials. WAE = RST + serial and the QTC exchange (WAE DX Contest).
/// ZONE = RST + CQ zone (OK DX RTTY Contest).
public enum ContestFormat: String, Codable, Sendable, CaseIterable { case serial, cqrj, bartg, ped, wae, zone }

/// Presets of known RTTY contests (name for Cabrillo, format, start) – in calendar year order.
/// The dates follow the usual rules; the exact date needs to be verified in the contest rules.
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
    /// CONTEST: in Cabrillo.
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
    /// Date: month, which full weekend (0 = the last one) and the start hour on Saturday (UTC).
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
    /// Contest length in hours from the start according to the official rules (docs/rulings.md, "Scoring and score").
    public var durationHours: Double {
        switch self {
        case .arrlRoundup: return 30                       // Sat 18:00 – Sun 23:59
        case .sartgRTTY, .makrothen: return 40             // three legs: Sat 00–08, Sat 16–24, Sun 08–16
        case .okDXRTTY: return 24                          // Sat 00:00 – 24:00
        case .cqwpxRTTY, .bartgHF, .cqwwRTTY, .jartsRTTY, .waeRTTY: return 48   // BARTG Sat 02:00 – Mon 01:59
        }
    }
    /// Date and exchange on one line (for the menu and the label in Settings).
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
    /// The preset matching the settings (by name and format); nil = custom settings.
    public static func matching(_ c: ContestSettings) -> ContestPreset? {
        allCases.first { $0.cabrilloName == c.name && $0.format == c.format }
    }
}

/// Contest mode: serial numbers and the Cabrillo header.
public struct ContestSettings: Codable, Sendable, Equatable {
    public var enabled = false
    public var format: ContestFormat = .serial
    public var name = ""                   // CONTEST: in Cabrillo
    public var category = ""               // CATEGORY-… (free text, one line per ";")
    public var nextSerial = 1
    public var exchange = ""               // exchange sent instead of the serial (empty = serial number)
    /// Contest start (UTC) – QTC (WAE) counts only QSOs and series from this moment; nil = the last 72 h.
    public var start: Date?
    /// The selected preset; nil = custom settings.
    public var preset: ContestPreset?
    public init() {}
    /// The preset valid for the UI: only as long as the format matches the preset.
    public var selectedPreset: ContestPreset? { preset.flatMap { $0.format == format ? $0 : nil } }
    /// ARRL RTTY Roundup with serial numbers: W/VE send a state/province instead of the serial (the "State/prov. r" field).
    public var isRoundupStateExchange: Bool { enabled && format == .serial && exchange.isEmpty && selectedPreset == .arrlRoundup }
    public var effectiveStart: Date { start ?? Date().addingTimeInterval(-72 * 3600) }
    /// Contest end (start + preset length); nil = the start or the preset is unknown.
    public var end: Date? {
        guard let s = start, let p = selectedPreset else { return nil }
        return s.addingTimeInterval(p.durationHours * 3600)
    }

    /// Settings according to a contest preset in the given year. `locator` = own locator (the Makrothen exchange).
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

    /// The nearest date: this year's if it has not ended yet (start + 48 h), otherwise next year.
    public static func upcoming(_ p: ContestPreset, now: Date = Date(), locator: String = "") -> ContestSettings {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let y = cal.component(.year, from: now)
        let c = preset(p, year: y, locator: locator)
        if let st = c.start, st.addingTimeInterval(48 * 3600) > now { return c }
        return preset(p, year: y + 1, locator: locator)
    }

    /// Saturday of the n-th full weekend (both Saturday and Sunday in the month), 00:00 UTC; n = 0 → the last full weekend.
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
    /// The format sends a serial number (ON without a fixed exchange, BARTG).
    public var sendsSerial: Bool { format == .bartg || format == .wae || (format == .serial && exchange.isEmpty) }
    /// A format where the other station's zone is prefilled from DXCC.
    public var prefillsZone: Bool { format == .zone }
    /// A format where, without a filled-in exchange, my CQ zone from DXCC is sent (OK DX RTTY, CQ WW RTTY).
    public var sendsOwnZone: Bool { format == .zone || format == .cqrj }
    enum CodingKeys: String, CodingKey { case enabled, format, name, category, nextSerial, exchange, start, preset }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "contest", x = ContestSettings()
        enabled = c.tolerant(.enabled, x.enabled, w, s); format = c.tolerant(.format, x.format, w, s)
        name = c.tolerant(.name, x.name, w, s)
        category = c.tolerant(.category, x.category, w, s); nextSerial = max(1, c.tolerant(.nextSerial, x.nextSerial, w, s))
        exchange = c.tolerant(.exchange, x.exchange, w, s)
        start = c.tolerant(.start, x.start, w, s)
        // an older file without the preset field: derive it from the name and the format
        preset = c.contains(.preset) ? c.tolerant(.preset, x.preset, w, s) : ContestPreset.matching(self)
    }
    /// preset is written even as null – that is how "custom" is distinguished from an old file without this field.
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled); try c.encode(format, forKey: .format); try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category); try c.encode(nextSerial, forKey: .nextSerial)
        try c.encode(exchange, forKey: .exchange); try c.encodeIfPresent(start, forKey: .start)
        try c.encode(preset, forKey: .preset)
    }
}

/// Display: range and gain of the spectrum/waterfall, font, timestamps.
public struct DisplaySettings: Codable, Sendable, Equatable {
    public var fromHz = 0.0, toHz = 3000.0
    public var gainDB = 0.0
    public var autoGain = true
    public var timestamps = false
    public var fontSize = 14.0
    /// Font of the RX and TX windows (family name; empty = the system monospaced one).
    public var rxFont = ""
    /// Window colors (#RRGGBB; nil = system): receive background and text, transmit echo, transmit background and text.
    public var rxBackground: String?, rxTextColor: String?, rxEchoColor: String?
    public var txBackground: String?, txTextColor: String?
    public var palette = WaterfallPalette.classic
    public var fftResponse = FFTResponse.normal
    public var xySize = XYScopeSize.medium
    public var xyQuality = XYScopeQuality.high
    /// Button tooltips (MMTTY "Show Button Hint").
    public var showHints = true
    /// Highlight calls in the received text (own, dupe, in the log, new).
    public var highlightCalls = true
    public init() {}
    /// The core's FFT covers 0–4000 Hz (TSound m_FFTWINDOW).
    public static let maxHz = 4000.0
    enum CodingKeys: String, CodingKey { case fromHz, toHz, gainDB, autoGain, timestamps, fontSize, rxFont, rxBackground,
                                             rxTextColor, rxEchoColor, txBackground, txTextColor, palette, fftResponse,
                                             xySize, xyQuality, showHints, highlightCalls }
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
        highlightCalls = c.tolerant(.highlightCalls, x.highlightCalls, w, s)
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
    public var callHistory = CallHistorySettings()
    public var rtty: [String: ParameterValue] = [:]
    public var macros: [Macro] = AppSettings.defaultMacros
    public var log = LogSettings()
    public var clock = ClockSettings()
    public var rttyCore = RTTYCoreSettings()
    public var contest = ContestSettings()
    public var display = DisplaySettings()
    /// Message list (MMTTY MsgList): named longer texts with the macro syntax.
    public var messages: [Macro] = AppSettings.defaultMessages
    public var txWindow = TxWindowSettings()
    /// Custom keyboard shortcuts (command id → shortcut); missing = the default.
    public var shortcuts: [String: KeyBinding] = [:]
    /// Uploading to LoTW / eQSL / Club Log.
    public var upload = UploadSettings()
    /// DX cluster and RBN spots.
    public var spots = SpotSettings()
    public var decoders = DecoderSettings()
    /// Enter Sends Message (Run / S&P) in a contest.
    public var esm = ESMSettings()
    /// Alerts (my call, watched calls, needed countries).
    public var alerts = AlertSettings()
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
        Macro(name: "My call", text: "\r\n%m %m\r\n\\"),          // ESM S&P
        Macro(name: "", text: ""),
    ]

    enum CodingKeys: String, CodingKey { case schemaVersion, station, audio, ptt, fsk, rig, api, callbook, callHistory, rtty,
                                             macros, log, clock, rttyCore, contest, display, messages, txWindow,
                                             shortcuts, upload, spots, decoders, esm, alerts }

    /// Default messages per MMTTY (sys.m_MsgList), without the author's details.
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
        callHistory = c.tolerant(.callHistory, x.callHistory, w, s)
        rtty = c.tolerant(.rtty, TolerantDict<ParameterValue>(), w, s).items
        macros = c.contains(.macros) ? c.tolerant(.macros, TolerantArray<Macro>(), w, s).items : x.macros
        // the earlier default contest macro had %M (the received number in MMTTY) instead of %N (the sent one)
        for i in macros.indices where macros[i].text == "\r\n%c 599 %M %M %c\r\n\\" {
            macros[i].text = "\r\n%c 599 %N %N %c\r\n\\"
        }
        // pad older settings with 12 macros (or a shortened list) to 16 with empty ones
        while macros.count < Self.macroCount { macros.append(Macro(name: "", text: "")) }
        log = c.tolerant(.log, x.log, w, s)
        clock = c.tolerant(.clock, x.clock, w, s); rttyCore = c.tolerant(.rttyCore, x.rttyCore, w, s)
        contest = c.tolerant(.contest, x.contest, w, s); display = c.tolerant(.display, x.display, w, s)
        messages = c.contains(.messages) ? c.tolerant(.messages, TolerantArray<Macro>(), w, s).items : x.messages
        txWindow = c.tolerant(.txWindow, x.txWindow, w, s)
        shortcuts = c.tolerant(.shortcuts, TolerantDict<KeyBinding>(), w, s).items.filter { $0.value.isValid }
        upload = c.tolerant(.upload, x.upload, w, s)
        spots = c.tolerant(.spots, x.spots, w, s)
        decoders = c.tolerant(.decoders, x.decoders, w, s)
        // older settings without ESM: an empty ⇧F3 gets the default macro "My call" (S&P)
        if !c.contains(.esm), macros.indices.contains(14), macros[14].name.isEmpty, macros[14].text.isEmpty {
            macros[14] = Self.defaultMacros[14]
        }
        esm = c.tolerant(.esm, x.esm, w, s)
        alerts = c.tolerant(.alerts, x.alerts, w, s)
    }

    /// Engine configuration from the settings.
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
