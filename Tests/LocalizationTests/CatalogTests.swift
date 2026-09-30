// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
@testable import Localization

private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// The L("…") keys in the sources (the same regex as scripts/i18n-extract.py).
private func sourceKeys() throws -> Set<String> {
    let re = try NSRegularExpression(pattern: #"\bL\("((?:[^"\\]|\\.)*)""#)
    var out = Set<String>()
    let e = FileManager.default.enumerator(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)!
    for case let u as URL in e where u.pathExtension == "swift" {
        let s = try String(contentsOf: u, encoding: .utf8)
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            let k = String(s[Range(m.range(at: 1), in: s)!])
            out.insert(k.replacingOccurrences(of: #"\""#, with: "\"").replacingOccurrences(of: #"\\"#, with: "\\"))
        }
    }
    return out
}

// The bundled English covers all the interface texts and the placeholders match
@Test func englishCatalogIsComplete() throws {
    let keys = try sourceKeys()
    #expect(keys.count > 100)
    let en = try LanguagePack.decode(Data(contentsOf: root.appendingPathComponent("Resources/Languages/en.json")))
    let missing = keys.filter { (en.strings[$0] ?? "").isEmpty }.sorted()
    #expect(missing.isEmpty, "chybí překlad (scripts/i18n-extract.py --update): \(missing.prefix(20))")
    let stale = en.strings.keys.filter { !keys.contains($0) }.sorted()
    #expect(stale.isEmpty, "nepoužívané klíče: \(stale.prefix(20))")
    for (k, v) in en.strings where !v.isEmpty {
        #expect(Localizer.placeholders(k) == Localizer.placeholders(v), "zástupné znaky: \(k) → \(v)")
    }
}


// The bundled Czech contains all the interface texts
@Test func czechCatalogIsComplete() throws {
    let keys = try sourceKeys()
    let cs = try LanguagePack.decode(Data(contentsOf: root.appendingPathComponent("Resources/Languages/cs.json")))
    #expect(cs.code == "cs")
    let missing = keys.filter { (cs.strings[$0] ?? "").isEmpty }.sorted()
    #expect(missing.isEmpty, "chybí (scripts/i18n-extract.py --update): \(missing.prefix(20))")
    #expect(cs.strings.keys.filter { !keys.contains($0) }.isEmpty)
}
