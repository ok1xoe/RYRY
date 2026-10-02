// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation

/// Cabrillo 3.0 header.
public struct CabrilloHeader: Sendable, Equatable {
    public var callsign: String
    public var contest: String
    /// Entries "KEY: value"; without a prefix `CATEGORY-` is prepended (e.g. "OPERATOR: SINGLE-OP").
    public var categories: [String] = []
    public var locator = ""
    public var name = ""
    public init(callsign: String, contest: String) { self.callsign = callsign; self.contest = contest }
}

/// Log export to the Cabrillo 3.0 format (mode RY = RTTY).
public enum Cabrillo {
    /// `qtc` = QTC series (WAE) – after the QSO lines as `QTC:` (DARC: QRG MODE DATE TIME CALL-RX QTC-GRP CALL-TX TIME-QSO CALL-QSO NR-QSO).
    public static func export(_ records: [QSORecord], header h: CabrilloHeader, qtc: [QTCSeries] = []) -> String {
        var lines = ["START-OF-LOG: 3.0", "CREATED-BY: RYRY", "CALLSIGN: \(h.callsign.uppercased())"]
        if !h.contest.isEmpty { lines.append("CONTEST: \(h.contest)") }
        for c in h.categories {
            let t = c.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            if t.uppercased().hasPrefix("CATEGORY-") { lines.append(t) }
            else if t.contains(":") { lines.append("CATEGORY-" + t) }
            else { lines.append("X-CATEGORY: " + t) }        // without a key it is not a valid Cabrillo 3.0 tag
        }
        if !h.locator.isEmpty { lines.append("GRID-LOCATOR: \(h.locator.uppercased())") }
        if !h.name.isEmpty { lines.append("NAME: \(h.name)") }
        let my = h.callsign.uppercased()
        for r in records.sorted(by: { $0.timeOn < $1.timeOn }) { lines.append(qsoLine(r, myCall: my)) }
        for s in qtc.sorted(by: { $0.time < $1.time }) { lines += qtcLines(s, myCall: my) }
        lines.append("END-OF-LOG:")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HHmm"
        return f
    }()

    static func qtcLines(_ s: QTCSeries, myCall: String) -> [String] {
        let khz = s.frequency.map { Int(($0 / 1000).rounded(.down)) } ?? 0
        let freq = String(repeating: " ", count: max(0, 5 - String(khz).count)) + String(khz)
        let (rx, tx) = s.direction == .sent ? (s.counterpart, myCall) : (myCall, s.counterpart)
        let head = (s.frequency == nil ? "X-QTC: " : "QTC: ") + "\(freq) RY \(dateFmt.string(from: s.time)) "
            + pad(rx, 13) + " " + pad("\(s.number)/\(s.groupSize)", 5) + " " + pad(tx, 13) + " "
        return s.lines.map { head + $0.time + " " + pad($0.call, 13) + " " + String(format: "%03d", $0.serial) }
    }

    static func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
    /// Exchange: number and/or text (BARTG "015 1203", CQ/RJ "14 OH").
    static func exch(_ serial: Int?, _ text: String?) -> String {
        [serial.map { String(format: "%03d", $0) }, text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func qsoLine(_ r: QSORecord, myCall: String) -> String {
        let khz = r.frequency.map { Int(($0 / 1000).rounded(.down)) } ?? 0
        let freq = String(repeating: " ", count: max(0, 5 - String(khz).count)) + String(khz)
        // without a frequency the QSO line is not valid – the adjudicator skips X-QSO, but it stays in the log
        var s = (r.frequency == nil ? "X-QSO: " : "QSO: ") + "\(freq) RY \(dateFmt.string(from: r.timeOn)) "
        s += pad(myCall, 13) + " " + pad(r.rstSent ?? "599", 3) + " " + pad(exch(r.serialSent, r.exchangeSent), 6) + " "
        s += pad(r.call, 13) + " " + pad(r.rstRcvd ?? "599", 3) + " " + exch(r.serialRcvd, r.exchangeRcvd)
        while s.hasSuffix(" ") { s.removeLast() }
        return s
    }
}
