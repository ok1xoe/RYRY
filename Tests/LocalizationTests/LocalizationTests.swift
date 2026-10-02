// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Testing
@testable import Localization

private func tmp() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("lang-\(UUID())")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

private let en = LanguagePack(code: "en", name: "English", strings: ["Zvuk": "Audio", "Spojení: %d": "QSOs: %d"])

// With no language loaded (Czech) the key is returned; after loading, the translation, and a missing key stays in Czech
@Test func translatesWithFallback() {
    let l = Localizer()
    #expect(l.tr("Zvuk") == "Zvuk")
    l.use(en)
    #expect(l.tr("Zvuk") == "Audio" && l.tr("Rig") == "Rig" && l.code == "en")
    #expect(l.tr("Spojení: %d", 5) == "QSOs: 5")
    l.use(nil)
    #expect(l.tr("Zvuk") == "Zvuk" && l.code == "cs")
}

// A language change is announced through Observation (SwiftUI redraws all the windows)
@Test func languageChangeIsObservable() {
    let l = Localizer()
    nonisolated(unsafe) var fired = false
    withObservationTracking { _ = l.tr("Zvuk") } onChange: { fired = true }
    l.use(en)
    #expect(fired)
}

// A language file: JSON with a code, a name and a table; empty values are ignored (an incomplete translation)
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

// A translation with a different number/type of placeholders than the key is not used (String(format:) would crash)
@Test func mismatchedPlaceholdersFallBack() {
    let l = Localizer()
    l.use(LanguagePack(code: "xx", name: "X", strings: ["Spojení: %d": "QSO %@ %d"]))
    #expect(l.tr("Spojení: %d", 3) == "Spojení: 3")
}

// The library: the bundled plus the loaded languages; loading copies the file into the languages folder
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
    // a loaded file with the same code takes precedence over the bundled one
    _ = try lib.importPack(from: { let u = tmp().appendingPathComponent("en.json")
        try! LanguagePack(code: "en", name: "English (mine)", strings: [:]).encoded().write(to: u); return u }())
    #expect(lib.pack(code: "en")?.name == "English (mine)")
}

// A template for translators: all the keys, with the values from the reference language
@Test func templateHasAllKeys() throws {
    let t = LanguagePack.template(from: en)
    #expect(t.code == "xx" && Set(t.strings.keys) == Set(en.strings.keys) && t.strings["Zvuk"] == "Audio")
}

// The language choice is remembered and restored after a restart; a file that is gone → Czech
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

// With no stored choice the interface is in English; Czech chosen explicitly is remembered
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


// Czech is an ordinary language file (it can be loaded and edited)
@Test func czechPackAllowed() throws {
    let p = try LanguagePack.decode(Data(#"{"code":"cs","name":"Čeština","strings":{"Zvuk":"Audio karta"}}"#.utf8))
    let l = Localizer(); l.use(p)
    #expect(l.code == "cs" && l.tr("Zvuk") == "Audio karta" && l.tr("Rig") == "Rig")
}

// An edited file in the folder takes precedence, missing texts are filled in from the bundled version
@Test func userPackOverlaysBundled() throws {
    let bundled = tmp(), user = tmp()
    try en.encoded().write(to: bundled.appendingPathComponent("en.json"))
    try LanguagePack(code: "en", name: "English (mine)", strings: ["Zvuk": "Sound", "Nové": ""]).encoded()
        .write(to: user.appendingPathComponent("en.json"))
    let p = try #require(LanguageLibrary(bundled: [bundled], userDirectory: user).pack(code: "en"))
    #expect(p.name == "English (mine)" && p.strings["Zvuk"] == "Sound" && p.strings["Spojení: %d"] == "QSOs: %d")
}

// At start-up the bundled languages are copied into the folder; unedited copies are refreshed with a new version, edited ones are not
@Test func seedUserDirectory() throws {
    let bundled = tmp(), user = tmp()
    try en.encoded().write(to: bundled.appendingPathComponent("en.json"))
    let lib = LanguageLibrary(bundled: [bundled], userDirectory: user)
    lib.seedUserDirectory()
    let u = user.appendingPathComponent("en.json")
    #expect(try LanguagePack.decode(Data(contentsOf: u)) == en)
    // a new version of the application: the unedited copy is refreshed
    var v2 = en; v2.strings["Zvuk"] = "Sound card"
    try v2.encoded().write(to: bundled.appendingPathComponent("en.json"))
    lib.seedUserDirectory()
    #expect(try LanguagePack.decode(Data(contentsOf: u)).strings["Zvuk"] == "Sound card")
    // the user edited the copy → the next version does not overwrite it
    var mine = v2; mine.strings["Zvuk"] = "My audio"
    try mine.encoded().write(to: u)
    var v3 = v2; v3.strings["Zvuk"] = "Audio v3"
    try v3.encoded().write(to: bundled.appendingPathComponent("en.json"))
    lib.seedUserDirectory()
    #expect(try LanguagePack.decode(Data(contentsOf: u)).strings["Zvuk"] == "My audio")
    #expect(lib.pack(code: "en")?.strings["Zvuk"] == "My audio")
}

// Saving an edited file in the languages folder takes effect immediately (without a restart)
@Test func editedFileAppliesLive() async throws {
    let bundled = tmp(), user = tmp()
    try en.encoded().write(to: bundled.appendingPathComponent("en.json"))
    let lib = LanguageLibrary(bundled: [bundled], userDirectory: user)
    lib.seedUserDirectory()
    let d = UserDefaults(suiteName: "lang-\(UUID())")!
    let l = Localizer()
    lib.select("en", localizer: l, defaults: d)
    #expect(l.tr("Zvuk") == "Audio")
    let watcher = LanguageWatcher(library: lib, localizer: l, defaults: d, deliverOn: DispatchQueue(label: "t"))
    watcher.start()
    var mine = en; mine.strings["Zvuk"] = "Sound card"
    try mine.encoded().write(to: user.appendingPathComponent("en.json"), options: .atomic)
    for _ in 0..<40 where l.tr("Zvuk") != "Sound card" { try await Task.sleep(for: .milliseconds(50)) }
    #expect(l.tr("Zvuk") == "Sound card")
    watcher.stop()
}
