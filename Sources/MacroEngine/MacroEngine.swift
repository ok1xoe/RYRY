// Copyright 2000-2013 Makoto Mori, Nobuyuki Oba; Modifications Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
// Přepis TMmttyWd::ConvString / StoreCWID / OutputStr (MMTTY Main.cpp:4142-4370) do Swiftu.
import Foundation

public struct MacroContext: Sendable, Equatable {
    public var myCall = "", hisCall = "", name = "", qth = ""
    public var rstSent = "599"          // MMTTY MyRST  (%s, %M)
    public var rstRcvd = "599"          // MMTTY HisRST (%r, %R, %N, %x, %y)
    public var now: Date = Date()
    /// Místní čas protistanice = UTC + offset (z DXCC); nil = země neznámá (%g → HELLO, %f → nic).
    public var hisUTCOffsetHours: Double?
    public init() {}
}

public enum MacroOutput: Sendable, Equatable { case text(String), raw([UInt8]) }
public enum MacroEnd: Sendable, Equatable { case none, rxAfter, keepTx }
public enum MacroMode: Sendable, Equatable { case send, toEditor }

public struct MacroResult: Sendable, Equatable {
    public var outputs: [MacroOutput] = []
    public var end: MacroEnd = .none
    public var mode: MacroMode = .send
    /// Makro začínalo `\`: zapnout TX a text vložit do editoru.
    public var startsTx = false
    public var logQSO = false

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
    // Baudot řídicí kódy MMTTY
    static let markHold: UInt8 = 0xFF, carrierOff: UInt8 = 0xFE, diddleOff: UInt8 = 0xFD
    static let ltrs: UInt8 = 0x1F, figs: UInt8 = 0x1B

    public static func expand(_ template: String, context c: MacroContext) -> MacroResult {
        var res = MacroResult()
        var chars = Array(template.unicodeScalars)

        // začátek: '#' = jen do editoru; '\' = TX + do editoru
        if let f = chars.first, f == "#" || f == "\\" {
            res.mode = .toEditor
            res.startsTx = f == "\\"
            chars.removeFirst()
        }
        // konec: '\' = RX po odvysílání, '#' = zůstat na TX (CR/LF mezi nimi se ignorují)
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
                        // %L/%F v CW ID: MMTTY vloží řídicí znak, StoreCWID ho vyšle jako neznámý (5× ticho + mezera)
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

    /// Hodnota proměnné %x (bez řídicích a CW maker).
    static func variable(_ code: Unicode.Scalar, _ c: MacroContext) -> String {
        func after3(_ s: String) -> String { s.count > 3 ? String(s.dropFirst(3)) : "" }
        switch code {
        case "m": return c.myCall
        case "c": return c.hisCall
        case "n": return c.name.isEmpty ? "OM" : c.name
        case "q": return c.qth
        case "r": return c.rstRcvd
        case "s": return c.rstSent
        case "R": return c.rstRcvd.count >= 3 ? String(c.rstRcvd.prefix(3)) : "599"
        case "N": return after3(c.rstRcvd)
        case "M": return after3(c.rstSent)
        case "x":
            let n = after3(c.rstRcvd)
            return n.isEmpty ? "" : String(n.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        case "y":
            let n = after3(c.rstRcvd)
            let parts = n.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count > 1 ? String(parts[1]) : ""
        case "g", "f":
            // TMmttyWd::SetGreetingString: místní čas protistanice podle země
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

    // StoreCWID tabulka pro '0'..'Z': horní bajt = vzor (1 = tečka, MSB první), dolní = počet prvků
    static let cwTable: [UInt16] = [
        0x0005, 0x8005, 0xc005, 0xe005, 0xf005, 0xf805, 0x7805, 0x3805, // 0-7
        0x1805, 0x0805, 0x0000, 0x0000, 0xe806, 0x7005, 0xA805, 0xcc06, // 8 9 : ; < = > ?
        0x0000, 0x8002, 0x7004, 0x5004, 0x6003, 0x8001, 0xd004, 0x2003, // @ A-G
        0xf004, 0xc002, 0x8004, 0x4003, 0xb004, 0x0002, 0x4002, 0x0003, // H-O
        0x9004, 0x2004, 0xa003, 0xe003, 0x0001, 0xc003, 0xe004, 0x8003, // P-W
        0x6004, 0x4004, 0x3004,                                         // X-Z
    ]

    /// Morse jednoho znaku jako Baudot řídicí kódy (StoreCWID).
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
                if d & 0x8000 == 0 { out += [markHold, markHold] }   // čárka = 3× delší
                out.append(carrierOff)
                d <<= 1
            }
        }
        out += [carrierOff, carrierOff]                             // mezera za znakem
        return out
    }
}
