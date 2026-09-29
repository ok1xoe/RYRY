// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
@testable import Localization

private func tmp() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("lang-\(UUID())")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

private let en = LanguagePack(code: "en", name: "English", strings: ["Zvuk": "Audio", "Spojení: %d": "QSOs: %d"])

// Bez načteného jazyka (čeština) vrací klíč; po načtení překlad, chybějící klíč zůstane česky
@Test func translatesWithFallback() {
    let l = Localizer()
    #expect(l.tr("Zvuk") == "Zvuk")
    l.use(en)
    #expect(l.tr("Zvuk") == "Audio" && l.tr("Rig") == "Rig" && l.code == "en")
    #expect(l.tr("Spojení: %d", 5) == "QSOs: 5")
    l.use(nil)
    #expect(l.tr("Zvuk") == "Zvuk" && l.code == "cs")
}

// Změna jazyka se ohlásí přes Observation (SwiftUI překreslí všechna okna)
@Test func languageChangeIsObservable() {
    let l = Localizer()
    nonisolated(unsafe) var fired = false
    withObservationTracking { _ = l.tr("Zvuk") } onChange: { fired = true }
    l.use(en)
    #expect(fired)
}

// Soubor jazyka: JSON s kódem, názvem a tabulkou; prázdné hodnoty se ignorují (neúplný překlad)
@Test func packDecoding() throws {
    let json = #"{"code":"de","name":"Deutsch","version":1,"strings":{"Zvuk":"Ton","Rig":""}}"#
    let p = try LanguagePack.decode(Data(json.utf8))
    #expect(p.code == "de" && p.name == "Deutsch")
    let l = Localizer(); l.use(p)
    #expect(l.tr("Zvuk") == "Ton" && l.tr("Rig") == "Rig")
}

@Test func packRejectsGarbage() {
    #expect(throws: LanguagePack.PackError.self) { try LanguagePack.decode(Data("nonsense".utf8)) }
    #expect(throws: LanguagePack.PackError.self) { try LanguagePack.decode(Data(#"{"code":"","name":"X","strings":{}}"#.utf8)) }
}

// Překlad s jiným počtem/typem zástupných znaků než klíč se nepoužije (String(format:) by spadl)
@Test func mismatchedPlaceholdersFallBack() {
    let l = Localizer()
    l.use(LanguagePack(code: "xx", name: "X", strings: ["Spojení: %d": "QSO %@ %d"]))
    #expect(l.tr("Spojení: %d", 3) == "Spojení: 3")
}

// Knihovna: přibalené + nahrané jazyky; nahrání zkopíruje soubor do složky jazyků
@Test func libraryImportAndList() throws {
    let bundled = tmp(), user = tmp()
    try en.encoded().write(to: bundled.appendingPathComponent("en.json"))
    let lib = LanguageLibrary(bundled: [bundled], userDirectory: user)
    #expect(lib.available().map(\.code) == ["en"])
    let src = tmp().appendingPathComponent("muj.json")
    try LanguagePack(code: "de", name: "Deutsch", strings: ["Zvuk": "Ton"]).encoded().write(to: src)
    let p = try lib.importPack(from: src)
    #expect(p.code == "de")
    #expect(FileManager.default.fileExists(atPath: user.appendingPathComponent("de.json").path))
    #expect(lib.available().map(\.code) == ["de", "en"])
    #expect(lib.pack(code: "de")?.strings["Zvuk"] == "Ton")
    // nahraný soubor stejného kódu má přednost před přibaleným
    _ = try lib.importPack(from: { let u = tmp().appendingPathComponent("en.json")
        try! LanguagePack(code: "en", name: "English (mine)", strings: [:]).encoded().write(to: u); return u }())
    #expect(lib.pack(code: "en")?.name == "English (mine)")
}

// Šablona pro překladatele: všechny klíče, hodnoty z referenčního jazyka
@Test func templateHasAllKeys() throws {
    let t = LanguagePack.template(from: en)
    #expect(t.code == "xx" && Set(t.strings.keys) == Set(en.strings.keys) && t.strings["Zvuk"] == "Audio")
}

