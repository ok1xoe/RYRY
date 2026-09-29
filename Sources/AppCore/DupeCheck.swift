// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import QSOLog

/// Duplicita v závodě: stejná stanice (základní značka bez /P apod.), stejné pásmo a mód od začátku závodu.
/// Bez známého pásma se porovná jen značka a mód.
public enum DupeCheck {
    public static func isDupe(call: String, band: String?, mode: String, records: [QSORecord], since: Date) -> Bool {
        let b = QSORecord.baseCall(call)
        return records.contains { r in
            r.timeOn >= since && QSORecord.baseCall(r.call) == b && r.mode.uppercased() == mode.uppercased()
                && (band == nil || r.band == band)
        }
    }
}
