// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Zalamování psaného textu (MMTTY „Word wrap on keyboard“): řádek delší než `column` se zlomí
/// na poslední mezeře, bez mezery natvrdo.
public enum TxWrap {
    public static func wrap(_ text: String, column: Int) -> String {
        guard column > 0 else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { wrapLine(String($0), column) }
            .joined(separator: "\n")
    }

    static func wrapLine(_ line: String, _ column: Int) -> String {
        var rest = Substring(line), out: [Substring] = []
        while rest.count > column {
            let limit = rest.index(rest.startIndex, offsetBy: column)
            if let sp = rest[..<rest.index(after: limit)].lastIndex(of: " "), sp > rest.startIndex {
                out.append(rest[..<sp]); rest = rest[rest.index(after: sp)...]
            } else {
                out.append(rest[..<limit]); rest = rest[limit...]
            }
        }
        out.append(rest)
        return out.joined(separator: "\n")
    }
}
