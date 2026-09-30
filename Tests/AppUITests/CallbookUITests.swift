import Foundation
import Testing
import AppCore
import Settings
@testable import AppUI

private let qrzLogin = #"<QRZDatabase xmlns="http://xmldata.qrz.com"><Session><Key>K1</Key></Session></QRZDatabase>"#
private let qrzBad = #"<QRZDatabase xmlns="http://xmldata.qrz.com"><Session><Error>Username/password incorrect</Error></Session></QRZDatabase>"#
private func qrzCall(_ call: String) -> String {
    #"<QRZDatabase xmlns="http://xmldata.qrz.com"><Callsign><call>\#(call)</call><fname>Tomas</fname><name>Kaplan</name><addr2>Praha</addr2><country>Czech Republic</country><grid>jo70fb</grid></Callsign><Session><Key>K1</Key></Session></QRZDatabase>"#
}

private final class Requests: @unchecked Sendable {
    private let lock = NSLock(); private var _u: [String] = []
    func add(_ s: String) { lock.withLock { _u.append(s) } }
    var all: [String] { lock.withLock { _u } }
    var lookups: [String] { all.filter { $0.contains("callsign=") } }
}

@MainActor
private func setup(fillEmptyOnly: Bool = true, autoLookup: Bool = true, kind: CallbookKind = .qrz, password: String = "pw",
                   badLogin: Bool = false, delay: Duration = .milliseconds(120)) async -> (Fixture, Requests) {
    let f = Fixture()
    let req = Requests()
    f.callbookDelay = delay
    f.configure = { s in
        s.callbook.service = kind; s.callbook.username = "ok1xoe"
        s.callbook.autoLookup = autoLookup; s.callbook.fillEmptyOnly = fillEmptyOnly
    }
    try? f.secrets.setPassword(password, service: kind.rawValue, account: "ok1xoe")
    f.callbookFetcher = { url in
        let s = url.absoluteString
        req.add(s)
        if s.contains("username=") { return Data((badLogin ? qrzBad : qrzLogin).utf8) }
        let call = s.components(separatedBy: "callsign=").last ?? ""
        return Data(qrzCall(call).utf8)
    }
    await f.model.start()
    return (f, req)
}

@MainActor
private func waitUntil(_ cond: () -> Bool) async {
    for _ in 0..<300 where !cond() { try? await Task.sleep(for: .milliseconds(10)) }
}

@Test @MainActor func callbookFillsOnlyEmptyFields() async throws {
    let (f, req) = await setup()
    await f.model.setQSOField("name", "JAN")
    await f.model.setQSOField("call", "ok1abc")
    await waitUntil { !f.model.qso.qth.isEmpty && !f.model.qso.locator.isEmpty }
    #expect(f.model.qso.name == "JAN")                // the filled-in field was kept
    #expect(f.model.qso.qth == "Praha")
    #expect(f.model.qso.locator == "JO70FB")
    #expect(req.lookups.count == 1)
    #expect(f.model.callbookStatus.contains("QRZ.com"))
    await f.model.stop()
}

@Test @MainActor func callbookOverwritesWhenNotFillEmptyOnly() async throws {
    let (f, _) = await setup(fillEmptyOnly: false)
    await f.model.setQSOField("name", "JAN")
    await f.model.setQSOField("call", "OK1ABC")
    await waitUntil { f.model.qso.qth == "Praha" }
    #expect(f.model.qso.name == "Tomas Kaplan")
    await f.model.stop()
}

@Test @MainActor func callbookLookupCancelledByQuickChange() async throws {
    let (f, req) = await setup(delay: .milliseconds(200))
    await f.model.setQSOField("call", "OK1AAA")
    try await Task.sleep(for: .milliseconds(50))
    await f.model.setQSOField("call", "OK1BBB")
    await waitUntil { !f.model.qso.qth.isEmpty }
    #expect(req.lookups.count == 1)
    #expect(req.lookups[0].contains("OK1BBB"))
    await f.model.stop()
}

@Test @MainActor func callbookOffOrManualDoesNotFetch() async throws {
    let (f, req) = await setup(kind: .none)
    await f.model.setQSOField("call", "OK1AAA")
    try await Task.sleep(for: .milliseconds(400))
    #expect(req.all.isEmpty && f.model.qso.qth.isEmpty)
    await f.model.stop()
    let (g, req2) = await setup(autoLookup: false)
    await g.model.setQSOField("call", "OK1AAA")
    try await Task.sleep(for: .milliseconds(400))
    #expect(req2.all.isEmpty)
    await g.model.stop()
}

@Test @MainActor func callbookShowsLoginError() async throws {
    let (f, _) = await setup(badLogin: true)
    await f.model.setQSOField("call", "OK1AAA")
    await waitUntil { f.model.callbookStatus.contains("incorrect") }
    #expect(f.model.callbookStatus.contains("incorrect"))
    #expect(f.model.qso.qth.isEmpty)
    await f.model.stop()
}

@Test @MainActor func callbookMissingPasswordIsReported() async throws {
    let (f, req) = await setup(password: "")
    await f.model.setQSOField("call", "OK1AAA")
    await waitUntil { !f.model.callbookStatus.isEmpty }
    #expect(!f.model.callbookStatus.isEmpty && req.all.isEmpty)
    await f.model.stop()
}

@Test @MainActor func callbookTestButtonLooksUpOwnCallWithDraftCredentials() async throws {
    let (f, req) = await setup(kind: .none)
    let text = await f.model.testCallbook(kind: .qrz, username: "u", password: "p", call: "OK1XOE")
    #expect(text.contains("Tomas Kaplan") && text.contains("Praha"))
    #expect(req.all.first?.contains("username=u;password=p") == true)
    let bad = await f.model.testCallbook(kind: .none, username: "u", password: "p", call: "OK1XOE")
    #expect(!bad.isEmpty)
    await f.model.stop()
}

@Test @MainActor func callbookPasswordGoesToSecretStore() async throws {
    let f = Fixture()
    f.model.saveCallbookPassword("tajne", kind: .hamqth, username: "x")
    #expect(f.secrets.password(service: "hamqth", account: "x") == "tajne")
    #expect(f.model.callbookPassword(kind: .hamqth, username: "x") == "tajne")
    let json = try String(contentsOf: f.dir.appendingPathComponent("settings.json"), encoding: .utf8)
    #expect(!json.contains("tajne"))
}
