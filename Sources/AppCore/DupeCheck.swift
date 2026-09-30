// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import QSOLog
import Settings

/// Duplicita v závodě: stejná stanice (základní značka bez /P apod.) na stejném pásmu od začátku závodu; u vlastního
/// závodu navíc stejný mód. Předvolby (všechny jen RTTY) podle pravidel „stejnou stanici jednou na pásmu“ mód
/// nerozlišují (docs/rulings.md, „Bodování a skóre“). Bez známého pásma se porovná jen značka (a mód).
/// Jeden klíč (`key`) sdílí okno QSO, zvýraznění příjmu, band mapa i skóre.
public enum DupeCheck {
    /// Rozlišuje se mód? Předvolba = ne (pravidla: jednou na pásmu), vlastní závod = ano.
    public static func perMode(preset: ContestPreset?) -> Bool { preset == nil }

    /// Klíč duplicity: základní značka | pásmo („*“ = libovolné) | mód (prázdný, když se mód nerozlišuje).
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
