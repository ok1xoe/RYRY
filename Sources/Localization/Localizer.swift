// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Observation

/// Jazykový soubor: tabulka „český text → překlad“. Čeština je výchozí jazyk přímo v kódu,
/// jiný jazyk je JSON `{"code":"en","name":"English","version":1,"strings":{…}}`.
public struct LanguagePack: Codable, Sendable, Equatable {
    public enum PackError: Error, Equatable { case unreadable(String), invalid(String) }
    public var code: String
    public var name: String
    public var version: Int
    public var strings: [String: String]

    public init(code: String, name: String, version: Int = 1, strings: [String: String]) {
        self.code = code; self.name = name; self.version = version; self.strings = strings
    }

    public static func decode(_ data: Data) throws -> LanguagePack {
        let p: LanguagePack
        do { p = try JSONDecoder().decode(LanguagePack.self, from: data) } catch {
            throw PackError.unreadable(L("Soubor není platný jazykový JSON: %@", error.localizedDescription))
        }
        let code = p.code.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty, !p.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PackError.invalid(L("Chybí kód nebo název jazyka."))
        }
        guard code != Localizer.baseCode else { throw PackError.invalid(L("Čeština je vestavěná, nelze ji nahradit.")) }
        guard code.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw PackError.invalid(L("Neplatný kód jazyka „%@“.", code))
        }
        return p
    }

    /// Text chyby pro uživatele.
    public static func message(_ e: Error) -> String {
        switch e as? PackError {
        case .unreadable(let m)?, .invalid(let m)?: return m
        case nil: return e.localizedDescription
        }
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }

    /// Šablona pro nový překlad: všechny klíče s hodnotami z referenčního jazyka (angličtiny).
    public static func template(from ref: LanguagePack) -> LanguagePack {
        LanguagePack(code: "xx", name: "New language", version: ref.version, strings: ref.strings)
    }
}

/// Aktuální jazyk rozhraní. Změna se ohlásí přes Observation, takže SwiftUI hned překreslí všechna okna.
/// Čte se i z actorů (hlášení AppControlleru), proto je stav chráněný zámkem.
public final class Localizer: Observable, @unchecked Sendable {
    public static let shared = Localizer()
    public static let baseCode = "cs"

    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private var _code = Localizer.baseCode
    private var _name = "Čeština"
    private var table: [String: String] = [:]

    public init() {}

    /// Kód aktivního jazyka („cs“ = vestavěná čeština).
    public var code: String {
        registrar.access(self, keyPath: \.code)
        return lock.withLock { _code }
    }

    public var name: String {
        registrar.access(self, keyPath: \.code)
        return lock.withLock { _name }
    }

    /// Přepne jazyk; nil = čeština.
    public func use(_ pack: LanguagePack?) {
        registrar.withMutation(of: self, keyPath: \.code) {
            lock.withLock {
                _code = pack?.code ?? Self.baseCode
                _name = pack?.name ?? "Čeština"
                table = (pack?.strings ?? [:]).filter { !$0.value.isEmpty }
            }
        }
    }

    public func tr(_ key: String) -> String {
        registrar.access(self, keyPath: \.code)
        return lock.withLock { table[key] } ?? key
    }

    /// Text se zástupnými znaky (%@, %d, %.1f…) – překlad se použije, jen když má stejné zástupné znaky jako klíč.
    public func tr(_ key: String, _ args: [any CVarArg]) -> String {
        var fmt = tr(key)
        if fmt != key, Self.placeholders(fmt) != Self.placeholders(key) { fmt = key }
        return String(format: fmt, locale: Locale(identifier: "en_US_POSIX"), arguments: args)
    }

    public func tr(_ key: String, _ args: any CVarArg...) -> String { tr(key, args) }

    /// Posloupnost konverzí formátu (bez šířky a přesnosti), např. „%.1f %@ %ld“ → ["f", "@", "ld"].
    /// Texty maker jako „%m“ nebo „%l zalogovat“ nejsou konverze a nepočítají se.
    static func placeholders(_ s: String) -> [String] {
        s.replacingOccurrences(of: "%%", with: "").matches(of: placeholder).map { String($0.output.1) }
    }
    nonisolated(unsafe) private static let placeholder =
        /%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?((?:ll|l|h|hh|q|z|t|j)?[@dDiuUxXoOfeEgGcCsSaAp])/
}

/// Překlad textu rozhraní (klíč = český text).
public func L(_ key: String) -> String { Localizer.shared.tr(key) }

/// Překlad textu se zástupnými znaky: `L("Spojení: %d", n)`.
public func L(_ key: String, _ args: any CVarArg...) -> String { Localizer.shared.tr(key, args) }
