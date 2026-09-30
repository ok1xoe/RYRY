// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import CryptoKit
import Foundation
import Testing
@testable import Updates

// MARK: helpers

final class MockNetwork: UpdateNetwork, @unchecked Sendable {
    private let lock = NSLock()
    private var _fetches = 0
    var body: Data
    var fetchError: Error?
    var fileContent = Data("dmg-obsah".utf8)
    init(_ json: String = "") { body = Data(json.utf8) }
    var fetches: Int { lock.withLock { _fetches } }
    func fetch(_ url: URL) async throws -> Data {
        lock.withLock { _fetches += 1 }
        if let e = fetchError { throw e }
        return body
    }
    func download(_ url: URL) async throws -> URL {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileContent.write(to: f)
        return f
    }
}

func freshDefaults() -> UserDefaults {
    let name = "updates-test-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

let appcast = """
{"latest":{"version":"0.13.0","build":150,"url":"https://example.com/mmtty4mac-0.13.0.dmg",
 "notes":{"cs":"Nové věci","en":"New things"},"minimumSystemVersion":"14.0",
 "sha256":"\(String(repeating: "ab", count: 32))"}}
"""
let feed = "https://example.com/appcast.json"
let os14 = OperatingSystemVersion(majorVersion: 14, minorVersion: 5, patchVersion: 0)
func v(_ s: String, _ b: Int? = nil) -> AppVersion { AppVersion(s, build: b)! }

func checker(_ net: MockNetwork, url: String? = feed, current: AppVersion = v("0.12.0", 100),
             defaults: UserDefaults = freshDefaults(), os: OperatingSystemVersion = os14,
             now: @escaping @Sendable () -> Date = { Date() }) -> UpdateChecker {
    UpdateChecker(feedURL: url, network: net, defaults: defaults, current: current, systemVersion: os, now: now)
}

// MARK: versions

@Test func versionParsing() {
    #expect(AppVersion("v0.13.0")?.description == "0.13.0")
    #expect(AppVersion("1.2")?.numbers == [1, 2, 0])
    #expect(AppVersion("1.2.3-beta.1+abc")?.description == "1.2.3-beta.1")
    #expect(AppVersion("") == nil)
    #expect(AppVersion("1.x.0") == nil)
    #expect(AppVersion("1.2.3.4") == nil)
    #expect(AppVersion("1.0.0-") == nil)
}

@Test func versionComparison() {
    #expect(v("0.13.0").isNewer(than: v("0.12.9")))
    #expect(v("0.10.0").isNewer(than: v("0.9.0")))            // numerically, not as text
    #expect(v("1.0.0").isNewer(than: v("0.99.99")))
    #expect(!v("0.12.0").isNewer(than: v("0.12.0")))
    #expect(!v("0.11.0").isNewer(than: v("0.12.0")))
    #expect(v("1.0.0").isNewer(than: v("1.0.0-rc.1")))         // a release > a pre-release
    #expect(v("1.0.0-rc.2").isNewer(than: v("1.0.0-rc.1")))
    #expect(v("1.0.0-rc.10").isNewer(than: v("1.0.0-rc.9")))
    #expect(v("0.12.0", 101).isNewer(than: v("0.12.0", 100)))  // the same version, a higher build
    #expect(!v("0.12.0", 100).isNewer(than: v("0.12.0", 100)))
    #expect(!v("0.12.0", 99).isNewer(than: v("0.12.0", 100)))
    #expect(!v("0.12.0").isNewer(than: v("0.12.0", 100)))       // an unknown build = no change
    #expect(v("0.13.0", 1).isNewer(than: v("0.12.0", 500)))     // semver takes precedence over the build
}

// MARK: formats

@Test func appcastParsing() throws {
    let i = try UpdateFeed.parse(Data(appcast.utf8), feedURL: URL(string: feed)!)
    #expect(i.version == v("0.13.0", 150))
    #expect(i.url.absoluteString == "https://example.com/mmtty4mac-0.13.0.dmg")
    #expect(i.minimumSystemVersion == "14.0")
    #expect(i.sha256 == String(repeating: "ab", count: 32))
    #expect(i.notes(for: "cs") == "Nové věci")
    #expect(i.notes(for: "en") == "New things")
    #expect(i.notes(for: "de") == "New things")   // another language → English
}

@Test func githubParsing() throws {
    let json = """
    {"tag_name":"v0.13.0","body":"Poznámky vydání","draft":false,"assets":[
      {"name":"source.zip","browser_download_url":"https://github.com/o/r/releases/download/v0.13.0/source.zip"},
      {"name":"mmtty4mac-0.13.0.dmg","browser_download_url":"https://github.com/o/r/releases/download/v0.13.0/mmtty4mac-0.13.0.dmg",
       "digest":"sha256:\(String(repeating: "0f", count: 32))"}]}
    """
    let u = URL(string: "https://api.github.com/repos/o/r/releases/latest")!
    #expect(UpdateFeed.isGitHub(u) && !UpdateFeed.isGitHub(URL(string: feed)!))
    let i = try UpdateFeed.parse(Data(json.utf8), feedURL: u)
    #expect(i.version == v("0.13.0"))
    #expect(i.url.lastPathComponent == "mmtty4mac-0.13.0.dmg")
    #expect(i.sha256 == String(repeating: "0f", count: 32))
    #expect(i.notes(for: "cs") == "Poznámky vydání")
}

@Test func githubWithoutDMGIsInvalid() {
    let json = #"{"tag_name":"v0.13.0","assets":[{"name":"a.zip","browser_download_url":"https://x.org/a.zip"}]}"#
    #expect(throws: UpdateError.self) {
        try UpdateFeed.parse(Data(json.utf8), feedURL: URL(string: "https://api.github.com/repos/o/r/releases/latest")!)
    }
}

