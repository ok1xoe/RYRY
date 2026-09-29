// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Zalamování psaného textu (MMTTY „Word wrap on keyboard“): řádek delší než `column` se zlomí
/// na poslední mezeře, bez mezery natvrdo.
public enum TxWrap {
    public static func wrap(_ text: String, column: Int) -> String { wrap(text, column: column, startColumn: 0) }

    /// `startColumn` = kolik znaků aktuálního řádku už bylo odvysíláno (během TX se odvysílaný text z okna maže).
    public static func wrap(_ text: String, column: Int, startColumn: Int) -> String {
        guard column > 0 else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.enumerated().map { i, l in wrapLine(l, column, used: i == 0 ? min(max(0, startColumn), column) : 0) }
            .joined(separator: "\n")
    }

    /// Sloupec po odvysílání textu (od posledního CR/LF), počítáno od `from`.
    public static func column(afterSending s: String, from: Int = 0) -> Int {
        if let i = s.lastIndex(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) { return s.distance(from: s.index(after: i), to: s.endIndex) }
        return from + s.count
    }

    /// `used` = znaky prvního řádku obsazené už dříve (odvysílaný text).
    static func wrapLine(_ line: String, _ column: Int, used: Int = 0) -> String {
        var rest = Substring(line), out: [Substring] = [], room = column - used
        while rest.count > room {
            let limit = rest.index(rest.startIndex, offsetBy: max(0, room))
            if let sp = rest[..<rest.index(limit, offsetBy: 1, limitedBy: rest.endIndex)!].lastIndex(of: " "), sp > rest.startIndex {
                out.append(rest[..<sp]); rest = rest[rest.index(after: sp)...]
            } else if room < column {
                out.append("")                                   // za odvysílaným textem: celé slovo na nový řádek
            } else {
                out.append(rest[..<limit]); rest = rest[limit...]
            }
            room = column
        }
        out.append(rest)
        return out.joined(separator: "\n")
    }
}
