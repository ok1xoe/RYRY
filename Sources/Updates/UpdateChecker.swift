// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import CryptoKit
import Foundation
import Localization

/// The network used for update checks (replaced by a stub in tests).
public protocol UpdateNetwork: Sendable {
    /// Downloads a small document (appcast, GitHub API).
    func fetch(_ url: URL) async throws -> Data
    /// Downloads a file to a temporary location; the caller moves it.
    func download(_ url: URL) async throws -> URL
}

public struct URLSessionUpdateNetwork: UpdateNetwork {
    private let session: URLSession
    public init(timeout: TimeInterval = 15) {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = 3600
        session = URLSession(configuration: c)
    }
    public func fetch(_ url: URL) async throws -> Data {
        var r = URLRequest(url: url)
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("mmtty4mac", forHTTPHeaderField: "User-Agent")   // the GitHub API requires a User-Agent
        let (d, resp) = try await session.data(for: r)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw UpdateError.http(h.statusCode) }
        return d
    }
    public func download(_ url: URL) async throws -> URL {
        let (tmp, resp) = try await session.download(from: url)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            try? FileManager.default.removeItem(at: tmp)
            throw UpdateError.http(h.statusCode)
        }
        return tmp
    }
}

public enum UpdateOutcome: Sendable, Equatable {
    case notConfigured               // MMUpdateFeedURL is empty
    case skippedByLimit              // automatic check, already done today
    case upToDate
    case available(UpdateInfo)
    case skippedVersion(UpdateInfo)  // a newer version that the user skipped (automatic check only)
    case systemTooOld(UpdateInfo)    // the newer version requires a newer macOS
    case failed(String)
}

/// Update checking. The state (last check, skipped version) lives in UserDefaults.
public final class UpdateChecker: @unchecked Sendable {
    public static let lastCheckKey = "updates.lastCheck"
    public static let skippedKey = "updates.skippedVersion"
    public static let minInterval: TimeInterval = 24 * 3600

    private let configured: Bool
    private let feedURL: URL?
    private let network: UpdateNetwork
    private let defaults: UserDefaults
    private let current: AppVersion
    private let systemVersion: OperatingSystemVersion
    private let now: @Sendable () -> Date

    public init(feedURL: String?, network: UpdateNetwork = URLSessionUpdateNetwork(),
                defaults: UserDefaults = .standard, current: AppVersion,
                systemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
                now: @escaping @Sendable () -> Date = { Date() }) {
        let t = feedURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.configured = !t.isEmpty
        self.feedURL = t.isEmpty ? nil : URL(string: t).flatMap { UpdateFeed.downloadURL($0.absoluteString) }
        self.network = network; self.defaults = defaults; self.current = current
        self.systemVersion = systemVersion; self.now = now
    }

    /// The current version from the main bundle's Info.plist (0.0.0 when missing).
    public static func currentVersion(bundle: Bundle = .main) -> AppVersion {
        let v = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let b = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap { Int($0) }
        return AppVersion(v, build: b) ?? AppVersion("0.0.0")!
    }

    public var isConfigured: Bool { configured }
    public var lastCheck: Date? { defaults.object(forKey: Self.lastCheckKey) as? Date }
    public var skippedVersion: String? { defaults.string(forKey: Self.skippedKey) }

    /// Whether an automatic check may run (at most once per 24 h; the clock went back = it may).
    public func dueForAutomaticCheck() -> Bool {
        guard let last = lastCheck else { return true }
        let d = now().timeIntervalSince(last)
        return d < 0 || d >= Self.minInterval
    }

    public func skip(_ info: UpdateInfo) { defaults.set(info.version.description, forKey: Self.skippedKey) }

    /// `manual` = a manual command from the menu: ignores both the daily limit and the skipped version.
    public func check(manual: Bool) async -> UpdateOutcome {
        guard configured else { return .notConfigured }
        guard let feedURL else { return .failed(L("neplatná adresa aktualizací")) }
        if !manual && !dueForAutomaticCheck() { return .skippedByLimit }
        let info: UpdateInfo
        do {
            let data = try await network.fetch(feedURL)
            info = try UpdateFeed.parse(data, feedURL: feedURL)
        } catch let e as UpdateError {
            return .failed(Self.describe(e))
        } catch {
            return .failed(error.localizedDescription)
        }
        defaults.set(now(), forKey: Self.lastCheckKey)
        guard info.version.isNewer(than: current) else { return .upToDate }
        if let min = info.minimumSystemVersion, !systemSatisfies(min) { return .systemTooOld(info) }
        if !manual, skippedVersion == info.version.description { return .skippedVersion(info) }
        return .available(info)
    }

    func systemSatisfies(_ min: String) -> Bool {
        guard let m = AppVersion(min) else { return true }
        let s = AppVersion("\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)")!
        return !m.isNewer(than: s)
    }

    static func describe(_ e: UpdateError) -> String {
        switch e {
        case .invalidFeed(let s): return L("neplatná data aktualizací (%@)", s)
        case .http(let c): return L("server odpověděl kódem %ld", c)
        case .checksumMismatch: return L("kontrolní součet nesouhlasí")
        }
    }

    // MARK: download

    /// Downloads the DMG into `directory`, verifies the sha256 (when known) and returns the destination file.
    /// A file with the same name is not overwritten (a number is appended).
    public static func download(_ info: UpdateInfo, to directory: URL, network: UpdateNetwork) async throws -> URL {
        let tmp = try await network.download(info.url)
        let fm = FileManager.default
        do {
            if let want = info.sha256, try sha256(of: tmp) != want { throw UpdateError.checksumMismatch }
            var name = info.url.lastPathComponent
            if name.isEmpty || !name.lowercased().hasSuffix(".dmg") { name = "mmtty4mac-\(info.version).dmg" }
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            var dest = directory.appendingPathComponent(name)
            let base = dest.deletingPathExtension().lastPathComponent
            var n = 1
            while fm.fileExists(atPath: dest.path) {
                dest = directory.appendingPathComponent("\(base) (\(n)).dmg"); n += 1
            }
            try fm.moveItem(at: tmp, to: dest)
            return dest
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    public static func sha256(of file: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: file)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
