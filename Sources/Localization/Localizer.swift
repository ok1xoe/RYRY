// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Observation

/// Language file: a table of "Czech text → translation". Czech is the default language, straight in the code,
/// any other language is JSON `{"code":"en","name":"English","version":1,"strings":{…}}`.
public struct LanguagePack: Codable, Sendable, Equatable {
    public enum PackError: Error, Equatable { case unreadable(String), invalid(String) }
    public var code: String
    public var name: String
    public var version: Int
    public var strings: [String: String]

    public init(code: String, name: String, version: Int = 1, strings: [String: String]) {
        self.code = code; self.name = name; self.version = version; self.strings = strings
    }

    enum CodingKeys: String, CodingKey { case code, name, version, strings }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code); name = try c.decode(String.self, forKey: .name)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 1          // optional
        strings = try c.decode([String: String].self, forKey: .strings)
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
        guard code.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw PackError.invalid(L("Neplatný kód jazyka „%@“.", code))
        }
        return p
    }

    /// The error text for the user.
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

    /// Template for a new translation: all keys with the values from the reference language (English).
    public static func template(from ref: LanguagePack) -> LanguagePack {
        LanguagePack(code: "xx", name: "New language", version: ref.version, strings: ref.strings)
    }
}

/// The current UI language. A change is announced through Observation, so SwiftUI redraws all windows at once.
/// It is read from actors as well (AppController reports), so the state is protected by a lock.
public final class Localizer: Observable, @unchecked Sendable {
    public static let shared = Localizer()
    public static let baseCode = "cs"

    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private var _code = Localizer.baseCode
    private var _name = "Čeština"
    private var table: [String: String] = [:]

    public init() {}

    /// The code of the active language ("cs" = the built-in Czech).
    public var code: String {
        registrar.access(self, keyPath: \.code)
        return lock.withLock { _code }
    }

    public var name: String {
        registrar.access(self, keyPath: \.code)
        return lock.withLock { _name }
    }

    /// Switches the language; nil = Czech.
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

    /// Text with placeholders (%@, %d, %.1f…) – a translation is used only if it has the same placeholders as the key.
    public func tr(_ key: String, _ args: [any CVarArg]) -> String {
        var fmt = tr(key)
        if fmt != key, Self.placeholders(fmt) != Self.placeholders(key) { fmt = key }
        return String(format: fmt, locale: Locale(identifier: "en_US_POSIX"), arguments: args)
    }

    public func tr(_ key: String, _ args: any CVarArg...) -> String { tr(key, args) }

    /// The sequence of format conversions (without width and precision), e.g. "%.1f %@ %ld" → ["f", "@", "ld"].
    /// Macro texts such as "%m" or "%l log" are not conversions and are not counted.
    static func placeholders(_ s: String) -> [String] {
        s.replacingOccurrences(of: "%%", with: "").matches(of: placeholder).map { String($0.output.1) }
    }
    nonisolated(unsafe) private static let placeholder =
        /%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?((?:ll|l|h|hh|q|z|t|j)?[@dDiuUxXoOfeEgGcCsSaAp])/
}

/// Translation of a UI text (the key is the Czech text).
public func L(_ key: String) -> String { Localizer.shared.tr(key) }

/// Translation of a text with placeholders: `L("Spojení: %d", n)`.
public func L(_ key: String, _ args: any CVarArg...) -> String { Localizer.shared.tr(key, args) }