@Test func insecureDownloadURLRejected() {
    let json = #"{"latest":{"version":"1.0.0","url":"http://example.com/a.dmg"}}"#
    #expect(throws: UpdateError.self) { try UpdateFeed.parse(Data(json.utf8), feedURL: URL(string: feed)!) }
}

// MARK: checking

@Test func emptyFeedURLDisablesAndDoesNoNetwork() async {
    let n = MockNetwork(appcast)
    #expect(await checker(n, url: "").check(manual: true) == .notConfigured)
    #expect(await checker(n, url: nil).check(manual: false) == .notConfigured)
    #expect(n.fetches == 0)
}

@Test func newerVersionIsAvailable() async {
    let n = MockNetwork(appcast)
    guard case .available(let i) = await checker(n).check(manual: true) else { Issue.record("čekáno available"); return }
    #expect(i.version.description == "0.13.0")
}

@Test func olderAndSameVersionAreUpToDate() async {
    let n = MockNetwork(appcast)
    #expect(await checker(n, current: v("0.13.0", 150)).check(manual: true) == .upToDate)   // the same
    #expect(await checker(n, current: v("0.14.0", 1)).check(manual: true) == .upToDate)     // newer than the feed
    guard case .available = await checker(n, current: v("0.13.0", 149)).check(manual: true) else {
        Issue.record("nižší build má být novinka"); return
    }
}

@Test func brokenJSONFails() async {
    for body in ["", "not json", "{}", #"{"latest":{"version":"abc","url":"https://e.com/a.dmg"}}"#] {
        let n = MockNetwork(body)
        guard case .failed = await checker(n).check(manual: true) else { Issue.record("čekáno failed: \(body)"); continue }
    }
}

@Test func networkErrorFailsAndDoesNotConsumeDailyLimit() async {
    let n = MockNetwork(appcast); n.fetchError = URLError(.notConnectedToInternet)
    let d = freshDefaults(); let c = checker(n, defaults: d)
    guard case .failed = await c.check(manual: false) else { Issue.record("čekáno failed"); return }
    #expect(c.lastCheck == nil)
    n.fetchError = nil
    guard case .available = await c.check(manual: false) else { Issue.record("čekáno available"); return }
}

