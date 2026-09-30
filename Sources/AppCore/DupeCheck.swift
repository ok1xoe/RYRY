// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import QSOLog
import Settings

/// Dupe in a contest: the same station (base call without /P etc.) on the same band since the contest start; in a custom
/// contest additionally the same mode. Presets (all RTTY only) do not distinguish the mode per the rules "the same station
/// once per band" (docs/rulings.md, "Scoring and score"). Without a known band only the call (and the mode) is compared.
/// A single key (`key`) is shared by the QSO window, receive highlighting, the band map and the score.
public enum DupeCheck {
    /// Is the mode distinguished? A preset = no (the rules: once per band), a custom contest = yes.
    public static func perMode(preset: ContestPreset?) -> Bool { preset == nil }

    /// Dupe key: base call | band ("*" = any) | mode (empty when the mode is not distinguished).
    public static func key(call: String, band: String?, mode: String, perMode: Bool) -> String {
        QSORecord.baseCall(call) + "|" + (band ?? "*") + "|" + (perMode ? mode.uppercased() : "")
    }

    public static func isDupe(call: String, band: String?, mode: String, records: [QSORecord], since: Date,
                              perMode: Bool = true) -> Bool {
        let k = key(call: call, band: band, mode: mode, perMode: perMode)
        return records.contains { r in
            r.timeOn >= since && key(call: r.call, band: band == nil ? nil : r.band, mode: r.mode, perMode: perMode) == k
        }
    }
}
