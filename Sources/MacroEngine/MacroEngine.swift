// Copyright 2000-2013 Makoto Mori, Nobuyuki Oba; Modifications Copyright 2026 OK1XOE (RYRY), LGPL v3
// A rewrite of TMmttyWd::ConvString / StoreCWID / OutputStr (MMTTY Main.cpp:4142-4370) in Swift.
import Foundation

public struct MacroContext: Sendable, Equatable {
    public var myCall = "", hisCall = "", name = "", qth = ""
    /// MMTTY HisRST: the report (and the contest serial) I SEND to the other station – %r, %R, %N, %x, %y.
    public var hisRST = "599"
    /// MMTTY MyRST: the report (and serial) I RECEIVED from the other station – %s, %M.
    public var myRST = "599"
    public var now: Date = Date()
    /// The other station's local time = UTC + offset (from DXCC); nil = country unknown (%g → HELLO, %f → nothing).
    public var hisUTCOffsetHours: Double?
    /// The rig frequency in kHz (%k; only for DX cluster commands, e.g. `dx %k %c RTTY`); nil = unknown (%k → nothing).
    public var rigKHz: Double?
    public init() {}
}

public enum MacroOutput: Sendable, Equatable {
    case text(String), raw([UInt8])
    /// Nothing to transmit.
    public var isEmpty: Bool {
        switch self { case .text(let t): t.isEmpty; case .raw(let r): r.isEmpty }
    }
}
public enum MacroEnd: Sendable, Equatable { case none, rxAfter, keepTx }
public enum MacroMode: Sendable, Equatable { case send, toEditor }

public struct MacroResult: Sendable, Equatable {
    public var outputs: [MacroOutput] = []
    public var end: MacroEnd = .none
    public var mode: MacroMode = .send
    /// The macro started with `\`: switch on TX and put the text into the editor.
    public var startsTx = false
    public var logQSO = false

    public init() {}
    /// Plain text without variables or control characters (e.g. QTC); `end` = what follows the transmission.
    public static func plain(_ text: String, end: MacroEnd) -> MacroResult {
        var m = MacroResult(); m.outputs = [.text(text)]; m.end = end; return m
    }

    public var plainText: String {
        outputs.map {
            switch $0 {
            case .text(let t): return t
            case .raw(let r): return r.first == 0xFD ? "[CW ID]" : ""
            }
        }.joined()
    }
}

public enum MacroEngine {
    // MMTTY Baudot control codes
    static let markHold: UInt8 = 0xFF, carrierOff: UInt8 = 0xFE, diddleOff: UInt8 = 0xFD
    static let ltrs: UInt8 = 0x1F, figs: UInt8 = 0x1B

    public static func expand(_ template: String, context c: MacroContext) -> MacroResult {
        var res = MacroResult()
        var chars = Array(template.unicodeScalars)

        // start: '#' = editor only; '\' = TX + editor
        if let f = chars.first, f == "#" || f == "\\" {
            res.mode = .toEditor
            res.startsTx = f == "\\"
            chars.removeFirst()
        }
        // end: '\' = RX after transmitting, '#' = stay in TX (CR/LF in between are ignored)
        var cut = chars.count
        var i = chars.count - 1
        while i >= 0 {
            let ch = chars[i]
            if ch == "\\" { res.end = .rxAfter; cut = i }
            else if ch == "#" { res.end = .keepTx; cut = i }
            else if ch != "\r" && ch != "\n" { break }
            i -= 1
        }
        let tail = Array(chars[cut...]).filter { $0 == "\r" || $0 == "\n" }
        chars = Array(chars[..<cut]) + tail

        var text = ""
        func flush() { if !text.isEmpty { res.outputs.append(.text(text)); text = "" } }
        func raw(_ r: [UInt8]) { flush(); res.outputs.append(.raw(r)) }

        var p = 0
        loop: while p < chars.count {
            let ch = chars[p]
            if ch != "%" {
                if ch != "\\" { text.unicodeScalars.append(ch) }
                p += 1; continue
            }
            p += 1
            guard p < chars.count else { break }
            let code = chars[p]
            p += 1
            switch code {
            case "L": raw([ltrs])
            case "F": raw([figs])
            case "E": break loop
            case "l": res.logQSO = true
            case "{":
                var codes: [UInt8] = [diddleOff, carrierOff]
                while p < chars.count, chars[p] != "}" {
                    if chars[p] == "%", p + 1 < chars.count {
                        // %L/%F in a CW ID: MMTTY inserts a control character, StoreCWID sends it as unknown (5× silence + space)
                        let v = chars[p + 1] == "L" ? "\u{1F}" : chars[p + 1] == "F" ? "\u{1B}" : variable(chars[p + 1], c)
                        for x in v.unicodeScalars { codes += cw(x) }
                        p += 2
                    } else {
                        codes += cw(chars[p]); p += 1
                    }
                }
                if p < chars.count { p += 1 }        // '}'
                raw(codes)
            default:
                text += variable(code, c)
            }
        }
        flush()
        return res
    }

    /// The maximum length of one DX cluster command (characters).
    public static let maxClusterLine = 250

