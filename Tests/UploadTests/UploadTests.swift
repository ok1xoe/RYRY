import Foundation
import Testing
import QSOLog
@testable import Upload

final class MockHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    var replies: [Result<HTTPResult, Error>]
    init(_ replies: [Result<HTTPResult, Error>]) { self.replies = replies }
    convenience init(status: Int, body: String) { self.init([.success(HTTPResult(status: status, body: Data(body.utf8)))]) }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        try lock.withLock {
            requests.append(request)
            let r = replies.count > 1 ? replies.removeFirst() : replies[0]
            return try r.get()
        }
    }
    var bodyText: String { String(decoding: requests.last?.httpBody ?? Data(), as: UTF8.self) }
}

final class MockRunner: ProcessRunner, @unchecked Sendable {
    var result: Result<ProcessResult, Error>
    private(set) var calls: [(String, [String])] = []
    private(set) var fileContent: String?
    init(_ r: Result<ProcessResult, Error>) { result = r }
    func run(executable: String, arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        calls.append((executable, arguments))
        if let f = arguments.last { fileContent = try? String(contentsOfFile: f, encoding: .utf8) }
        return try result.get()
    }
}

func rec(_ call: String, hz: Double? = 14_080_000, t: TimeInterval = 1_790_000_000) -> QSORecord {
    var r = QSORecord(call: call, timeOn: Date(timeIntervalSince1970: t))
    r.frequency = hz; r.rstSent = "599"; r.rstRcvd = "599"
    return r
}

// MARK: selection

@Test func pendingSelectsOnlyNotUploadedWithBand() {
    var a = rec("OK1A"), b = rec("OK1B", t: 1_790_000_100), c = rec("OK1C", hz: nil, t: 1_790_000_200)
    a.markUploaded(.eqsl)
    b.markUploaded(.lotw)
    let all = [a, b, c]
    let e = UploadSelection.pending(all, target: .eqsl)
    #expect(e.eligible.map(\.call) == ["OK1B"] && e.missingBand == 1)
    let l = UploadSelection.pending(all, target: .lotw)
    #expect(l.eligible.map(\.call) == ["OK1A"] && l.missingBand == 1)
    #expect(UploadSelection.pending(all, target: .clublog).eligible.count == 2)
}

// MARK: multipart

@Test func multipartBodyIsWellFormed() {
    var m = MultipartBody(boundary: "BND")
    m.addField("user", "ok1xoe")
    m.addFile("Filename", filename: "a.adi", Data("<EOR>".utf8))
    let s = String(decoding: m.body, as: UTF8.self)
    #expect(m.contentType == "multipart/form-data; boundary=BND")
    #expect(s == "--BND\r\nContent-Disposition: form-data; name=\"user\"\r\n\r\nok1xoe\r\n"
            + "--BND\r\nContent-Disposition: form-data; name=\"Filename\"; filename=\"a.adi\"\r\nContent-Type: text/plain\r\n\r\n<EOR>\r\n"
            + "--BND--\r\n")
    let r = m.request(url: URL(string: "https://x.test/")!)
    #expect(r.httpMethod == "POST" && r.value(forHTTPHeaderField: "Content-Type") == m.contentType)
}

@Test func formBodyEncodesReservedCharacters() {
    let r = FormBody.request(url: URL(string: "https://x.test/")!, [("email", "a+b@x.cz"), ("adif", "<CALL:4>OK1A &")])
    #expect(String(decoding: r.httpBody!, as: UTF8.self) == "email=a%2Bb%40x.cz&adif=%3CCALL%3A4%3EOK1A%20%26")
}

// MARK: eQSL

@Test func eqslParsesResult() {
    let html = "<html><body><p>Result: 2 out of 3 records added</p><li>Warning: Bad record: 1</li><li>Error: Bad Mode</li></body></html>"
    let p = EQSLUploader.parse(html)
    #expect(p.added == 2 && p.total == 3 && p.errors == ["Error: Bad Mode"] && p.warnings.count == 1 && !p.loginFailed)
    #expect(EQSLUploader.parse("Error: No match on Username/Password").loginFailed)
}

