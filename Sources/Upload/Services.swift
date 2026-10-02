// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Localization
import QSOLog

// MARK: eQSL

/// eQSL: a multipart POST to ImportADIF.cfm (file `Filename`); the EQSL_USER/EQSL_PSWD login in the ADIF header
/// (as the eQSL documentation says) and, just in case, as form fields too.
public struct EQSLUploader: Sendable {
    public static let defaultURL = URL(string: "https://www.eQSL.cc/qslcard/ImportADIF.cfm")!
    let http: HTTPClient, url: URL, user: String, password: String
    public init(http: HTTPClient, user: String, password: String, url: URL = EQSLUploader.defaultURL) {
        self.http = http; self.user = user; self.password = password; self.url = url
    }

    public struct Parsed: Equatable, Sendable {
        public var added: Int?, total: Int?
        public var errors: [String] = [], warnings: [String] = []
        public var loginFailed = false
    }

    /// Parses the HTML response ("Result: X out of Y records added", the Error:/Warning: lines).
    public static func parse(_ html: String) -> Parsed {
        var p = Parsed()
        let text = html.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
        if let m = text.range(of: #"Result:\s*(\d+)\s+out of\s+(\d+)\s+records? added"#, options: [.regularExpression, .caseInsensitive]) {
            let nums = text[m].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if nums.count == 2 { p.added = nums[0]; p.total = nums[1] }
        }
        for raw in text.split(whereSeparator: \.isNewline) {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.lowercased().hasPrefix("error") {
                p.errors.append(l)
                if l.lowercased().contains("no match on username") || l.lowercased().contains("password") { p.loginFailed = true }
            } else if l.lowercased().hasPrefix("warning") { p.warnings.append(l) }
        }
        return p
    }

    public func upload(_ records: [QSORecord]) async throws -> UploadOutcome {
        let (eligible, missing) = (records.filter { $0.band != nil }, records.filter { $0.band == nil }.count)
        guard !eligible.isEmpty else {
            return UploadOutcome(target: .eqsl, uploadedIDs: [], skipped: missing, message: L("eQSL: není co nahrát."))
        }
        let header = ADIF.field("EQSL_USER", user) + ADIF.field("EQSL_PSWD", password)
        var mp = MultipartBody()
        mp.addField("EQSL_USER", user); mp.addField("EQSL_PSWD", password)
        mp.addFile("Filename", filename: "RYRY.adi", Data(UploadSelection.adif(eligible, headerFields: header).utf8))
        let res = try await http.send(mp.request(url: url))
        guard (200..<300).contains(res.status) else { throw UploadError.http(res.status, String(res.text.prefix(200))) }
        let p = Self.parse(res.text)
        if p.loginFailed && p.added == nil { throw UploadError.authFailed(p.errors.first ?? "eQSL") }
        guard let added = p.added, let total = p.total else {
            if let e = p.errors.first { throw UploadError.rejected(e) }
            throw UploadError.unexpectedResponse(String(res.text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)))
        }
        // nothing added and only errors (no duplicates) → the records are wrong, do not mark them
        let dupes = p.warnings.contains { $0.lowercased().contains("duplicate") }
        if added == 0, total > 0, !p.errors.isEmpty, !dupes { throw UploadError.rejected(p.errors.first!) }
        var msg = L("eQSL: přidáno %ld z %ld záznamů.", added, total)
        if !p.errors.isEmpty { msg += " " + L("Chyb: %ld (první: %@).", p.errors.count, p.errors[0]) }
        if dupes { msg += " " + L("Duplicity byly přeskočeny.") }
        return UploadOutcome(target: .eqsl, uploadedIDs: eligible.map(\.id), skipped: missing, message: msg)
    }
}

// MARK: Club Log

