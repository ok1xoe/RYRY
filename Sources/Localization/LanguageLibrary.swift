// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import CryptoKit
import Foundation

/// Dostupné jazyky: přibalené v aplikaci a nahrané uživatelem (Application Support/mmtty4mac/Languages).
/// Nahraný soubor se stejným kódem má přednost před přibaleným.
public struct LanguageLibrary: Sendable {
    public let bundled: [URL]
    public let userDirectory: URL

    public init(bundled: [URL], userDirectory: URL) {
        self.bundled = bundled; self.userDirectory = userDirectory
    }

    /// Výchozí umístění: Languages v balíčku aplikace, při vývoji Resources/Languages v repozitáři.
    public static func standard() -> LanguageLibrary {
        var dirs: [URL] = []
        if let r = Bundle.main.resourceURL { dirs.append(r.appendingPathComponent("Languages")) }
        dirs.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/Languages"))
        let sup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return LanguageLibrary(bundled: dirs, userDirectory: sup.appendingPathComponent("mmtty4mac/Languages"))
    }

    private func packs(in dir: URL) -> [LanguagePack] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? LanguagePack.decode(Data(contentsOf: $0)) }
    }

    /// Přibalené jazyky podle kódu (dřívější složka v `bundled` má přednost).
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

    /// Všechny jazyky seřazené podle kódu. Soubor ve složce uživatele má přednost; texty, které v něm chybějí
    /// (nebo jsou prázdné), doplní přibalená verze – nové texty z dalších verzí aplikace tak nechybí.
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

    /// Zkopíruje přibalené jazyky do složky uživatele (kde je lze upravit). Kopie, kterou uživatel neupravil,
    /// se při nové verzi aplikace obnoví; upravenou nepřepíše (pozná se podle otisku v `.<soubor>.seeded`).
    public func seedUserDirectory() {
        let fm = FileManager.default
        try? fm.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        for (code, b) in bundledPacks() {
            guard let src = try? Data(contentsOf: b.file) else { continue }
            let dst = userDirectory.appendingPathComponent("\(code).json")
            let mark = userDirectory.appendingPathComponent(".\(code).json.seeded")
            if let cur = try? Data(contentsOf: dst) {
                guard cur != src, let seeded = try? String(contentsOf: mark, encoding: .utf8),
                      seeded == Self.digest(cur) else { continue }      // upravená (nebo cizí) kopie – nechat
            }
            do {
                try src.write(to: dst, options: .atomic)
                try Self.digest(src).write(to: mark, atomically: true, encoding: .utf8)
            } catch { continue }
        }
    }

    static func digest(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    public func pack(code: String) -> LanguagePack? { available().first { $0.code == code } }

    /// Ověří soubor a zkopíruje ho do složky jazyků jako `<kód>.json`.
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

    /// Referenční jazyk pro šablonu (angličtina, jinak první dostupný).
    public func reference() -> LanguagePack? { pack(code: "en") ?? available().first }

    /// Zvolený jazyk se pamatuje v UserDefaults (volba rozhraní, platí hned – nečeká na „Použít“).
    public static let defaultsKey = "language"

    /// Přepne jazyk (nil/„cs“ = čeština) a zapamatuje volbu.
    public func select(_ code: String?, localizer: Localizer = .shared, defaults: UserDefaults = .standard) {
        let p = code.flatMap { pack(code: $0) }                     // čeština bez souboru = vestavěná
        localizer.use(p)
        defaults.set(p?.code ?? Localizer.baseCode, forKey: Self.defaultsKey)
    }

    /// Jazyk bez uložené volby (první spuštění).
    public static let defaultCode = "en"

    /// Obnoví jazyk z minulého spuštění; bez volby angličtina, chybějící soubor → čeština.
    public func restore(localizer: Localizer = .shared, defaults: UserDefaults = .standard) {
        let c = defaults.string(forKey: Self.defaultsKey) ?? Self.defaultCode
        localizer.use(pack(code: c))
    }
}
