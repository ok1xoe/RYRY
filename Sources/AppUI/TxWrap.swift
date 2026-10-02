// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation

/// Wrapping of typed text (MMTTY "Word wrap on keyboard"): a line longer than `column` is broken
/// at the last space, or hard-broken when there is no space.
public enum TxWrap {
    public static func wrap(_ text: String, column: Int) -> String { wrap(text, column: column, startColumn: 0) }

    /// `startColumn` = how many characters of the current line have already been transmitted (during TX the transmitted text is removed from the window).
    public static func wrap(_ text: String, column: Int, startColumn: Int) -> String {
        guard column > 0 else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.enumerated().map { i, l in wrapLine(l, column, used: i == 0 ? min(max(0, startColumn), column) : 0) }
            .joined(separator: "\n")
    }

    /// Column after the text has been transmitted (since the last CR/LF), counted from `from`.
    public static func column(afterSending s: String, from: Int = 0) -> Int {
        if let i = s.lastIndex(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) { return s.distance(from: s.index(after: i), to: s.endIndex) }
        return from + s.count
    }

    /// `used` = characters of the first line already taken up earlier (transmitted text).
    static func wrapLine(_ line: String, _ column: Int, used: Int = 0) -> String {
        var rest = Substring(line), out: [Substring] = [], room = column - used
        while rest.count > room {
            let limit = rest.index(rest.startIndex, offsetBy: max(0, room))
            if let sp = rest[..<rest.index(limit, offsetBy: 1, limitedBy: rest.endIndex)!].lastIndex(of: " "), sp > rest.startIndex {
                out.append(rest[..<sp]); rest = rest[rest.index(after: sp)...]
            } else if room < column {
                out.append("")                                   // after the transmitted text: the whole word goes on a new line
            } else {
                out.append(rest[..<limit]); rest = rest[limit...]
            }
            room = column
        }
        out.append(rest)
        return out.joined(separator: "\n")
    }
}
