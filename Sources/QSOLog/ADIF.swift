// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

public enum ADIF {
    public static let version = "3.1.4"

    public static func field(_ name: String, _ value: String?) -> String {
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
            + field("PROGRAMVERSION", "0.16.0") + field("CREATED_TIMESTAMP", dateFmt.string(from: now) + " " + timeFmt.string(from: now))
            + "<EOH>\n"
    }

    /// Record for the persistent log/export: also with upload flags (LOTW_QSL_SENT, EQSL_QSL_SENT, CLUBLOG_QSO_UPLOAD_STATUS + dates).
    public static func record(_ r: QSORecord) -> String { record(r, includeUploadStatus: true) }
    /// Record for sending to a service: without upload flags.
    public static func uploadRecord(_ r: QSORecord) -> String { record(r, includeUploadStatus: false) }

    static func record(_ r: QSORecord, includeUploadStatus: Bool) -> String {
        var s = field("CALL", r.call)
        s += field("QSO_DATE", dateFmt.string(from: r.timeOn)) + field("TIME_ON", timeFmt.string(from: r.timeOn))
        if let t = r.timeOff { s += field("QSO_DATE_OFF", dateFmt.string(from: t)) + field("TIME_OFF", timeFmt.string(from: t)) }
        if let f = r.frequency { s += field("FREQ", String(format: "%.6f", f / 1e6)) }
        s += field("BAND", r.band) + field("MODE", r.mode) + field("SUBMODE", r.submode)
        s += field("RST_SENT", r.rstSent) + field("RST_RCVD", r.rstRcvd)
        s += field("NAME", r.name) + field("QTH", r.qth) + field("GRIDSQUARE", r.grid)
        s += field("STX", r.serialSent.map(String.init)) + field("SRX", r.serialRcvd.map(String.init))
        s += field("STX_STRING", r.exchangeSent) + field("SRX_STRING", r.exchangeRcvd)
        s += field("COUNTRY", r.country) + field("CONT", r.continent)
        s += field("CQZ", r.cqZone.map(String.init)) + field("ITUZ", r.ituZone.map(String.init))
        s += field("COMMENT", r.comment) + field("STATION_CALLSIGN", r.stationCallsign)
        s += field("APP_MMTTY4MAC_ID", r.id.uuidString)
        if includeUploadStatus {
            for (t, sent, date) in uploadFields {
                if let d = r.uploads?[t.rawValue] { s += field(sent.0, sent.1) + field(date, dateFmt.string(from: d)) }
            }
        }
        return s + "<EOR>\n"
    }

    static let uploadFields: [(UploadTarget, (String, String), String)] = [
        (.lotw, ("LOTW_QSL_SENT", "Y"), "LOTW_QSLSDATE"),
        (.eqsl, ("EQSL_QSL_SENT", "Y"), "EQSL_QSLSDATE"),
        (.clublog, ("CLUBLOG_QSO_UPLOAD_STATUS", "Y"), "CLUBLOG_QSO_UPLOAD_DATE"),
    ]

    /// Parses the records (after <EOH>). Lengths are in UTF-8 bytes.
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

// MARK: Import (MMTTY and other programs export ADIF)

extension ADIF {
    public struct ImportResult: Sendable { public var records: [QSORecord]; public var skipped: Int }

    /// ADIF records → QSOs. A record without a call or without a date/time is skipped.
    /// Band only without a frequency → frequency = the lower band edge (in the log the band is derived from the frequency).
    public static func importRecords(_ text: String) -> ImportResult {
        var out: [QSORecord] = [], skipped = 0
        for f in parse(text) {
            guard let call = f["CALL"].map(QSORecord.normalizeCall), !call.isEmpty,
                  let on = date(f["QSO_DATE"], f["TIME_ON"]) else { skipped += 1; continue }
            let id = f["APP_MMTTY4MAC_ID"].flatMap(UUID.init(uuidString:)) ?? UUID()
            var r = QSORecord(id: id, call: call, timeOn: on, mode: (f["MODE"] ?? "RTTY").uppercased())
            r.timeOff = date(f["QSO_DATE_OFF"] ?? f["QSO_DATE"], f["TIME_OFF"])
            if let mhz = f["FREQ"].flatMap(Double.init) { r.frequency = mhz * 1e6 }
            else if let b = f["BAND"]?.lowercased(), let row = Bands.table.first(where: { $0.0 == b }) { r.frequency = row.1 * 1e6 }
            func s(_ k: String) -> String? { f[k].flatMap { $0.isEmpty ? nil : $0 } }
            r.submode = s("SUBMODE"); r.rstSent = s("RST_SENT"); r.rstRcvd = s("RST_RCVD")
            r.name = s("NAME"); r.qth = s("QTH"); r.grid = s("GRIDSQUARE")
            r.serialSent = s("STX").flatMap { Int($0) }; r.serialRcvd = s("SRX").flatMap { Int($0) }
            r.exchangeSent = s("STX_STRING"); r.exchangeRcvd = s("SRX_STRING")
            r.comment = s("COMMENT") ?? s("NOTES"); r.stationCallsign = s("STATION_CALLSIGN")
            r.country = s("COUNTRY"); r.continent = s("CONT")
            r.cqZone = s("CQZ").flatMap { Int($0) }; r.ituZone = s("ITUZ").flatMap { Int($0) }
            for (t, sent, dateKey) in uploadFields where f[sent.0]?.uppercased() == sent.1 {
                r.markUploaded(t, at: date(f[dateKey], "000000") ?? on)
            }
            out.append(r)
        }
        return ImportResult(records: out, skipped: skipped)
    }

    /// QSO_DATE (yyyyMMdd) + TIME_ON (HHmm or HHmmss), UTC.
    static func date(_ d: String?, _ t: String?) -> Date? {
        guard let d, d.count == 8, let t, t.count == 4 || t.count == 6 else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = t.count == 4 ? "yyyyMMddHHmm" : "yyyyMMddHHmmss"
        return f.date(from: d + t)
    }
}