    /// A DX cluster macro: the same variables as a transmit macro (+ `%k` the rig frequency in kHz), but text only:
    /// `\` and `#` at the start/end, CW ID `%{…}`, `%L` `%F` `%l` `%E` are not control (they are dropped), a line = a command.
    /// Control characters (except the CR/LF line breaks) are removed, empty lines are skipped, a line is cut to 250 characters.
    public static func expandCluster(_ template: String, context c: MacroContext) -> [String] {
        let r = expand(template, context: c)
        let text = r.outputs.compactMap { o -> String? in if case .text(let t) = o { t } else { nil } }.joined()
        return text.split(whereSeparator: { $0 == "\r" || $0 == "\n" || $0 == "\r\n" }).compactMap { line in
            let clean = String(String.UnicodeScalarView(line.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }))
                .trimmingCharacters(in: .whitespaces)
            return clean.isEmpty ? nil : String(clean.prefix(maxClusterLine))
        }
    }

    /// The value of the %x variable (without the control and CW macros).
    static func variable(_ code: Unicode.Scalar, _ c: MacroContext) -> String {
        func after3(_ s: String) -> String { s.count > 3 ? String(s.dropFirst(3)) : "" }
        switch code {
        case "m": return c.myCall
        case "c": return c.hisCall
        case "n": return c.name.isEmpty ? "OM" : c.name
        case "q": return c.qth
        case "r": return c.hisRST
        case "s": return c.myRST
        case "R": return c.hisRST.count >= 3 ? String(c.hisRST.prefix(3)) : "599"
        case "N": return after3(c.hisRST)
        case "M": return after3(c.myRST)
        case "x":
            let n = after3(c.hisRST)
            return n.isEmpty ? "" : String(n.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        case "y":
            let n = after3(c.hisRST)
            let parts = n.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count > 1 ? String(parts[1]) : ""
        case "k":
            guard let k = c.rigKHz, k.isFinite, k > 0 else { return "" }
            return String(format: "%.1f", k)
        case "g", "f":
            // TMmttyWd::SetGreetingString: the other station's local time from its country
            guard let off = c.hisUTCOffsetHours, off.isFinite else { return code == "g" ? "HELLO" : "" }
            let h = utc.component(.hour, from: c.now.addingTimeInterval(off * 3600))
            let (long, short) = h < 12 ? ("GOOD MORNING", "GM") : h < 18 ? ("GOOD AFTERNOON", "GA") : ("GOOD EVENING", "GE")
            return code == "g" ? long : short
        case "D":
            let d = utc.dateComponents([.year, .month, .day], from: c.now)
            return String(format: "%04d-%@-%02d", d.year!, months[d.month!], d.day!)
        case "T":
            let d = utc.dateComponents([.hour, .minute], from: c.now)
            return String(format: "%02d:%02d", d.hour!, d.minute!)
        case "t":
            let d = utc.dateComponents([.hour, .minute], from: c.now)
            return String(format: "%02d%02d", d.hour!, d.minute!)
        default:
            return "%%"
        }
    }

    static let utc: Calendar = { var k = Calendar(identifier: .gregorian); k.timeZone = TimeZone(identifier: "UTC")!; return k }()
    static let months = ["", "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    // StoreCWID table for '0'..'Z': high byte = the pattern (1 = dot, MSB first), low = the number of elements
    static let cwTable: [UInt16] = [
        0x0005, 0x8005, 0xc005, 0xe005, 0xf005, 0xf805, 0x7805, 0x3805, // 0-7
        0x1805, 0x0805, 0x0000, 0x0000, 0xe806, 0x7005, 0xA805, 0xcc06, // 8 9 : ; < = > ?
        0x0000, 0x8002, 0x7004, 0x5004, 0x6003, 0x8001, 0xd004, 0x2003, // @ A-G
        0xf004, 0xc002, 0x8004, 0x4003, 0xb004, 0x0002, 0x4002, 0x0003, // H-O
        0x9004, 0x2004, 0xa003, 0xe003, 0x0001, 0xc003, 0xe004, 0x8003, // P-W
        0x6004, 0x4004, 0x3004,                                         // X-Z
    ]

    /// The Morse code of one character as Baudot control codes (StoreCWID).
    static func cw(_ s: Unicode.Scalar) -> [UInt8] {
        let c = Character(s).uppercased().unicodeScalars.first!.value & 0x7F
        var out: [UInt8] = []
        var d: Int, nn: Int
        if c == UInt32(UInt8(ascii: "/")) { d = 0x6805; nn = d & 0xFF }
        else if c == UInt32(UInt8(ascii: "@")) { d = -1; nn = 3 }
        else if c >= 0x30, c <= 0x5A, Int(c - 0x30) < cwTable.count { d = Int(cwTable[Int(c - 0x30)]); nn = d & 0xFF }
        else { d = -1; nn = 5 }
        if d == -1 || d == 0 && nn == 0 {
            if d == -1 { out += [UInt8](repeating: carrierOff, count: nn) }
        } else {
            for _ in 0..<nn {
                out.append(markHold)
                if d & 0x8000 == 0 { out += [markHold, markHold] }   // dash = 3× longer
                out.append(carrierOff)
                d <<= 1
            }
        }
        out += [carrierOff, carrierOff]                             // the gap after a character
        return out
    }
}
