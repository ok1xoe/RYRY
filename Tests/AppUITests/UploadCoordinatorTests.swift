// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
import QSOLog
import Settings
import Upload
@testable import AppUI

private final class FakeHTTP: HTTPClient, @unchecked Sendable {
    let lock = NSLock()
    var requests: [URLRequest] = []
    let status: Int, body: String
    init(_ status: Int, _ body: String) { self.status = status; self.body = body }
    func send(_ request: URLRequest) async throws -> HTTPResult {
        lock.withLock { requests.append(request) }
        return HTTPResult(status: status, body: Data(body.utf8))
    }
}

private struct FakeOpener: TQSLOpener {
    let ok: Bool
    func open(_ file: URL) async -> Bool { ok }
}

private func downloadsDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID())")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func makeLog() async throws -> (QSOLogStore, [QSORecord]) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("upl-\(UUID())")
    let log = try QSOLogStore(directory: dir)
    var out: [QSORecord] = []
    for (i, c) in ["OK1A", "OK1B", "OK1C"].enumerated() {
        var r = QSORecord(call: c, timeOn: Date(timeIntervalSince1970: 1_790_000_000 + Double(i) * 60))
        r.frequency = 14_080_000
        try await log.append(r); out.append(r)
    }
    return (log, out)
}

private func settings(_ f: (inout AppSettings) -> Void) -> AppSettings {
    var s = AppSettings(); s.station.call = "ok1xoe"
    s.upload.eqslEnabled = true; s.upload.eqslUser = "OK1XOE"
    s.upload.clublogEnabled = true; s.upload.clublogEmail = "a@b.cz"
    s.upload.lotwEnabled = true
    f(&s); return s
}

private func secrets() throws -> UploadMemoryStore {
    let m = UploadMemoryStore()
    try m.set("pw", service: SecretServices.eqsl, account: SecretServices.account)
    try m.set("pw", service: SecretServices.clublog, account: SecretServices.account)
    try m.set("key", service: SecretServices.clublogAPIKey, account: SecretServices.account)
    return m
}

@Test func eqslUploadMarksRecordsAndSecondRunHasNothingToDo() async throws {
    let (log, _) = try await makeLog()
    let http = FakeHTTP(200, "Result: 3 out of 3 records added")
    let c = UploadCoordinator(http: http, secrets: try secrets())
    let msg = try await c.uploadPending(.eqsl, settings: settings { _ in }, log: log)
    #expect(msg.contains("3"))
    #expect(await log.records.allSatisfy { $0.isUploaded(.eqsl) && !$0.isUploaded(.lotw) })
    let again = try await c.uploadPending(.eqsl, settings: settings { _ in }, log: log)
    #expect(http.requests.count == 1 && !again.isEmpty)
}

@Test func failedUploadLeavesStateUntouched() async throws {
    let (log, _) = try await makeLog()
    let c = UploadCoordinator(http: FakeHTTP(403, "no"), secrets: try secrets())
    await #expect(throws: UploadError.self) { _ = try await c.uploadPending(.clublog, settings: settings { _ in }, log: log) }
    #expect(await log.records.allSatisfy { $0.uploads == nil })
}

@Test func disabledServiceOrMissingSecretsAreErrors() async throws {
    let (log, _) = try await makeLog()
    let c = UploadCoordinator(http: FakeHTTP(200, "OK"), secrets: UploadMemoryStore())
    await #expect(throws: UploadError.self) { _ = try await c.uploadPending(.eqsl, settings: settings { $0.upload.eqslEnabled = false }, log: log) }
    await #expect(throws: UploadError.self) { _ = try await c.uploadPending(.eqsl, settings: settings { _ in }, log: log) }   // without a password
    await #expect(throws: UploadError.self) { _ = try await c.uploadPending(.clublog, settings: settings { _ in }, log: log) }
}

@Test func lotwIsPreparedForTQSLAndNothingIsMarkedUntilConfirmed() async throws {
    let (log, _) = try await makeLog()
    let c = UploadCoordinator(http: FakeHTTP(200, ""), secrets: UploadMemoryStore(), tqsl: FakeOpener(ok: true), downloads: downloadsDir())
    let h = try #require(try await c.prepareLoTW(settings: settings { _ in }, log: log, logName: "cq"))
    #expect(h.openedInTQSL && h.ids.count == 3 && FileManager.default.fileExists(atPath: h.file.path))
    #expect(await log.records.allSatisfy { !$0.isUploaded(.lotw) })
    await #expect(throws: UploadError.self) { _ = try await c.uploadPending(.lotw, settings: settings { _ in }, log: log) }
}

@Test func lotwWithoutTQSLStillWritesTheFileAndMarksNothing() async throws {
    let (log, _) = try await makeLog()
    let c = UploadCoordinator(http: FakeHTTP(200, ""), secrets: UploadMemoryStore(), tqsl: FakeOpener(ok: false), downloads: downloadsDir())
    let h = try #require(try await c.prepareLoTW(settings: settings { _ in }, log: log, logName: "cq"))
    #expect(!h.openedInTQSL && FileManager.default.fileExists(atPath: h.file.path))
    #expect(await log.records.allSatisfy { !$0.isUploaded(.lotw) })
}

@Test func lotwWithNothingPendingOrDisabledPreparesNothing() async throws {
    let (log, recs) = try await makeLog()
    let c = UploadCoordinator(http: FakeHTTP(200, ""), secrets: UploadMemoryStore(), tqsl: FakeOpener(ok: true), downloads: downloadsDir())
    await #expect(throws: UploadError.self) { _ = try await c.prepareLoTW(settings: settings { $0.upload.lotwEnabled = false }, log: log, logName: "cq") }
    try await log.markUploaded(ids: recs.map(\.id), target: .lotw)
    #expect(try await c.prepareLoTW(settings: settings { _ in }, log: log, logName: "cq") == nil)
}

@Test func autoFlagRequiresEnabledAndDefaultsOff() {
    let d = UploadSettings()
    for t in UploadTarget.allCases { #expect(!UploadCoordinator.isEnabled(t, d) && !UploadCoordinator.isAuto(t, d)) }
    var s = UploadSettings(); s.eqslAuto = true
    #expect(!UploadCoordinator.isAuto(.eqsl, s))
    s.eqslEnabled = true
    #expect(UploadCoordinator.isAuto(.eqsl, s) && !UploadCoordinator.isAuto(.lotw, s))
    s.lotwEnabled = true
    #expect(!UploadCoordinator.isAuto(.lotw, s))                     // LoTW needs the user in TQSL - never automatic
}

@Test func uploadSettingsTolerantDecodeAndRoundTrip() throws {
    let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
    #expect(old.upload == UploadSettings())
    var s = AppSettings(); s.upload.clublogEmail = "x@y.cz"; s.upload.clublogAuto = true
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    #expect(back.upload.clublogEmail == "x@y.cz" && back.upload.clublogAuto)
    let bad = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"upload":{"eqslEnabled":"ano","eqslUser":"A"}}"#.utf8))
    #expect(!bad.upload.eqslEnabled && bad.upload.eqslUser == "A")
}
