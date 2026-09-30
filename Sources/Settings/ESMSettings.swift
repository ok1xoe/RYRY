// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Contest operating: Run (I call CQ) or S&P (Search & Pounce, I answer CQs).
public enum ESMMode: String, Codable, Sendable, CaseIterable { case run, sp }

/// "Enter Sends Message" (like N1MM Logger+): Enter in the QSO window sends a macro according to the QSO state.
/// Macros are indexes 0…15 (F1–F12, ⇧F1–⇧F4).
public struct ESMSettings: Codable, Sendable, Equatable {
    public var enabled = false
    /// The current (and, after startup, the default) mode; it is also switched in the QSO panel and by a shortcut.
    public var mode: ESMMode = .run
    public var runCQ = 0                  // F1 CQ
    public var runExchange = 3            // F4 Contest
    public var runTU = 4                  // F5 TU (%l logs)
    public var spMyCall = 14              // ⇧F3 My call
    public var spExchange = 3             // F4 Contest
    /// AGN? – only part of the exchange was received (both modes).
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
