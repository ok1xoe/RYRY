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

// MARK: LoTW (hand-off to TrustedQSL)

@Test func lotwExportWritesADIFWithEligibleQSOs() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lotw-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let fixed = Date(timeIntervalSince1970: 1_790_000_000)
    let r = try LoTWExport(directory: dir, now: { fixed }).write([rec("OK1A"), rec("DL1B", hz: nil)], logName: "cqww")
    #expect(r.file.lastPathComponent == "cqww-lotw-20260921-141320.adi")
    #expect(r.ids.count == 1 && r.skipped == 1)
    let text = try String(contentsOf: r.file, encoding: .utf8)
    #expect(text.contains("<CALL:4>OK1A") && !text.contains("DL1B"))
}

@Test func lotwExportNeverOverwritesAnEarlierFile() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lotw-\(UUID())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let e = LoTWExport(directory: dir, now: { Date(timeIntervalSince1970: 1_790_000_000) })
    let a = try e.write([rec("OK1A")], logName: "x"), b = try e.write([rec("OK1B")], logName: "x")
    #expect(a.file != b.file && FileManager.default.fileExists(atPath: a.file.path))
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