@Test func dailyLimitForAutomaticCheck() async {
    let n = MockNetwork(appcast)
    let clock = Box(Date(timeIntervalSince1970: 1_800_000_000))
    let c = checker(n, now: { clock.value })
    guard case .available = await c.check(manual: false) else { Issue.record("první kontrola"); return }
    #expect(n.fetches == 1)
    clock.value += 3600
    #expect(await c.check(manual: false) == .skippedByLimit)
    #expect(n.fetches == 1)
    guard case .available = await c.check(manual: true) else { Issue.record("ruční ignoruje limit"); return }
    #expect(n.fetches == 2)
    clock.value += 25 * 3600
    guard case .available = await c.check(manual: false) else { Issue.record("po 24 h znovu"); return }
    #expect(n.fetches == 3)
}

final class Box: @unchecked Sendable {
    private let l = NSLock(); private var _v: Date
    init(_ v: Date) { _v = v }
    var value: Date { get { l.withLock { _v } } set { l.withLock { _v = newValue } } }
}

@Test func skippedVersionSilentInAutoButShownManually() async {
    let n = MockNetwork(appcast)
    let d = freshDefaults()
    let c = checker(n, defaults: d)
    guard case .available(let i) = await c.check(manual: true) else { Issue.record("available"); return }
    c.skip(i)
    let c2 = checker(n, defaults: d)   // a new instance, the same UserDefaults
    #expect(await c2.check(manual: true) != .skippedByLimit)
    d.removeObject(forKey: UpdateChecker.lastCheckKey)
    guard case .skippedVersion = await c2.check(manual: false) else { Issue.record("auto má přeskočit"); return }
    guard case .available = await c2.check(manual: true) else { Issue.record("ruční ukáže i přeskočenou"); return }
    // for an even newer version the skip does not apply
    n.body = Data(appcast.replacingOccurrences(of: "0.13.0", with: "0.14.0").utf8)
    d.removeObject(forKey: UpdateChecker.lastCheckKey)
    guard case .available = await c2.check(manual: false) else { Issue.record("novější než přeskočená"); return }
}

@Test func minimumSystemVersionIsRespected() async {
    let n = MockNetwork(appcast.replacingOccurrences(of: "\"14.0\"", with: "\"15.0\""))
    guard case .systemTooOld = await checker(n).check(manual: true) else { Issue.record("čekáno systemTooOld"); return }
    #expect(await checker(n, os: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)).check(manual: true) != .upToDate)
}

// MARK: download

private func tmpDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("upd-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

@Test func downloadVerifiesChecksumAndMoves() async throws {
    let n = MockNetwork()
    let sha = SHA256.hash(data: n.fileContent).map { String(format: "%02x", $0) }.joined()
    let dir = tmpDir(); defer { try? FileManager.default.removeItem(at: dir) }
    var info = UpdateInfo(version: v("0.13.0"), url: URL(string: "https://example.com/mmtty4mac-0.13.0.dmg")!, sha256: sha)
    let f = try await UpdateChecker.download(info, to: dir, network: n)
    #expect(f.lastPathComponent == "mmtty4mac-0.13.0.dmg")
    #expect(try Data(contentsOf: f) == n.fileContent)
    let f2 = try await UpdateChecker.download(info, to: dir, network: n)      // does not overwrite
    #expect(f2.lastPathComponent == "mmtty4mac-0.13.0 (1).dmg")
    info.sha256 = String(repeating: "00", count: 32)
    await #expect(throws: UpdateError.checksumMismatch) { try await UpdateChecker.download(info, to: dir, network: n) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 2)   // a bad file is not kept
    info.sha256 = nil
    _ = try await UpdateChecker.download(info, to: dir, network: n)                      // without a sha256 nothing is verified
}
