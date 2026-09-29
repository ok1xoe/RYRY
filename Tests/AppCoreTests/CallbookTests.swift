import Foundation
import Testing
import Settings
@testable import AppCore

// Ukázkové odpovědi podle dokumentace formátů QRZ.com XML a HamQTH XML.
enum CallbookSamples {
    static let qrzLogin = """
    <?xml version="1.0" encoding="utf-8" ?>
    <QRZDatabase version="1.34" xmlns="http://xmldata.qrz.com">
      <Session><Key>KEY123</Key><Count>123</Count><SubExp>Wed Jan 1 12:34:03 2026</SubExp><GMTime>Sun Nov 16 04:13:46 2025</GMTime></Session>
    </QRZDatabase>
    """
    static let qrzBadPassword = """
    <?xml version="1.0" ?><QRZDatabase version="1.34" xmlns="http://xmldata.qrz.com">
      <Session><Error>Username/password incorrect </Error><GMTime>Sun Nov 16 04:13:46 2025</GMTime></Session></QRZDatabase>
    """
    static let qrzTimeout = """
    <?xml version="1.0" ?><QRZDatabase version="1.34" xmlns="http://xmldata.qrz.com">
      <Session><Error>Session Timeout</Error><GMTime>Sun Nov 16 04:13:46 2025</GMTime></Session></QRZDatabase>
    """
    static let qrzNotFound = """
    <?xml version="1.0" ?><QRZDatabase version="1.34" xmlns="http://xmldata.qrz.com">
      <Session><Error>Not found: OK9ZZZ</Error><Key>KEY123</Key><Count>124</Count></Session></QRZDatabase>
    """
    static func qrzCall(_ call: String = "OK1XOE") -> String { """
    <?xml version="1.0" ?><QRZDatabase version="1.34" xmlns="http://xmldata.qrz.com">
      <Callsign><call>\(call)</call><fname>Tomas</fname><name>Kaplan</name><addr1>Ulice 1</addr1><addr2>Praha</addr2>
        <country>Czech Republic</country><grid>JO70fb</grid><qslmgr>via bureau</qslmgr></Callsign>
      <Session><Key>KEY123</Key><Count>125</Count></Session></QRZDatabase>
    """ }
    static let hamLogin = """
    <?xml version="1.0"?><HamQTH version="2.8" xmlns="https://www.hamqth.com">
      <session><session_id>09b0ae90050be03c452ad235a1f2915ad684393c</session_id></session></HamQTH>
    """
    static let hamBadPassword = """
    <?xml version="1.0"?><HamQTH version="2.8" xmlns="https://www.hamqth.com"><session><error>Wrong user name or password</error></session></HamQTH>
    """
    static let hamExpired = """
    <?xml version="1.0"?><HamQTH version="2.8" xmlns="https://www.hamqth.com"><session><error>Session does not exist or expired</error></session></HamQTH>
    """
    static let hamNotFound = """
    <?xml version="1.0"?><HamQTH version="2.8" xmlns="https://www.hamqth.com"><session><error>Callsign not found</error></session></HamQTH>
    """
    static let hamCall = """
    <?xml version="1.0"?><HamQTH version="2.8" xmlns="https://www.hamqth.com">
      <search><callsign>ok1xoe</callsign><nick>Tomas</nick><qth>Praha</qth><country>Czech Republic</country>
        <adif>503</adif><itu>28</itu><cq>15</cq><grid>jo70fb</grid><adr_name>Tomas Kaplan</adr_name></search></HamQTH>
    """
}