public struct ClubLogUploader: Sendable {
    public static let realtimeURL = URL(string: "https://clublog.org/realtime.php")!
    public static let putLogsURL = URL(string: "https://clublog.org/putlogs.php")!
    let http: HTTPClient
    let email: String, password: String, callsign: String, apiKey: String
    let realtime: URL, putlogs: URL
    public init(http: HTTPClient, email: String, password: String, callsign: String, apiKey: String,
                realtimeURL: URL = ClubLogUploader.realtimeURL, putLogsURL: URL = ClubLogUploader.putLogsURL) {
        self.http = http; self.email = email; self.password = password; self.callsign = callsign; self.apiKey = apiKey
        self.realtime = realtimeURL; self.putlogs = putLogsURL
    }

    /// 200 OK, 400 (bad data), 403 (login/key), anything else = a server error.
    static func check(_ r: HTTPResult) throws {
        switch r.status {
        case 200: return
        case 400: throw UploadError.rejected(String(r.text.prefix(200)))
        case 403: throw UploadError.authFailed(String(r.text.prefix(200)).isEmpty ? "Club Log (403)" : String(r.text.prefix(200)))
        default: throw UploadError.http(r.status, String(r.text.prefix(200)))
        }
    }

    /// A single QSO right away (realtime.php).
    public func uploadRealtime(_ r: QSORecord) async throws {
        let req = FormBody.request(url: realtime, [("email", email), ("password", password), ("callsign", callsign),
                                                   ("adif", ADIF.uploadRecord(r)), ("api", apiKey)])
        try Self.check(try await http.send(req))
    }

    /// A batch as a file (putlogs.php).
    public func uploadBatch(_ records: [QSORecord]) async throws {
        var mp = MultipartBody()
        mp.addField("email", email); mp.addField("password", password); mp.addField("callsign", callsign); mp.addField("api", apiKey)
        mp.addFile("file", filename: "RYRY.adi", Data(UploadSelection.adif(records).utf8))
        try Self.check(try await http.send(mp.request(url: putlogs)))
    }

    public func upload(_ records: [QSORecord]) async throws -> UploadOutcome {
        let eligible = records.filter { $0.band != nil }, missing = records.count - eligible.count
        guard !eligible.isEmpty else {
            return UploadOutcome(target: .clublog, uploadedIDs: [], skipped: missing, message: L("Club Log: není co nahrát."))
        }
        if eligible.count == 1 { try await uploadRealtime(eligible[0]) } else { try await uploadBatch(eligible) }
        return UploadOutcome(target: .clublog, uploadedIDs: eligible.map(\.id), skipped: missing,
                             message: L("Club Log: nahráno %ld spojení.", eligible.count))
    }
}

// MARK: LoTW (hand-off to TrustedQSL)

/// LoTW needs the QSOs signed with the user's certificate, which only TrustedQSL can do. The App Store sandbox
/// cannot run the tqsl program, so RYRY writes the QSOs not uploaded yet into an ADIF file and hands it to TQSL;
/// the user signs and sends it there and confirms in RYRY.
public struct LoTWExport: Sendable {
    let directory: URL
    let now: @Sendable () -> Date
    public init(directory: URL, now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory; self.now = now
    }

    /// Writes the QSOs with a band into `<directory>/<logName>-lotw-<yyyyMMdd-HHmmss>.adi` (UTC); an existing file is
    /// never overwritten (`-2`, `-3`… is appended). Returns the file, the IDs written and how many were skipped (no band).
    public func write(_ records: [QSORecord], logName: String) throws -> (file: URL, ids: [UUID], skipped: Int) {
        let eligible = records.filter { $0.band != nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(logName)-lotw-\(f.string(from: now()))"
        var file = directory.appendingPathComponent(base + ".adi"), n = 2
        while FileManager.default.fileExists(atPath: file.path) {
            file = directory.appendingPathComponent("\(base)-\(n).adi"); n += 1
        }
        try Data(UploadSelection.adif(eligible).utf8).write(to: file, options: .withoutOverwriting)
        return (file, eligible.map(\.id), records.count - eligible.count)
    }
}

/// Opens an ADIF file in TrustedQSL (the real one uses NSWorkspace in AppUI).
public protocol TQSLOpener: Sendable {
    /// false = TrustedQSL is not installed.
    func open(_ file: URL) async -> Bool
}
