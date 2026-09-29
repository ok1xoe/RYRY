// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Hlavička Cabrillo 3.0.
public struct CabrilloHeader: Sendable, Equatable {
    public var callsign: String
    public var contest: String
    /// Položky „KLÍČ: hodnota“; bez předpony se doplní `CATEGORY-` (např. „OPERATOR: SINGLE-OP“).
    public var categories: [String] = []
    public var locator = ""
    public var name = ""
    public init(callsign: String, contest: String) { self.callsign = callsign; self.contest = contest }
}

/// Export logu do formátu Cabrillo 3.0 (mód RY = RTTY).
public enum Cabrillo {
    public static func export(_ records: [QSORecord], header h: CabrilloHeader) -> String {
        var lines = ["START-OF-LOG: 3.0", "CREATED-BY: mmtty4mac", "CALLSIGN: \(h.callsign.uppercased())"]
        if !h.contest.isEmpty { lines.append("CONTEST: \(h.contest)") }
        for c in h.categories {
            let t = c.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            lines.append(t.uppercased().hasPrefix("CATEGORY-") ? t : "CATEGORY-" + t)
        }
        if !h.locator.isEmpty { lines.append("GRID-LOCATOR: \(h.locator.uppercased())") }
        if !h.name.isEmpty { lines.append("NAME: \(h.name)") }
        let my = h.callsign.uppercased()
        for r in records.sorted(by: { $0.timeOn < $1.timeOn }) { lines.append(qsoLine(r, myCall: my)) }
        lines.append("END-OF-LOG:")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HHmm"
        return f
    }()

    static func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
    static func exch(_ serial: Int?, _ text: String?) -> String { serial.map { String(format: "%03d", $0) } ?? text ?? "" }

    static func qsoLine(_ r: QSORecord, myCall: String) -> String {
        let khz = r.frequency.map { Int(($0 / 1000).rounded(.down)) } ?? 0
        let freq = String(repeating: " ", count: max(0, 5 - String(khz).count)) + String(khz)
        var s = "QSO: \(freq) RY \(dateFmt.string(from: r.timeOn)) "
        s += pad(myCall, 13) + " " + pad(r.rstSent ?? "599", 3) + " " + pad(exch(r.serialSent, r.exchangeSent), 6) + " "
        s += pad(r.call, 13) + " " + pad(r.rstRcvd ?? "599", 3) + " " + exch(r.serialRcvd, r.exchangeRcvd)
        while s.hasSuffix(" ") { s.removeLast() }
        return s
    }
}
