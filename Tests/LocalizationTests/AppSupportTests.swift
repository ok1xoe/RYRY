import Foundation
import Testing
@testable import Localization

// The former name mmtty4mac: the data folder is renamed to RYRY at launch, the preferences are taken over.

private func tmp() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("appsupport-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@Test func legacyFolderIsUsedThenRenamed() throws {
    let base = tmp(), fm = FileManager.default
    #expect(AppSupport.directory(in: base).lastPathComponent == "RYRY")
    try fm.createDirectory(at: base.appendingPathComponent("mmtty4mac/Languages"), withIntermediateDirectories: true)
    #expect(AppSupport.directory(in: base).lastPathComponent == "mmtty4mac")      // before the move
    AppSupport.migrateFolder(in: base)
    #expect(fm.fileExists(atPath: base.appendingPathComponent("RYRY/Languages").path))
    #expect(!fm.fileExists(atPath: base.appendingPathComponent("mmtty4mac").path))
    #expect(AppSupport.directory(in: base).lastPathComponent == "RYRY")
    // a second legacy folder next to an existing RYRY is left alone
    try fm.createDirectory(at: base.appendingPathComponent("mmtty4mac"), withIntermediateDirectories: true)
    AppSupport.migrateFolder(in: base)
    #expect(fm.fileExists(atPath: base.appendingPathComponent("mmtty4mac").path))
}

@Test func legacyDefaultsFillOnlyMissingKeys() {
    let d = UserDefaults(suiteName: "appsupport-test-\(UUID().uuidString)")!
    d.set("cs", forKey: "language")
    AppSupport.migrateDefaults(from: ["language": "en", "settingsTab": 5], to: d)
    #expect(d.string(forKey: "language") == "cs" && d.integer(forKey: "settingsTab") == 5)
}
