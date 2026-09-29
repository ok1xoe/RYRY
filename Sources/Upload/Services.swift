// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Localization
import QSOLog

// MARK: eQSL

/// eQSL: multipart POST na ImportADIF.cfm (soubor `Filename`); přihlášení EQSL_USER/EQSL_PSWD v hlavičce ADIF
/// (podle dokumentace eQSL) a pro jistotu i jako pole formuláře.
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

    /// Vyparsuje HTML odpověď („Result: X out of Y records added“, řádky Error:/Warning:).
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
        mp.addFile("Filename", filename: "mmtty4mac.adi", Data(UploadSelection.adif(eligible, headerFields: header).utf8))
        let res = try await http.send(mp.request(url: url))
        guard (200..<300).contains(res.status) else { throw UploadError.http(res.status, String(res.text.prefix(200))) }
        let p = Self.parse(res.text)
        if p.loginFailed && p.added == nil { throw UploadError.authFailed(p.errors.first ?? "eQSL") }
        guard let added = p.added, let total = p.total else {
            if let e = p.errors.first { throw UploadError.rejected(e) }
            throw UploadError.unexpectedResponse(String(res.text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)))
        }
        // nic nepřidáno a jen chyby (ne duplicity) → záznamy jsou špatně, neoznačovat
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

    /// 200 OK, 400 (špatná data), 403 (přihlášení/klíč), ostatní = chyba serveru.
    static func check(_ r: HTTPResult) throws {
        switch r.status {
        case 200: return
        case 400: throw UploadError.rejected(String(r.text.prefix(200)))
        case 403: throw UploadError.authFailed(String(r.text.prefix(200)).isEmpty ? "Club Log (403)" : String(r.text.prefix(200)))
        default: throw UploadError.http(r.status, String(r.text.prefix(200)))
        }
    }

    /// Jedno spojení hned (realtime.php).
    public func uploadRealtime(_ r: QSORecord) async throws {
        let req = FormBody.request(url: realtime, [("email", email), ("password", password), ("callsign", callsign),
                                                   ("adif", ADIF.uploadRecord(r)), ("api", apiKey)])
        try Self.check(try await http.send(req))
    }

    /// Dávka souborem (putlogs.php).
    public func uploadBatch(_ records: [QSORecord]) async throws {
        var mp = MultipartBody()
        mp.addField("email", email); mp.addField("password", password); mp.addField("callsign", callsign); mp.addField("api", apiKey)
        mp.addFile("file", filename: "mmtty4mac.adi", Data(UploadSelection.adif(records).utf8))
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

// MARK: LoTW (TQSL)

public struct ProcessResult: Sendable, Equatable {
    public var status: Int32
    public var output: String
    public init(status: Int32, output: String) { self.status = status; self.output = output }
}

public protocol ProcessRunner: Sendable {
    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult
}

/// Skutečný spouštěč (Foundation.Process); po vypršení limitu proces ukončí.
public struct SystemProcessRunner: ProcessRunner {
    public init() {}
    public func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                let p = Process(), pipe = Pipe()
                p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments
                p.standardOutput = pipe; p.standardError = pipe; p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(throwing: UploadError.tqslNotFound); return }
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit(); killer.cancel()
                cont.resume(returning: ProcessResult(status: p.terminationStatus, output: String(decoding: data, as: UTF8.self)))
            }
        }
    }
}

public enum TQSLLocator {
    public static let standardPaths = ["/Applications/TrustedQSL/tqsl.app/Contents/MacOS/tqsl",
                                       "/Applications/tqsl.app/Contents/MacOS/tqsl",
                                       "/opt/homebrew/bin/tqsl", "/usr/local/bin/tqsl"]
    /// Zadaná cesta → standardní místa → PATH.
    public static func find(custom: String?, path: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
                            isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        var c: [String] = []
        if let custom, !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            let t = (custom as NSString).expandingTildeInPath
            c.append(t)
            // zadán balíček tqsl.app
            if t.hasSuffix(".app") { c.append(t + "/Contents/MacOS/tqsl") }
        }
        c += standardPaths + path.split(separator: ":").map { String($0) + "/tqsl" }
        return c.first(where: isExecutable)
    }
}

/// LoTW přes TQSL: `tqsl -d -q -u -a compliant -l "<lokace>" -x <soubor.adi>` (-d bez dialogu s rozsahem dat,
/// -q/-x dávkový režim, -u nahrát po podpisu, -a compliant = už nahrané a mimo rozsah přeskočit, -l Station Location).
/// Návratové kódy: 0 = OK; 8 = vše už bylo nahráno / mimo rozsah; 9 a 14 = část už nahrána (ostatní odeslána).
public struct LoTWUploader: Sendable {
    let runner: ProcessRunner
    let tqslPath: String?, location: String
    let tempDirectory: URL, isExecutable: @Sendable (String) -> Bool
    let timeout: TimeInterval
    public init(runner: ProcessRunner, tqslPath: String?, location: String,
                tempDirectory: URL = FileManager.default.temporaryDirectory, timeout: TimeInterval = 180,
                isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.runner = runner; self.tqslPath = tqslPath; self.location = location
        self.tempDirectory = tempDirectory; self.timeout = timeout; self.isExecutable = isExecutable
    }

    static let okCodes: Set<Int> = [0, 8, 9, 14]

    static func arguments(location: String, file: String) -> [String] {
        ["-d", "-q", "-u", "-a", "compliant", "-l", location, "-x", file]
    }

    /// Poslední řádek „Final Status: popis (kód)“ z výstupu TQSL.
    static func finalStatus(_ out: String) -> String? {
        out.split(whereSeparator: \.isNewline).last { $0.contains("Final Status:") }
            .map { String($0).components(separatedBy: "Final Status:").last!.trimmingCharacters(in: .whitespaces) }
    }

    public func upload(_ records: [QSORecord]) async throws -> UploadOutcome {
        let eligible = records.filter { $0.band != nil }, missing = records.count - eligible.count
        guard !eligible.isEmpty else {
            return UploadOutcome(target: .lotw, uploadedIDs: [], skipped: missing, message: L("LoTW: není co nahrát."))
        }
        guard !location.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw UploadError.notConfigured(L("název Station Location pro LoTW"))
        }
        guard let exe = TQSLLocator.find(custom: tqslPath, isExecutable: isExecutable) else { throw UploadError.tqslNotFound }
        let file = tempDirectory.appendingPathComponent("mmtty4mac-lotw-\(UUID().uuidString).adi")
        try Data(UploadSelection.adif(eligible).utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let res = try await runner.run(executable: exe, arguments: Self.arguments(location: location, file: file.path), timeout: timeout)
        let status = Self.finalStatus(res.output)
        guard Self.okCodes.contains(Int(res.status)) else {
            throw UploadError.tqsl(code: Int(res.status), message: status ?? String(res.output.suffix(200)))
        }
        let msg: String
        switch res.status {
        case 0: msg = L("LoTW: odesláno %ld spojení (TQSL).", eligible.count)
        case 8: msg = L("LoTW: spojení už byla nahrána nebo jsou mimo rozsah dat.")
        default: msg = L("LoTW: část spojení už byla nahrána, zbytek odeslán.")
        }
        return UploadOutcome(target: .lotw, uploadedIDs: eligible.map(\.id), skipped: missing, message: msg)
    }
}
