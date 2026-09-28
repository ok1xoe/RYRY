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

/// Přeskočí libovolnou JSON hodnotu (pro posun v nekeyovaném kontejneru po chybě).
struct Skip: Decodable { init(from decoder: Decoder) throws {} }

struct DynamicKey: CodingKey {
    var stringValue: String; var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

/// Pole, kde vadný prvek nahradí `fallback` (a varování) místo zahození celého pole.
struct TolerantArray<T: Decodable>: Decodable {
    var items: [T] = []
    init() {}
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var i = 0
        while !c.isAtEnd {
            if let v = try? c.decode(T.self) { items.append(v) }
            else {
                _ = try? c.decode(Skip.self)
                decoder.warningSink?.add("prvek \(i) je neplatný, vynechán")
                if let fb = (T.self as? any TolerantFallback.Type)?.fallback as? T { items.append(fb) }
            }
            i += 1
        }
    }
}

protocol TolerantFallback { static var fallback: Self { get } }

/// Slovník, kde vadná položka vypadne (s varováním) a ostatní zůstanou.
struct TolerantDict<V: Decodable>: Decodable {
    var items: [String: V] = [:]
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        for k in c.allKeys {
            if let v = try? c.decode(V.self, forKey: k) { items[k.stringValue] = v }
            else { decoder.warningSink?.add("\(k.stringValue): neplatná hodnota, vynechána") }
        }
    }
}
