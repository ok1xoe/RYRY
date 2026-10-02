// Copyright 2026 OK1XOE (RYRY), LGPL v3
import CryptoKit
import Foundation

/// Available languages: bundled with the app and added by the user (Application Support/RYRY/Languages).
/// A user file with the same code takes precedence over the bundled one.
public struct LanguageLibrary: Sendable {
    public let bundled: [URL]
    public let userDirectory: URL

    public init(bundled: [URL], userDirectory: URL) {
        self.bundled = bundled; self.userDirectory = userDirectory
    }

    /// Default locations: Languages inside the app bundle, during development Resources/Languages in the repository.
    public static func standard() -> LanguageLibrary {
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r.appendingPathComponent("Languages")) }
        dirs.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Languages"))
        return LanguageLibrary(bundled: dirs, userDirectory: AppSupport.directory.appendingPathComponent("Languages"))
    }

    private func packs(in dir: URL) -> [LanguagePack] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? LanguagePack.decode(Data(contentsOf: $0)) }
    }

    /// Bundled languages by code (an earlier folder in `bundled` wins).
    func bundledPacks() -> [String: (pack: LanguagePack, file: URL)] {
        var byCode: [String: (LanguagePack, URL)] = [:]
        for d in bundled.reversed() {
            let files = (try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []
            for f in files where f.pathExtension.lowercased() == "json" {
                if let p = try? LanguagePack.decode(Data(contentsOf: f)) { byCode[p.code] = (p, f) }
            }
        }
        return byCode
    }

    /// All languages sorted by code. A file in the user folder takes precedence; texts that are missing there
    /// (or empty) are filled in from the bundled version – so new texts from later app versions are not missing.
    public func available() -> [LanguagePack] {
        var byCode = bundledPacks().mapValues(\.pack)
        for u in packs(in: userDirectory) {
            if var b = byCode[u.code] {
                for (k, v) in u.strings where !v.isEmpty { b.strings[k] = v }
                b.name = u.name; b.version = u.version
                byCode[u.code] = b
            } else {
                byCode[u.code] = u
            }
        }
        return byCode.values.sorted { $0.code < $1.code }
    }

    /// Copies the bundled languages into the user folder (where they can be edited). A copy the user has not edited
    /// is refreshed on a new app version; an edited one is not overwritten (recognized by the digest in `.<file>.seeded`).
    public func seedUserDirectory() {
        let fm = FileManager.default
        try? fm.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        for (code, b) in bundledPacks() {
            guard let src = try? Data(contentsOf: b.file) else { continue }
            let dst = userDirectory.appendingPathComponent("\(code).json")
            let mark = userDirectory.appendingPathComponent(".\(code).json.seeded")
            if let cur = try? Data(contentsOf: dst) {
                guard cur != src, let seeded = try? String(contentsOf: mark, encoding: .utf8),
                      seeded == Self.digest(cur) else { continue }      // an edited (or foreign) copy – leave it
            }
            do {
                try src.write(to: dst, options: .atomic)
                try Self.digest(src).write(to: mark, atomically: true, encoding: .utf8)
            } catch { continue }
        }
    }

    static func digest(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    public func pack(code: String) -> LanguagePack? { available().first { $0.code == code } }

    /// Validates the file and copies it into the languages folder as `<code>.json`.
    @discardableResult
    public func importPack(from url: URL) throws -> LanguagePack {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw LanguagePack.PackError.unreadable(L("Soubor nelze přečíst: %@", error.localizedDescription))
        }
        let p = try LanguagePack.decode(data)
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        try data.write(to: userDirectory.appendingPathComponent("\(p.code).json"), options: .atomic)
        return p
    }

    /// The reference language for the template (English, otherwise the first available one).
    public func reference() -> LanguagePack? { pack(code: "en") ?? available().first }

    /// The chosen language is remembered in UserDefaults (a UI choice, effective at once – no waiting for "Apply").
    public static let defaultsKey = "language"

    /// Switches the language (nil/"cs" = Czech) and remembers the choice.
    public func select(_ code: String?, localizer: Localizer = .shared, defaults: UserDefaults = .standard) {
        let p = code.flatMap { pack(code: $0) }                     // Czech without a file = the built-in one
        localizer.use(p)
        defaults.set(p?.code ?? Localizer.baseCode, forKey: Self.defaultsKey)
    }

    /// The language used when no choice is stored (first launch).
    public static let defaultCode = "en"

    /// Restores the language from the previous launch; English when nothing was chosen, a missing file → Czech.
    public func restore(localizer: Localizer = .shared, defaults: UserDefaults = .standard) {
        let c = defaults.string(forKey: Self.defaultsKey) ?? Self.defaultCode
        localizer.use(pack(code: c))
    }
}