// Volba jazyka se zapamatuje a po restartu obnoví; zmizelý soubor → čeština
@Test func selectionPersists() throws {
    let bundled = tmp(), user = tmp()
    try en.encoded().write(to: bundled.appendingPathComponent("en.json"))
    let lib = LanguageLibrary(bundled: [bundled], userDirectory: user)
    let d = UserDefaults(suiteName: "lang-\(UUID())")!
    let l1 = Localizer()
    lib.select("en", localizer: l1, defaults: d)
    #expect(l1.code == "en" && d.string(forKey: LanguageLibrary.defaultsKey) == "en")
    let l2 = Localizer()
    lib.restore(localizer: l2, defaults: d)
    #expect(l2.tr("Zvuk") == "Audio")
    try FileManager.default.removeItem(at: bundled.appendingPathComponent("en.json"))
    let l3 = Localizer()
    lib.restore(localizer: l3, defaults: d)
    #expect(l3.code == "cs")
}

@Test func placeholderParsing() {
    #expect(Localizer.placeholders("%.1f dB %@ %ld 100%%") == ["f", "@", "ld"])
    #expect(Localizer.placeholders("%m moje · %l zalogovat · %N") == [])
}

// Bez uložené volby je rozhraní anglicky; výslovně zvolená čeština se pamatuje
@Test func defaultLanguageIsEnglish() throws {
    let bundled = tmp(), user = tmp()
    try en.encoded().write(to: bundled.appendingPathComponent("en.json"))
    let lib = LanguageLibrary(bundled: [bundled], userDirectory: user)
    let d = UserDefaults(suiteName: "lang-\(UUID())")!
    let l = Localizer()
    lib.restore(localizer: l, defaults: d)
    #expect(l.code == "en")
    lib.select("cs", localizer: l, defaults: d)
    let l2 = Localizer()
    lib.restore(localizer: l2, defaults: d)
    #expect(l2.code == "cs")
}


// Čeština je normální jazykový soubor (lze ho nahrát a upravit)
@Test func czechPackAllowed() throws {
    let p = try LanguagePack.decode(Data(#"{"code":"cs","name":"Čeština","strings":{"Zvuk":"Audio karta"}}"#.utf8))
    let l = Localizer(); l.use(p)
    #expect(l.code == "cs" && l.tr("Zvuk") == "Audio karta" && l.tr("Rig") == "Rig")
}

// Upravený soubor ve složce má přednost, chybějící texty doplní přibalená verze
@Test func userPackOverlaysBundled() throws {
    let bundled = tmp(), user = tmp()
    try en.encoded().write(to: bundled.appendingPathComponent("en.json"))
    try LanguagePack(code: "en", name: "English (mine)", strings: ["Zvuk": "Sound", "Nové": ""]).encoded()
        .write(to: user.appendingPathComponent("en.json"))
    let p = try #require(LanguageLibrary(bundled: [bundled], userDirectory: user).pack(code: "en"))
    #expect(p.name == "English (mine)" && p.strings["Zvuk"] == "Sound" && p.strings["Spojení: %d"] == "QSOs: %d")
}

// Při startu se přibalené jazyky zkopírují do složky; neupravené kopie se s novou verzí obnoví, upravené ne
@Test func seedUserDirectory() throws {
    let bundled = tmp(), user = tmp()
    try en.encoded().write(to: bundled.appendingPathComponent("en.json"))
    let lib = LanguageLibrary(bundled: [bundled], userDirectory: user)
    lib.seedUserDirectory()
    let u = user.appendingPathComponent("en.json")
    #expect(try LanguagePack.decode(Data(contentsOf: u)) == en)
    // nová verze aplikace: neupravená kopie se obnoví
    var v2 = en; v2.strings["Zvuk"] = "Sound card"
    try v2.encoded().write(to: bundled.appendingPathComponent("en.json"))
    lib.seedUserDirectory()
    #expect(try LanguagePack.decode(Data(contentsOf: u)).strings["Zvuk"] == "Sound card")
    // uživatel kopii upravil → další verze ji nepřepíše
    var mine = v2; mine.strings["Zvuk"] = "My audio"
    try mine.encoded().write(to: u)
    var v3 = v2; v3.strings["Zvuk"] = "Audio v3"
    try v3.encoded().write(to: bundled.appendingPathComponent("en.json"))
    lib.seedUserDirectory()
    #expect(try LanguagePack.decode(Data(contentsOf: u)).strings["Zvuk"] == "My audio")
    #expect(lib.pack(code: "en")?.strings["Zvuk"] == "My audio")
}
