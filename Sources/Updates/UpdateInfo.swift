// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Informace o vydání z appcastu nebo GitHub Releases.
public struct UpdateInfo: Sendable, Equatable {
    public var version: AppVersion
    public var url: URL
    public var notes: [String: String]
    public var minimumSystemVersion: String?
    public var sha256: String?

    public init(version: AppVersion, url: URL, notes: [String: String] = [:],
                minimumSystemVersion: String? = nil, sha256: String? = nil) {
        self.version = version; self.url = url; self.notes = notes
        self.minimumSystemVersion = minimumSystemVersion; self.sha256 = sha256
    }

    /// Poznámky ve zvoleném jazyce, jinak anglicky, jinak jakékoli (GitHub: jediný text pod klíčem „“).
    public func notes(for code: String) -> String {
        notes[code] ?? notes["en"] ?? notes[""] ?? notes.sorted { $0.key < $1.key }.first?.value ?? ""
    }
}

public enum UpdateError: Error, Equatable, Sendable {
    case invalidFeed(String)
    case http(Int)
    case checksumMismatch
}

/// Rozbor zdroje verzí. Tvar URL rozhoduje: `api.github.com/repos/…/releases/latest` = GitHub, jinak appcast.
public enum UpdateFeed {
    public static func isGitHub(_ url: URL) -> Bool {
        url.host?.lowercased() == "api.github.com" && url.path.contains("/releases")
    }

    public static func parse(_ data: Data, feedURL: URL) throws -> UpdateInfo {
        isGitHub(feedURL) ? try parseGitHub(data) : try parseAppcast(data)
    }

    // MARK: appcast

    private struct Appcast: Decodable {
        struct Latest: Decodable {
            var version: String
            var build: Int?
            var url: String
            var notes: [String: String]?
            var minimumSystemVersion: String?
            var sha256: String?
        }
        var latest: Latest
    }

    static func parseAppcast(_ data: Data) throws -> UpdateInfo {
        let l: Appcast.Latest
        do { l = try JSONDecoder().decode(Appcast.self, from: data).latest }
        catch { throw UpdateError.invalidFeed("appcast") }
        guard let v = AppVersion(l.version, build: l.build) else { throw UpdateError.invalidFeed("verze „\(l.version)“") }
        guard let url = downloadURL(l.url) else { throw UpdateError.invalidFeed("adresa souboru") }
        return UpdateInfo(version: v, url: url, notes: l.notes ?? [:],
                          minimumSystemVersion: l.minimumSystemVersion.flatMap { $0.isEmpty ? nil : $0 },
                          sha256: normalizedSHA(l.sha256))
    }

    // MARK: GitHub

    private struct Release: Decodable {
        struct Asset: Decodable { var name: String; var browser_download_url: String; var digest: String? }
        var tag_name: String
        var body: String?
        var assets: [Asset]?
    }

    static func parseGitHub(_ data: Data) throws -> UpdateInfo {
        let r: Release
        do { r = try JSONDecoder().decode(Release.self, from: data) }
        catch { throw UpdateError.invalidFeed("GitHub") }
        guard let v = AppVersion(r.tag_name) else { throw UpdateError.invalidFeed("tag „\(r.tag_name)“") }
        guard let a = r.assets?.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
              let url = downloadURL(a.browser_download_url) else { throw UpdateError.invalidFeed("vydání neobsahuje DMG") }
        var sha: String?
        if let d = a.digest, d.lowercased().hasPrefix("sha256:") { sha = normalizedSHA(String(d.dropFirst(7))) }
        let body = (r.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdateInfo(version: v, url: url, notes: body.isEmpty ? [:] : ["": body], sha256: sha)
    }

    /// Jen https (a http pro lokální ladění na localhost).
    static func downloadURL(_ s: String) -> URL? {
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), let host = u.host else { return nil }
        if scheme == "https" { return u }
        if scheme == "http", ["localhost", "127.0.0.1"].contains(host) { return u }
        return nil
    }

    static func normalizedSHA(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces).lowercased(), s.count == 64,
              s.allSatisfy({ $0.isHexDigit }) else { return nil }
        return s
    }
}
