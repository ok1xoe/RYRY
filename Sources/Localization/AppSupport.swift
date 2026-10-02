// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation

/// The app's data folder (Application Support/RYRY: settings, languages, cty.dat, MASTER.SCP) and the move from the
/// former name mmtty4mac (folder `mmtty4mac`, preferences domain `cz.ok1xoe.mmtty4mac`).
public enum AppSupport {
    public static let folderName = "RYRY"
    public static let legacyFolderName = "mmtty4mac"
    public static let legacyDefaultsDomain = "cz.ok1xoe.mmtty4mac"

    static var base: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// Application Support/RYRY; until the move, the legacy folder when only that one exists.
    public static var directory: URL { directory(in: base) }

    static func directory(in base: URL) -> URL {
        let fm = FileManager.default
        let new = base.appendingPathComponent(folderName), old = base.appendingPathComponent(legacyFolderName)
        if !fm.fileExists(atPath: new.path), fm.fileExists(atPath: old.path) { return old }
        return new
    }

    /// At launch: renames the legacy folder (also the one moved into the sandbox container by container-migration.plist)
    /// and takes over the legacy preferences (language, windows) that are not set yet. Repeating it does nothing.
    public static func migrateLegacy(defaults: UserDefaults = .standard) {
        migrateFolder(in: base)
        migrateDefaults(from: UserDefaults(suiteName: legacyDefaultsDomain)?.persistentDomain(forName: legacyDefaultsDomain) ?? [:],
                        to: defaults)
    }

    static func migrateFolder(in base: URL) {
        let fm = FileManager.default
        let new = base.appendingPathComponent(folderName), old = base.appendingPathComponent(legacyFolderName)
        guard !fm.fileExists(atPath: new.path), fm.fileExists(atPath: old.path) else { return }
        try? fm.moveItem(at: old, to: new)
    }

    static func migrateDefaults(from old: [String: Any], to defaults: UserDefaults) {
        for (k, v) in old where defaults.object(forKey: k) == nil { defaults.set(v, forKey: k) }
    }
}
