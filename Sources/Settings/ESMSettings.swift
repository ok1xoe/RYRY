// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Závodní provoz: Run (volám CQ) nebo S&P (Search & Pounce, odpovídám na CQ).
public enum ESMMode: String, Codable, Sendable, CaseIterable { case run, sp }

/// „Enter Sends Message“ (jako N1MM Logger+): Enter v QSO okně pošle makro podle stavu spojení.
/// Makra jsou indexy 0…15 (F1–F12, ⇧F1–⇧F4).
public struct ESMSettings: Codable, Sendable, Equatable {
    public var enabled = false
    /// Aktuální (a po spuštění výchozí) režim; přepíná se i v QSO panelu a zkratkou.
    public var mode: ESMMode = .run
    public var runCQ = 0                  // F1 CQ
    public var runExchange = 3            // F4 Contest
    public var runTU = 4                  // F5 TU (%l zaloguje)
    public var spMyCall = 14              // ⇧F3 My call
    public var spExchange = 3             // F4 Contest
    /// AGN? – jen část výměny přijata (oba režimy).
    public var agn = 10                   // F11 AGN
    public init() {}

    enum CodingKeys: String, CodingKey { case enabled, mode, runCQ, runExchange, runTU, spMyCall, spExchange, agn }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "esm", x = ESMSettings()
        enabled = c.tolerant(.enabled, x.enabled, w, s); mode = c.tolerant(.mode, x.mode, w, s)
        func idx(_ k: CodingKeys, _ def: Int) -> Int {
            let v = c.tolerant(k, def, w, s)
            return (0..<AppSettings.macroCount).contains(v) ? v : def
        }
        runCQ = idx(.runCQ, x.runCQ); runExchange = idx(.runExchange, x.runExchange); runTU = idx(.runTU, x.runTU)
        spMyCall = idx(.spMyCall, x.spMyCall); spExchange = idx(.spExchange, x.spExchange); agn = idx(.agn, x.agn)
    }
}