@Test func eqslUploadSendsFileAndMarksAll() async throws {
    let http = MockHTTP(status: 200, body: "<HTML>Result: 2 out of 2 records added</HTML>")
    let up = EQSLUploader(http: http, user: "OK1XOE", password: "tajne")
    let o = try await up.upload([rec("OK1A"), rec("OK1B"), rec("NOBAND", hz: nil)])
    #expect(o.uploadedIDs.count == 2 && o.skipped == 1 && o.target == .eqsl)
    let body = http.bodyText
    #expect(body.contains("name=\"Filename\"") && body.contains("<EQSL_USER:6>OK1XOE") && body.contains("<EQSL_PSWD:5>tajne"))
    #expect(body.contains("<CALL:4>OK1A") && !body.contains("NOBAND") && body.contains("<EOH>"))
    #expect(http.requests[0].url?.host?.lowercased() == "www.eqsl.cc")
}

@Test func eqslErrors() async {
    let bad = EQSLUploader(http: MockHTTP(status: 200, body: "Error: No match on Username/Password"), user: "a", password: "b")
    await #expect(throws: UploadError.self) { _ = try await bad.upload([rec("OK1A")]) }
    let down = EQSLUploader(http: MockHTTP(status: 503, body: "busy"), user: "a", password: "b")
    await #expect(throws: UploadError.http(503, "busy")) { _ = try await down.upload([rec("OK1A")]) }
    let junk = EQSLUploader(http: MockHTTP(status: 200, body: "<html>hello</html>"), user: "a", password: "b")
    await #expect(throws: UploadError.self) { _ = try await junk.upload([rec("OK1A")]) }
    let none = EQSLUploader(http: MockHTTP(status: 200, body: "Result: 0 out of 1 records added<li>Error: Bad record</li>"), user: "a", password: "b")
    await #expect(throws: UploadError.rejected("Error: Bad record")) { _ = try await none.upload([rec("OK1A")]) }
    // dupes are not an error
    let dup = EQSLUploader(http: MockHTTP(status: 200, body: "Result: 0 out of 1 records added<li>Warning: Duplicate</li>"), user: "a", password: "b")
    let o = try? await dup.upload([rec("OK1A")])
    #expect(o?.uploadedIDs.count == 1)
}

// MARK: Club Log

func clublog(_ http: MockHTTP) -> ClubLogUploader {
    ClubLogUploader(http: http, email: "a@b.cz", password: "pw", callsign: "OK1XOE", apiKey: "KEY123")
}

@Test func clublogRealtimeForSingleRecord() async throws {
    let http = MockHTTP(status: 200, body: "OK")
    let o = try await clublog(http).upload([rec("OK1A")])
    #expect(o.uploadedIDs.count == 1)
    let r = http.requests[0]
    #expect(r.url?.absoluteString == "https://clublog.org/realtime.php")
    let b = http.bodyText
    #expect(b.contains("email=a%40b.cz") && b.contains("api=KEY123") && b.contains("callsign=OK1XOE") && b.contains("adif=%3CCALL%3A4%3EOK1A"))
}

@Test func clublogBatchUsesMultipart() async throws {
    let http = MockHTTP(status: 200, body: "OK")
    let o = try await clublog(http).upload([rec("OK1A"), rec("OK1B")])
    #expect(o.uploadedIDs.count == 2)
    #expect(http.requests[0].url?.absoluteString == "https://clublog.org/putlogs.php")
    let b = http.bodyText
    #expect(b.contains("name=\"file\"") && b.contains("name=\"api\"") && b.contains("KEY123") && b.contains("<CALL:4>OK1B"))
}

@Test func clublogStatusCodes() async {
    for (code, expected) in [(400, UploadError.rejected("bad adif")), (403, .authFailed("bad adif")), (500, .http(500, "bad adif"))] {
        let http = MockHTTP(status: code, body: "bad adif")
        await #expect(throws: expected) { _ = try await clublog(http).upload([rec("OK1A")]) }
    }
    let net = MockHTTP([.failure(UploadError.network("offline"))])
    await #expect(throws: UploadError.network("offline")) { _ = try await clublog(net).upload([rec("OK1A")]) }
}

// MARK: LoTW / TQSL

