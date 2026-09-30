// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Icom CI-V: frame `FE FE <to> <from> <cmd> [data…] FD`, the computer has address E0.
public enum CIV {
    public static let controller: UInt8 = 0xE0

    public struct Frame: Equatable, Sendable {
        public var to: UInt8, from: UInt8, cmd: UInt8
        public var data: ArraySlice<UInt8>
    }

    public static func frame(to radio: UInt8, cmd: UInt8, _ data: [UInt8] = []) -> [UInt8] {
        [0xFE, 0xFE, radio, controller, cmd] + data + [0xFD]
    }

    /// Frequency in Hz → 5 BCD bytes, least significant first.
    public static func bcd(_ hz: Int) -> [UInt8] {
        var v = max(0, hz), out: [UInt8] = []
        for _ in 0..<5 { let lo = v % 10; v /= 10; let hi = v % 10; v /= 10; out.append(UInt8(hi << 4 | lo)) }
        return out
    }

    public static func fromBCD(_ b: [UInt8]) -> Int? {
        var v = 0, mul = 1
        for x in b {
            let lo = Int(x & 0x0F), hi = Int(x >> 4)
            guard lo < 10, hi < 10 else { return nil }
            v += lo * mul + hi * mul * 10; mul *= 100
        }
        return v
    }

    public static func readFrequency(to r: UInt8) -> [UInt8] { frame(to: r, cmd: 0x03) }
    public static func setFrequency(_ hz: Double, to r: UInt8) -> [UInt8] { frame(to: r, cmd: 0x05, bcd(Int(hz.rounded()))) }
    public static func readMode(to r: UInt8) -> [UInt8] { frame(to: r, cmd: 0x04) }
    public static func ptt(_ on: Bool, to r: UInt8) -> [UInt8] { frame(to: r, cmd: 0x1C, [0x00, on ? 0x01 : 0x00]) }
    /// Data mode (USB-D etc., IC-7300/705/9700/7610): 1A 06 <0/1> <filter>.
    public static func dataMode(_ on: Bool, to r: UInt8) -> [UInt8] { frame(to: r, cmd: 0x1A, [0x06, on ? 0x01 : 0x00, on ? 0x01 : 0x00]) }

    static let modes: [(UInt8, String)] = [(0x00, "LSB"), (0x01, "USB"), (0x02, "AM"), (0x03, "CW"), (0x04, "RTTY"),
                                           (0x05, "FM"), (0x07, "CWR"), (0x08, "RTTYR")]
    public static func modeName(_ c: UInt8) -> String? { modes.first { $0.0 == c }?.1 }
    /// Mode name (hamlib) → code; PKTUSB/PKTLSB = USB/LSB + data mode.
    public static func modeCode(_ name: String) -> UInt8? {
        switch name.uppercased() {
        case "PKTUSB": return 0x01
        case "PKTLSB": return 0x00
        default: return modes.first { $0.1 == name.uppercased() }?.0
        }
    }

    /// Assembles frames from a byte stream. Returns only frames addressed to the computer (E0) – the echo of our own
    /// commands on the CI-V bus and broadcasts to everybody (address 00) are skipped.
    public struct Parser: Sendable {
        var buf: [UInt8] = []
        public init() {}
        public mutating func feed(_ bytes: [UInt8]) -> [Frame] {
            buf += bytes
            var out: [Frame] = []
            while true {
                guard let s = buf.firstIndex(of: 0xFE) else { buf.removeAll(); break }
                if s > 0 { buf.removeFirst(s) }
                guard let e = buf.firstIndex(of: 0xFD) else { break }
                let f = Array(buf[..<e]); buf.removeFirst(e + 1)
                // FE FE to from cmd …  (the preamble may repeat FE several times)
                var i = 0
                while i < f.count, f[i] == 0xFE { i += 1 }
                guard f.count - i >= 3 else { continue }
                let fr = Frame(to: f[i], from: f[i + 1], cmd: f[i + 2], data: f[(i + 3)...])
                if fr.to == controller, fr.from != controller { out.append(fr) }
            }
            return out
        }
    }
}

/// Text CAT terminated by ";" – Kenwood, Elecraft and the newer Yaesu (FT-991, FTDX10/101, FT-710).
public enum TextCAT {
    public enum Dialect: String, Sendable, CaseIterable { case kenwood, elecraft, yaesu }

    public static let frequencyQuery = "FA;"
    public static func setFrequency(_ hz: Double, dialect: Dialect) -> String {
        setFrequency(hz, digits: dialect == .yaesu ? 9 : 11)
    }
    public static func setFrequency(_ hz: Double, digits: Int) -> String {
        "FA" + String(format: "%0\(min(max(digits, 6), 11))d", Int(hz.rounded())) + ";"
    }
    public static func parseFrequency(_ s: String) -> Double? {
        guard s.hasPrefix("FA"), s.hasSuffix(";") else { return nil }
        let d = s.dropFirst(2).dropLast()
        guard !d.isEmpty, d.allSatisfy(\.isNumber), let v = Double(d), v > 0 else { return nil }
        return v
    }

    public static func ptt(_ on: Bool, dialect: Dialect) -> String {
        switch dialect {
        case .kenwood: return on ? "TX1;" : "RX;"          // TX1 = DATA SEND (audio from USB/ACC)
        case .elecraft: return on ? "TX;" : "RX;"
        case .yaesu: return on ? "TX1;" : "TX0;"
        }
    }

    public static func modeQuery(_ d: Dialect) -> String { d == .yaesu ? "MD0;" : "MD;" }

    static let kenwoodModes: [(String, String)] = [("1", "LSB"), ("2", "USB"), ("3", "CW"), ("4", "FM"), ("5", "AM"),
                                                    ("6", "RTTY"), ("7", "CWR"), ("9", "RTTYR")]
    static let yaesuModes: [(String, String)] = [("1", "LSB"), ("2", "USB"), ("3", "CW"), ("4", "FM"), ("5", "AM"),
                                                  ("6", "RTTY"), ("7", "CWR"), ("8", "PKTLSB"), ("9", "RTTYR"),
                                                  ("A", "PKTFM"), ("C", "PKTUSB")]

    public static func parseMode(_ s: String, dialect: Dialect) -> String? {
        guard s.hasPrefix("MD"), s.hasSuffix(";") else { return nil }
        let body = String(s.dropFirst(2).dropLast())
        switch dialect {
        case .yaesu: return body.count == 2 ? yaesuModes.first { $0.0 == String(body.last!) }?.1 : nil
        case .kenwood, .elecraft: return kenwoodModes.first { $0.0 == body }?.1
        }
    }

    /// Command(s) to set the mode; nil = the protocol does not know the mode.
    public static func setMode(_ name: String, dialect: Dialect) -> String? {
        let n = name.uppercased()
        switch dialect {
        case .yaesu: return yaesuModes.first { $0.1 == n }.map { "MD0\($0.0);" }
        case .kenwood:
            if n == "PKTUSB" { return "MD2;DA1;" }
            if n == "PKTLSB" { return "MD1;DA1;" }
            return kenwoodModes.first { $0.1 == n }.map { "MD\($0.0);DA0;" }       // leave the data mode
        case .elecraft:
            if n == "PKTUSB" { return "MD6;DT0;" }                   // DATA A
            if n == "PKTLSB" { return "MD9;DT0;" }                   // DATA A reverse
            return kenwoodModes.first { $0.1 == n }.map { "MD\($0.0);" }
        }
    }
}
