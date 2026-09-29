// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
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

    /// Všechny jazyky (bez vestavěné češtiny), seřazené podle kódu.
    public func available() -> [LanguagePack] {
        var byCode: [String: LanguagePack] = [:]
        for d in bundled.reversed() { for p in packs(in: d) { byCode[p.code] = p } }
        for p in packs(in: userDirectory) { byCode[p.code] = p }
        return byCode.values.sorted { $0.code < $1.code }
    }

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
        let p = code.flatMap { $0 == Localizer.baseCode ? nil : pack(code: $0) }
        localizer.use(p)
        defaults.set(p?.code ?? Localizer.baseCode, forKey: Self.defaultsKey)
    }

    /// Jazyk bez uložené volby (první spuštění).
    public static let defaultCode = "en"

    /// Obnoví jazyk z minulého spuštění; bez volby angličtina, chybějící soubor → čeština.
    public func restore(localizer: Localizer = .shared, defaults: UserDefaults = .standard) {
        let c = defaults.string(forKey: Self.defaultsKey) ?? Self.defaultCode
        localizer.use(c == Localizer.baseCode ? nil : pack(code: c))
    }
}
