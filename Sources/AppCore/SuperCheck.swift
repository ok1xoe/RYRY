// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Super Check Partial: a database of known calls (MASTER.SCP + calls from the log).
/// `partial` = calls containing the given part (`?` = any character), `near` = calls differing by one character
/// (a substitution, a missing or an extra character) – correcting a mis-received call.
public struct SuperCheck: Sendable {
    private let calls: [[UInt8]]
    public var count: Int { calls.count }
    public static let minPartial = 3
    public static let limit = 30

    public init(calls: [String]) {
        let set = Set(calls.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty })
        self.calls = set.sorted().map { Array($0.utf8) }
    }

    /// Contents of MASTER.SCP: one call per line, `#` = comment.
    public static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Exact call match (binary search in the sorted list).
    public func contains(_ call: String) -> Bool {
        let p = Array(call.trimmingCharacters(in: .whitespaces).uppercased().utf8)
        guard !p.isEmpty else { return false }
        var lo = 0, hi = calls.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if calls[mid].lexicographicallyPrecedes(p) { lo = mid + 1 } else { hi = mid }
        }
        return lo < calls.count && calls[lo] == p
    }

    public func partial(_ s: String) -> [String] {
        let p = Array(s.uppercased().utf8)
        guard p.count >= Self.minPartial else { return [] }
        var out: [String] = []
        for c in calls where Self.contains(c, p) {
            out.append(String(decoding: c, as: UTF8.self))
            if out.count >= Self.limit { break }
        }
        return out
    }

    public func near(_ s: String) -> [String] {
        let p = Array(s.uppercased().utf8)
        guard p.count >= Self.minPartial else { return [] }
        var out: [String] = []
        for c in calls where abs(c.count - p.count) <= 1 && c != p && Self.oneEdit(c, p) {
            out.append(String(decoding: c, as: UTF8.self))
            if out.count >= Self.limit { break }
        }
        return out
    }

    static let wildcard = UInt8(ascii: "?")

    static func contains(_ c: [UInt8], _ p: [UInt8]) -> Bool {
        guard c.count >= p.count else { return false }
        outer: for i in 0...(c.count - p.count) {
            for j in 0..<p.count where p[j] != wildcard && c[i + j] != p[j] { continue outer }
            return true
        }
        return false
    }

    /// Exactly one edit (substitution, insertion, deletion).
    static func oneEdit(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        if a.count == b.count { return zip(a, b).filter { $0 != $1 }.count == 1 }
        let (l, s) = a.count > b.count ? (a, b) : (b, a)
        var i = 0, j = 0, skipped = false
        while i < l.count, j < s.count {
            if l[i] == s[j] { i += 1; j += 1 } else if skipped { return false } else { skipped = true; i += 1 }
        }
        return true
    }
}
