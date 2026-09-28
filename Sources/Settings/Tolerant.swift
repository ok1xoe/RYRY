// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Sběrač varování při tolerantním dekódování (předává se přes JSONDecoder.userInfo).
final class WarningSink: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.withLock { items.append(s) } }
    var all: [String] { lock.withLock { items } }
}

extension CodingUserInfoKey {
    static let warnings = CodingUserInfoKey(rawValue: "mmtty4mac.warnings")!
}

extension Decoder {
    var warningSink: WarningSink? { userInfo[.warnings] as? WarningSink }
}

extension KeyedDecodingContainer {
    /// Hodnota klíče, nebo výchozí; neplatná hodnota → výchozí + varování.
    func tolerant<T: Decodable>(_ key: Key, _ def: T, _ sink: WarningSink?, _ section: String) -> T {
        guard contains(key) else { return def }
        if (try? decodeNil(forKey: key)) == true { return def }
        do { return try decode(T.self, forKey: key) } catch {
            sink?.add("\(section).\(key.stringValue): neplatná hodnota, použita výchozí")
            return def
        }
    }
}