@Test func tqslArgumentsAndTempFile() async throws {
    let runner = MockRunner(.success(ProcessResult(status: 0, output: "Final Status: Success (0)")))
    let up = LoTWUploader(runner: runner, tqslPath: "/fake/tqsl", location: "Doma OK1XOE", isExecutable: { $0 == "/fake/tqsl" })
    let o = try await up.upload([rec("OK1A"), rec("OK1B")])
    #expect(o.uploadedIDs.count == 2)
    let (exe, args) = runner.calls[0]
    #expect(exe == "/fake/tqsl")
    #expect(Array(args.dropLast()) == ["-d", "-q", "-u", "-a", "compliant", "-l", "Doma OK1XOE", "-x"])
    #expect(args.last!.hasSuffix(".adi"))
    #expect(runner.fileContent?.contains("<CALL:4>OK1B") == true)
    #expect(!FileManager.default.fileExists(atPath: args.last!))       // the temporary file was deleted
}

@Test func tqslExitCodes() async throws {
    func run(_ code: Int32, out: String = "") async throws -> UploadOutcome {
        let up = LoTWUploader(runner: MockRunner(.success(ProcessResult(status: code, output: out))), tqslPath: "/fake/tqsl",
                              location: "L", isExecutable: { _ in true })
        return try await up.upload([rec("OK1A")])
    }
    for ok: Int32 in [0, 8, 9, 14] { #expect(try await run(ok).uploadedIDs.count == 1) }
    for bad: Int32 in [1, 2, 4, 11] {
        do { _ = try await run(bad, out: "x\n12:00:00 PM: Final Status: LoTW Connection error (11)\n"); Issue.record("mělo selhat \(bad)") }
        catch let UploadError.tqsl(code, message) { #expect(code == Int(bad) && message == "LoTW Connection error (11)") }
    }
}

@Test func tqslMissingBinaryAndLocation() async {
    let none = LoTWUploader(runner: MockRunner(.success(ProcessResult(status: 0, output: ""))), tqslPath: "/nope/tqsl",
                            location: "L", isExecutable: { _ in false })
    await #expect(throws: UploadError.tqslNotFound) { _ = try await none.upload([rec("OK1A")]) }
    let noLoc = LoTWUploader(runner: MockRunner(.success(ProcessResult(status: 0, output: ""))), tqslPath: nil,
                             location: " ", isExecutable: { _ in true })
    await #expect(throws: UploadError.self) { _ = try await noLoc.upload([rec("OK1A")]) }
}

@Test func systemRunnerReportsMissingExecutable() async {
    await #expect(throws: UploadError.tqslNotFound) {
        _ = try await SystemProcessRunner().run(executable: "/nonexistent/tqsl", arguments: [], timeout: 5)
    }
}

@Test func systemRunnerCapturesExitStatus() async throws {
    let r = try await SystemProcessRunner().run(executable: "/bin/sh", arguments: ["-c", "echo hi; exit 9"], timeout: 5)
    #expect(r.status == 9 && r.output.contains("hi"))
}

@Test func locatorOrderCustomThenStandardThenPath() {
    let seen: Set<String> = ["/custom/tqsl", "/opt/x/tqsl", "/Applications/TrustedQSL/tqsl.app/Contents/MacOS/tqsl"]
    #expect(TQSLLocator.find(custom: "/custom/tqsl", path: "/opt/x", isExecutable: seen.contains) == "/custom/tqsl")
    #expect(TQSLLocator.find(custom: nil, path: "/opt/x", isExecutable: seen.contains) == "/Applications/TrustedQSL/tqsl.app/Contents/MacOS/tqsl")
    #expect(TQSLLocator.find(custom: "", path: "/opt/x", isExecutable: { $0 == "/opt/x/tqsl" }) == "/opt/x/tqsl")
    #expect(TQSLLocator.find(custom: nil, path: "", isExecutable: { _ in false }) == nil)
}

// MARK: Keychain

@Test func memorySecretStoreRoundTrip() throws {
    let s = UploadMemoryStore()
    #expect(s.get(service: "a", account: "b") == nil)
    try s.set("x", service: "a", account: "b")
    #expect(s.get(service: "a", account: "b") == "x")
    try s.set("", service: "a", account: "b")
    #expect(s.get(service: "a", account: "b") == nil)
}
