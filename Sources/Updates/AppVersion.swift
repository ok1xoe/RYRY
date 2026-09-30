// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Application version: semver (major.minor.patch[-prerelease]) + an optional build number.
public struct AppVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    public var numbers: [Int]          // always 3 elements
    public var prerelease: [String]    // the parts after "-" (empty = a full release)
    public var build: Int?

    public init?(_ text: String, build: Int? = nil) {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.first == "v" || t.first == "V" { t.removeFirst() }
        if let plus = t.firstIndex(of: "+") { t = String(t[..<plus]) }      // build metadata is ignored
        var pre: [String] = []
        if let dash = t.firstIndex(of: "-") {
            pre = t[t.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            t = String(t[..<dash])
            if pre.contains(where: \.isEmpty) { return nil }
        }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var nums: [Int] = []
        for p in parts {
            guard !p.isEmpty, p.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(p) else { return nil }
            nums.append(n)
        }
        while nums.count < 3 { nums.append(0) }
        numbers = nums; prerelease = pre; self.build = build
    }

    public var description: String {
        numbers.map(String.init).joined(separator: ".") + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
    }

    /// Ordering by semver; the build number is not part of `<` (see `isNewer`).
    public static func < (a: AppVersion, b: AppVersion) -> Bool { compareSemver(a, b) < 0 }
    public static func == (a: AppVersion, b: AppVersion) -> Bool { compareSemver(a, b) == 0 && a.build == b.build }

    static func compareSemver(_ a: AppVersion, _ b: AppVersion) -> Int {
        for i in 0..<3 where a.numbers[i] != b.numbers[i] { return a.numbers[i] < b.numbers[i] ? -1 : 1 }
        if a.prerelease.isEmpty != b.prerelease.isEmpty { return a.prerelease.isEmpty ? 1 : -1 }   // release > prerelease
        for (x, y) in zip(a.prerelease, b.prerelease) where x != y {
            switch (Int(x), Int(y)) {
            case let (i?, j?): return i < j ? -1 : 1
            case (_?, nil): return -1                     // numeric < textual
            case (nil, _?): return 1
            default: return x < y ? -1 : 1
            }
        }
        if a.prerelease.count != b.prerelease.count { return a.prerelease.count < b.prerelease.count ? -1 : 1 }
        return 0
    }

    /// Is `self` newer than `other`? With equal versions the build number decides (only when known for both).
    public func isNewer(than other: AppVersion) -> Bool {
        let c = Self.compareSemver(self, other)
        if c != 0 { return c > 0 }
        if let b = build, let o = other.build { return b > o }
        return false
    }
}
