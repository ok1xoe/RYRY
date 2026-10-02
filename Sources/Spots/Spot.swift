// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import QSOLog

/// Where the spot came from.
public enum SpotSource: String, Sendable, Equatable { case cluster, rbn }

/// A single spot from a DX cluster or the Reverse Beacon Network.
public struct Spot: Sendable, Equatable, Identifiable {
    public var frequencyKHz: Double
    public var call: String
    public var spotter: String
    public var comment: String
    public var time: Date
    /// "RTTY", another recognized mode (CW, FT8…), or nil when it cannot be told from the comment or the frequency.
    public var mode: String?
    public var snr: Int?
    public var source: SpotSource

    public init(frequencyKHz: Double, call: String, spotter: String, comment: String, time: Date,
                mode: String? = nil, snr: Int? = nil, source: SpotSource = .cluster) {
        self.frequencyKHz = frequencyKHz; self.call = call; self.spotter = spotter; self.comment = comment
        self.time = time; self.mode = mode; self.snr = snr; self.source = source
    }

    public var frequencyHz: Double { frequencyKHz * 1000 }
    public var band: String? { Bands.band(forHz: frequencyHz) }
    /// Deduplication key: call + band.
    public var id: String { call + "|" + (band ?? "?") }
}

/// Parser of "DX de SPOTTER:  14080.0  DL1ABC  comment  1203Z" lines (DX cluster and RBN) and of `sh/dx` listing lines
/// from a DX cluster: "14080.0  JA1ABC  30-Sep-2026 0701Z  comment  <SPOTTER>" (DXSpider, AR-Cluster, CC Cluster).
public enum SpotParser {
    /// RTTY segments in kHz (approximate, IARU band plans) – for spots without a mode in the comment.
    public static let rttySegments: [ClosedRange<Double>] = [
        3580...3600, 7030...7060, 10130...10150, 14070...14100, 18095...18109,
        21070...21100, 24910...24930, 28070...28120,
    ]
    public static func inRTTYSegment(kHz: Double) -> Bool { rttySegments.contains { $0.contains(kHz) } }

    static let otherModes: Set<String> = ["CW", "PSK", "PSK31", "PSK63", "PSK125", "FT8", "FT4", "JT65", "JT9", "SSB", "USB", "LSB",
                                          "FM", "AM", "MFSK", "OLIVIA", "SSTV", "WSPR", "FSK441", "HELL", "MSK144", "Q65"]

    /// `now` = the current time (the time in a spot is only HHMM UTC; the date is computed).
    public static func parse(_ line: String, now: Date = Date(), source: SpotSource = .cluster) -> Spot? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.lowercased().hasPrefix("dx de ") else {
            return source == .cluster ? parseListing(text, now: now) : nil
        }
        let rest = text.dropFirst(6)
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        let spotter = rest[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
        guard !spotter.isEmpty, !spotter.contains(" ") else { return nil }
        let tokens = rest[rest.index(after: colon)...].split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.count >= 3, let kHz = Double(tokens[0]), kHz >= 100, kHz < 1e7 else { return nil }
        let call = tokens[1].uppercased()
        guard validCall(call) else { return nil }
        // the HHMMZ time is the last token, possibly before the locator (CC cluster adds it)
        var timeIdx: Int?
        for i in stride(from: tokens.count - 1, through: max(2, tokens.count - 2), by: -1) where parseHHMM(tokens[i]) != nil {
            timeIdx = i; break
        }
        guard let ti = timeIdx, let hm = parseHHMM(tokens[ti]) else { return nil }
        let comment = tokens[2..<ti].joined(separator: " ")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hm.0; comps.minute = hm.1; comps.second = 0
        guard var t = cal.date(from: comps) else { return nil }
        if t > now.addingTimeInterval(300) { t = cal.date(byAdding: .day, value: -1, to: t) ?? t }   // spot from the previous day (UTC midnight)
        return Spot(frequencyKHz: kHz, call: call, spotter: spotter, comment: comment, time: t,
                    mode: mode(comment: comment, kHz: kHz), snr: snr(in: comment), source: source)
    }