final class MockFetcher: @unchecked Sendable {
    private let lock = NSLock()
    private var _urls: [URL] = []
    let handler: @Sendable (URL) async throws -> String
    init(_ r: @escaping @Sendable (URL) async throws -> String) { handler = r }
    var urls: [URL] { lock.withLock { _urls } }
    var fetcher: HTTPFetcher {
        { [self] url in
            lock.withLock { _urls.append(url) }
            return Data(try await handler(url).utf8)
        }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var v = 0
    func next() -> Int { lock.withLock { v += 1; return v } }
}

@Test func qrzParsesEntry() async throws {
    let m = MockFetcher { url in url.absoluteString.contains("username=") ? CallbookSamples.qrzLogin : CallbookSamples.qrzCall() }
    let qrz = QRZCallbook(username: "ok1xoe", password: "p w&d", fetcher: m.fetcher)
    let e = try await qrz.lookup("ok1xoe")
    #expect(e == CallbookEntry(call: "OK1XOE", name: "Tomas Kaplan", qth: "Praha", grid: "JO70FB", country: "Czech Republic"))
    #expect(m.urls.count == 2)
    #expect(m.urls[0].absoluteString.hasPrefix("https://xmldata.qrz.com/xml/current/?username=ok1xoe;password=p%20w%26d"))
    #expect(m.urls[1].absoluteString.contains("s=KEY123;callsign=OK1XOE"))
}

@Test func qrzLoginErrorIsReported() async {
    let m = MockFetcher { _ in CallbookSamples.qrzBadPassword }
    let qrz = QRZCallbook(username: "a", password: "b", fetcher: m.fetcher)
    await #expect(throws: CallbookError.login("Username/password incorrect")) { _ = try await qrz.lookup("OK1XOE") }
}

@Test func qrzNotFoundIsNil() async throws {
    let m = MockFetcher { url in url.absoluteString.contains("username=") ? CallbookSamples.qrzLogin : CallbookSamples.qrzNotFound }
    let qrz = QRZCallbook(username: "a", password: "b", fetcher: m.fetcher)
    #expect(try await qrz.lookup("OK9ZZZ") == nil)
}

@Test func qrzRelogsInAfterSessionTimeout() async throws {
    let cnt = Counter()
    let m = MockFetcher { url in
        if url.absoluteString.contains("username=") { return CallbookSamples.qrzLogin }
        return cnt.next() == 1 ? CallbookSamples.qrzTimeout : CallbookSamples.qrzCall()
    }
    let qrz = QRZCallbook(username: "a", password: "b", fetcher: m.fetcher)
    let e = try await qrz.lookup("OK1XOE")
    #expect(e?.name == "Tomas Kaplan")
    #expect(m.urls.filter { $0.absoluteString.contains("username=") }.count == 2)   // přihlášení, znovu přihlášení
    #expect(m.urls.count == 4)
}

@Test func qrzReusesSession() async throws {
    let m = MockFetcher { url in url.absoluteString.contains("username=") ? CallbookSamples.qrzLogin : CallbookSamples.qrzCall() }
    let qrz = QRZCallbook(username: "a", password: "b", fetcher: m.fetcher)
    _ = try await qrz.lookup("OK1XOE"); _ = try await qrz.lookup("OK1ABC")
    #expect(m.urls.filter { $0.absoluteString.contains("username=") }.count == 1)
}

@Test func hamqthParsesEntry() async throws {
    let m = MockFetcher { url in url.absoluteString.contains("u=") ? CallbookSamples.hamLogin : CallbookSamples.hamCall }
    let h = HamQTHCallbook(username: "ok1xoe", password: "pw", fetcher: m.fetcher)
    let e = try await h.lookup("OK1XOE")
    #expect(e == CallbookEntry(call: "OK1XOE", name: "Tomas", qth: "Praha", grid: "JO70FB", country: "Czech Republic"))
    #expect(m.urls[0].absoluteString == "https://www.hamqth.com/xml.php?u=ok1xoe&p=pw")
    #expect(m.urls[1].absoluteString == "https://www.hamqth.com/xml.php?id=09b0ae90050be03c452ad235a1f2915ad684393c&callsign=OK1XOE&prg=mmtty4mac")
}

@Test func hamqthLoginErrorNotFoundAndExpiry() async throws {
    let bad = HamQTHCallbook(username: "a", password: "b", fetcher: MockFetcher { _ in CallbookSamples.hamBadPassword }.fetcher)
    await #expect(throws: CallbookError.login("Wrong user name or password")) { _ = try await bad.lookup("OK1XOE") }

    let nf = MockFetcher { url in url.absoluteString.contains("u=") ? CallbookSamples.hamLogin : CallbookSamples.hamNotFound }
    #expect(try await HamQTHCallbook(username: "a", password: "b", fetcher: nf.fetcher).lookup("OK9ZZZ") == nil)

    let cnt = Counter()
    let ex = MockFetcher { url in
        if url.absoluteString.contains("u=") { return CallbookSamples.hamLogin }
        return cnt.next() == 1 ? CallbookSamples.hamExpired : CallbookSamples.hamCall
    }
    let e = try await HamQTHCallbook(username: "a", password: "b", fetcher: ex.fetcher).lookup("OK1XOE")
    #expect(e?.qth == "Praha")
    #expect(ex.urls.filter { $0.absoluteString.contains("u=") }.count == 2)
}

private actor CountingService: CallbookService {
    nonisolated let name = "T"
    var calls: [String] = []
    var failedOnce = false
    func lookup(_ call: String) async throws -> CallbookEntry? {
        calls.append(call)
        if call == "ERR", !failedOnce { failedOnce = true; throw CallbookError.network("x") }
        return call == "NONE" ? nil : CallbookEntry(call: call, name: "N", qth: "", grid: "", country: "")
    }
}

@Test func cacheRemembersPositiveAndNegativeButNotErrors() async throws {
    let svc = CountingService()
    let c = CachingCallbook(svc)
    _ = try await c.lookup("aa1a"); _ = try await c.lookup("AA1A")
    #expect(try await c.lookup("NONE") == nil); #expect(try await c.lookup("none") == nil)
    #expect(await svc.calls == ["AA1A", "NONE"])
    await #expect(throws: CallbookError.network("x")) { _ = try await c.lookup("ERR") }
    _ = try await c.lookup("ERR")                        // chyba se neukládá
    #expect(await svc.calls.count == 4)
}

private actor SlowService: CallbookService {
    nonisolated let name = "T"
    var running = 0, peak = 0
    func lookup(_ call: String) async throws -> CallbookEntry? {
        running += 1; peak = max(peak, running)
        try await Task.sleep(for: .milliseconds(30))
        running -= 1
        return nil
    }
}

@Test func concurrencyIsLimited() async throws {
    let svc = SlowService()
    let c = CachingCallbook(svc, maxConcurrent: 2)
    await withTaskGroup(of: Void.self) { g in
        for i in 0..<8 { g.addTask { _ = try? await c.lookup("AA\(i)A") } }
    }
    #expect(await svc.peak == 2)
}

@Test func callbookSettingsDefaultsAndTolerance() throws {
    let s = AppSettings()
    #expect(s.callbook.service == .none && s.callbook.autoLookup && s.callbook.fillEmptyOnly && s.callbook.username == "")
    let d = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"callbook":{"service":"hamqth","username":"x","autoLookup":"bad"}}"#.utf8))
    #expect(d.callbook.service == .hamqth && d.callbook.username == "x" && d.callbook.autoLookup)
    let bad = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"callbook":{"service":"nic"}}"#.utf8))
    #expect(bad.callbook.service == .none)
}

@Test func memorySecretStoreRoundTrip() throws {
    let s = MemorySecretStore()
    #expect(s.password(service: "qrz", account: "a") == nil)
    try s.setPassword("x", service: "qrz", account: "a")
    #expect(s.password(service: "qrz", account: "a") == "x")
    try s.setPassword("", service: "qrz", account: "a")
    #expect(s.password(service: "qrz", account: "a") == nil)
}
