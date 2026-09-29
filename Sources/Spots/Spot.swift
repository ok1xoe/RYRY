// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import QSOLog

/// Odkud spot přišel.
public enum SpotSource: String, Sendable, Equatable { case cluster, rbn }

/// Jeden spot z DX clusteru nebo Reverse Beacon Network.
public struct Spot: Sendable, Equatable, Identifiable {
    public var frequencyKHz: Double
    public var call: String
    public var spotter: String
    public var comment: String
    public var time: Date
    /// „RTTY“, jiný rozpoznaný mód (CW, FT8…), nebo nil, když z komentáře ani frekvence nejde poznat.
    public var mode: String?
    public var snr: Int?
    public var source: SpotSource

    public init(frequencyKHz: Double, call: String, spotter: String, comment: String, time: Date,
                mode: String? = nil, snr: Int? = nil, source: SpotSource = .cluster) {
        self.frequencyKHz = frequencyKHz; self.call = call; self.spotter = spotter; self.comment = comment
        self.time = time; self.mode = mode; self.snr = snr; self.source = source
    }

    public var isRTTY: Bool { mode == "RTTY" }
    public var frequencyHz: Double { frequencyKHz * 1000 }
    public var band: String? { Bands.band(forHz: frequencyHz) }
    /// Klíč deduplikace: značka + pásmo.
    public var id: String { call + "|" + (band ?? "?") }
}

/// Parser řádků „DX de SPOTTER:  14080.0  DL1ABC  komentář  1203Z“ (DX cluster i RBN).
public enum SpotParser {
    /// Segmenty RTTY v kHz (orientačně, IARU pásmové plány) – pro spoty bez módu v komentáři.
    public static let rttySegments: [ClosedRange<Double>] = [
        3580...3600, 7030...7060, 10130...10150, 14070...14100, 18095...18109,
        21070...21100, 24910...24930, 28070...28120,
    ]
    public static func inRTTYSegment(kHz: Double) -> Bool { rttySegments.contains { $0.contains(kHz) } }

    static let otherModes: Set<String> = ["CW", "PSK", "PSK31", "PSK63", "PSK125", "FT8", "FT4", "JT65", "JT9", "SSB", "USB", "LSB",
                                          "FM", "AM", "MFSK", "OLIVIA", "SSTV", "WSPR", "FSK441", "HELL", "MSK144", "Q65"]

    /// `now` = aktuální čas (čas ve spotu je jen HHMM UTC; datum se dopočítá).
    public static func parse(_ line: String, now: Date = Date(), source: SpotSource = .cluster) -> Spot? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.lowercased().hasPrefix("dx de ") else { return nil }
        let rest = text.dropFirst(6)
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        let spotter = rest[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
        guard !spotter.isEmpty, !spotter.contains(" ") else { return nil }
        let tokens = rest[rest.index(after: colon)...].split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.count >= 3, let kHz = Double(tokens[0]), kHz >= 100, kHz < 1e7 else { return nil }
        let call = tokens[1].uppercased()
        guard validCall(call) else { return nil }
        // čas HHMMZ je poslední token, případně před lokátorem (CC cluster ho přidává)
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
        if t > now.addingTimeInterval(300) { t = cal.date(byAdding: .day, value: -1, to: t) ?? t }   // spot z minulého dne (půlnoc UTC)
        let words = comment.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var mode: String?
        if words.contains("RTTY") { mode = "RTTY" }
        else if let m = words.first(where: { otherModes.contains($0) }) { mode = m }
        else if inRTTYSegment(kHz: kHz) { mode = "RTTY" }
        return Spot(frequencyKHz: kHz, call: call, spotter: spotter, comment: comment, time: t,
                    mode: mode, snr: snr(in: comment), source: source)
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

    /// „25 dB“ nebo „25dB“ v komentáři.
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
