// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Localization
import Settings

/// Which QSO window fields are offered - depending on whether a contest is on and which format it uses.
public enum QSOLayout {
    public enum Row: Equatable, Sendable {
        case single(String, String)                    // field, label
        case pair(String, String, String, String)      // sent field+label, received field+label
        case country                                   // row with the DXCC entity
    }

    public static func rows(for c: ContestSettings) -> [Row] {
        let call = Row.single("call", "Call"), rst = Row.pair("rstSent", "RST s", "rstRcvd", "RST r")
        let notes = Row.single("notes", "Notes")
        let serial = Row.pair("serialSent", "Nr s", "serialRcvd", "Nr r")
        guard c.enabled else {
            return [call, .country, .single("name", "Name"), .single("qth", "QTH"), .single("locator", "Locator"), rst, notes]
        }
        let base = [call, .country, rst]
        switch c.format {
        case .serial:
            // ARRL RTTY Roundup: W/VE send a state/province instead of a number (multiplier), Russian contests an oblast …
            if c.receivesSerialOrCode, let code = c.selectedPreset?.alternativeCode {
                return base + [serial, .single("exchangeRcvd", code + " r"), notes]
            }
            return base + [c.exchange.isEmpty ? serial : .pair("exchangeSent", "Exch s", "exchangeRcvd", "Exch r"), notes]
        case .cqrj: return base + [.pair("exchangeSent", L("Zóna/QTH s"), "exchangeRcvd", L("Zóna/QTH r")), notes]
        case .bartg: return base + [serial, .pair("exchangeSent", L("Čas s"), "exchangeRcvd", L("Čas r")), notes]
        case .ped: return base + [notes]
        case .wae: return base + [serial, notes]
        case .zone: return base + [.pair("exchangeSent", L("Zóna s"), "exchangeRcvd", L("Zóna r")), notes]
        case .text:
            let t = c.selectedPreset?.textLabel ?? "Exch"
            return base + [.pair("exchangeSent", t + " s", "exchangeRcvd", t + " r"), notes]
        case .serialText:
            let t = c.selectedPreset?.textLabel ?? "Exch"
            return base + [serial, .pair("exchangeSent", t + " s", "exchangeRcvd", t + " r"), notes]
        }
    }

    /// The QTC panel only in the WAE contest.
    public static func showsQTC(_ c: ContestSettings) -> Bool { c.enabled && c.format == .wae }
}