    /// Spot mode: the word RTTY in the comment, another known mode, otherwise RTTY by band segment; nil = unrecognized.
    static func mode(comment: String, kHz: Double) -> String? {
        let words = comment.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.contains("RTTY") { return "RTTY" }
        if let m = words.first(where: { otherModes.contains($0) }) { return m }
        return inRTTYSegment(kHz: kHz) ? "RTTY" : nil
    }

    /// A `sh/dx` listing line: frequency, call, date, HHMMZ time, comment, `<spotter>` (at most 2 words after it,
    /// e.g. a CC Cluster locator). Requires the whole pattern so that arbitrary console text is not taken as a spot.
    static func parseListing(_ text: String, now: Date) -> Spot? {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.count >= 5, let kHz = Double(tokens[0]), kHz >= 100, kHz < 1e7 else { return nil }
        let call = tokens[1].uppercased()
        guard validCall(call), let hm = parseHHMM(tokens[3]),
              let si = tokens.indices.last(where: { $0 >= 4 && tokens[$0].hasPrefix("<") && tokens[$0].hasSuffix(">") }),
              tokens.count - si <= 3 else { return nil }
        let spotter = tokens[si].dropFirst().dropLast().uppercased()
        guard !spotter.isEmpty, spotter.count <= 20,
              spotter.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || "/-#".contains($0) }),
              let t = listingDate(tokens[2], hour: hm.0, minute: hm.1, now: now) else { return nil }
        let comment = tokens[4..<si].joined(separator: " ")
        return Spot(frequencyKHz: kHz, call: call, spotter: String(spotter), comment: comment, time: t,
                    mode: mode(comment: comment, kHz: kHz), snr: snr(in: comment), source: .cluster)
    }

    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// Listing date: "30-Sep-2026", "30-Sep-26", "30-Sep" (year computed; a future one = last year) or "2026-09-30".
    static func listingDate(_ s: String, hour: Int, minute: Int, now: Date) -> Date? {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let p = s.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        var y: Int?, m: Int, d: Int
        if p.count == 3, p[0].count == 4, let yy = Int(p[0]), let mm = Int(p[1]), let dd = Int(p[2]) {
            y = yy; m = mm; d = dd
        } else if (2...3).contains(p.count), let dd = Int(p[0]), let mi = months.firstIndex(of: p[1].uppercased()) {
            d = dd; m = mi + 1
            if p.count == 3 {
                guard let yy = Int(p[2]), p[2].count == 4 || p[2].count == 2 else { return nil }
                y = p[2].count == 2 ? 2000 + yy : yy
            }
        } else { return nil }
        let year = y ?? cal.component(.year, from: now)
        var comps = DateComponents(year: year, month: m, day: d, hour: hour, minute: minute)
        guard cal.date(from: comps) != nil, let check = cal.date(from: comps),
              cal.component(.day, from: check) == d, cal.component(.month, from: check) == m else { return nil }   // 31-Feb
        if y == nil, check > now.addingTimeInterval(86_400) { comps.year = year - 1; return cal.date(from: comps) }
        return check
    }

    static func parseHHMM(_ s: String) -> (Int, Int)? {
        guard s.count == 5, s.last == "Z" || s.last == "z" else { return nil }
        let d = s.dropLast()
        guard d.allSatisfy(\.isASCII), d.allSatisfy(\.isNumber), let v = Int(d), v / 100 < 24, v % 100 < 60 else { return nil }
        return (v / 100, v % 100)
    }

    static func validCall(_ c: String) -> Bool {
        guard (3...15).contains(c.count),
              c.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "/" }) else { return false }
        return c.contains(where: \.isNumber) && c.contains(where: \.isLetter)
    }

    /// "25 dB" or "25dB" in the comment.
    static func snr(in comment: String) -> Int? {
        let t = comment.split(separator: " ").map(String.init)
        for (i, w) in t.enumerated() {
            let u = w.uppercased()
            if u == "DB", i > 0, let v = Int(t[i - 1]) { return v }
            if u.hasSuffix("DB"), let v = Int(u.dropLast(2)) { return v }
        }
        return nil
    }
}
