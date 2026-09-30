// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Removes telnet commands (IAC) from the stream and prepares polite replies (to DO → WONT, to WILL → DONT).
struct TelnetFilter {
    private enum St { case normal, iac, option(UInt8), sub, subIAC }
    private var st = St.normal

    /// Returns the clean text and the bytes that need to be sent back.
    mutating func process(_ data: Data) -> (text: Data, reply: Data) {
        var text = Data(), reply = Data()
        for b in data {
            switch st {
            case .normal:
                if b == 255 { st = .iac } else { text.append(b) }
            case .iac:
                switch b {
                case 255: text.append(255); st = .normal
                case 251, 252, 253, 254: st = .option(b)
                case 250: st = .sub
                default: st = .normal
                }
            case .option(let cmd):
                if cmd == 253 { reply.append(contentsOf: [255, 252, b]) }
                else if cmd == 251 { reply.append(contentsOf: [255, 254, b]) }
                st = .normal
            case .sub: if b == 255 { st = .subIAC }
            case .subIAC: st = b == 240 ? .normal : .sub
            }
        }
        return (text, reply)
    }
}

/// Assembles bytes into lines; an unfinished remainder (the "login:" prompt) is available in `pending`.
struct LineSplitter {
    private var buf = Data()

    mutating func feed(_ data: Data) -> [String] {
        buf.append(data)
        var lines: [String] = []
        while let i = buf.firstIndex(of: 10) {
            lines.append(Self.decode(buf[buf.startIndex..<i]))
            buf.removeSubrange(buf.startIndex...i)
        }
        if buf.count > 8192 { buf.removeAll() }         // protection against an endless line
        return lines
    }

    var pending: String { Self.decode(buf) }

    static func decode(_ d: Data) -> String {
        let clean = d.filter { $0 >= 32 || $0 == 9 }    // without CR, BEL, NUL…
        return String(data: clean, encoding: .utf8) ?? String(decoding: clean.map { UInt16($0) }, as: UTF16.self)
    }
}

enum TelnetPrompt {
    /// Prompt to enter the call: "login:", "Please enter your call:", "callsign:"…
    static func isLogin(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        guard let last = t.last, ":?>".contains(last), t.count < 80 else { return false }
        return t.contains("login") || t.contains("call")
    }
}
