// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

public enum ADIF {
    static let version = "3.1.4"

    static func field(_ name: String, _ value: String?) -> String {
        guard let v = value, !v.isEmpty else { return "" }
        return "<\(name):\(v.utf8.count)>\(v) "
    }

    static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd"; return f
    }()
    static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HHmmss"; return f
    }()

    public static func header(now: Date = Date()) -> String {
        "mmtty4mac ADIF export\n" + field("ADIF_VER", version) + field("PROGRAMID", "mmtty4mac")
            + field("PROGRAMVERSION", "0.1") + field("CREATED_TIMESTAMP", dateFmt.string(from: now) + " " + timeFmt.string(from: now))
            + "<EOH>\n"
    }

    public static func record(_ r: QSORecord) -> String {
        var s = field("CALL", r.call)
        s += field("QSO_DATE", dateFmt.string(from: r.timeOn)) + field("TIME_ON", timeFmt.string(from: r.timeOn))
        if let t = r.timeOff { s += field("QSO_DATE_OFF", dateFmt.string(from: t)) + field("TIME_OFF", timeFmt.string(from: t)) }
        if let f = r.frequency { s += field("FREQ", String(format: "%.6f", f / 1e6)) }
        s += field("BAND", r.band) + field("MODE", r.mode) + field("SUBMODE", r.submode)
        s += field("RST_SENT", r.rstSent) + field("RST_RCVD", r.rstRcvd)
        s += field("NAME", r.name) + field("QTH", r.qth) + field("GRIDSQUARE", r.grid)
        s += field("STX", r.serialSent.map(String.init)) + field("SRX", r.serialRcvd.map(String.init))
        s += field("STX_STRING", r.exchangeSent) + field("SRX_STRING", r.exchangeRcvd)
        s += field("COMMENT", r.comment) + field("STATION_CALLSIGN", r.stationCallsign)
        s += field("APP_MMTTY4MAC_ID", r.id.uuidString)
        return s + "<EOR>\n"
    }

    /// Rozparsuje záznamy (za <EOH>). Délky jsou v bajtech UTF-8.
    public static func parse(_ text: String) -> [[String: String]] {
        let b = Array(text.utf8)
        var i = 0
        if let r = text.range(of: "<EOH>", options: .caseInsensitive) {
            i = text.utf8.distance(from: text.utf8.startIndex, to: r.upperBound)
        } else if !text.hasPrefix("<") { return [] }
        var out: [[String: String]] = []
        var cur: [String: String] = [:]
        while i < b.count {
            guard b[i] == UInt8(ascii: "<") else { i += 1; continue }
            guard let close = b[i...].firstIndex(of: UInt8(ascii: ">")) else { break }
            let spec = String(decoding: b[(i + 1)..<close], as: UTF8.self)
            let parts = spec.split(separator: ":")
            let name = parts.first.map { $0.uppercased() } ?? ""
            i = close + 1
            if name == "EOR" { out.append(cur); cur = [:]; continue }
            if parts.count >= 2, let len = Int(parts[1]), len >= 0, len <= b.count - i {
                cur[name] = String(decoding: b[i..<(i + len)], as: UTF8.self)
                i += len
            }
        }
        return out
    }
}
