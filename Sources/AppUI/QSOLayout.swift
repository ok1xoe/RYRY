// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Settings

/// Která pole QSO okna se nabízejí – podle toho, zda je zapnutý závod a jakého formátu.
public enum QSOLayout {
    public enum Row: Equatable, Sendable {
        case single(String, String)                    // pole, popisek
        case pair(String, String, String, String)      // odeslané pole+popisek, přijaté pole+popisek
        case country                                   // řádek se zemí DXCC
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
            return base + [c.exchange.isEmpty ? serial : .pair("exchangeSent", "Exch s", "exchangeRcvd", "Exch r"), notes]
        case .cqrj: return base + [.pair("exchangeSent", "Zóna/QTH s", "exchangeRcvd", "Zóna/QTH r"), notes]
        case .bartg: return base + [serial, .pair("exchangeSent", "Čas s", "exchangeRcvd", "Čas r"), notes]
        case .ped: return base + [notes]
        case .wae: return base + [serial, notes]
        case .zone: return base + [.pair("exchangeSent", "Zóna s", "exchangeRcvd", "Zóna r"), notes]
        }
    }

    /// Panel QTC jen v závodě WAE.
    public static func showsQTC(_ c: ContestSettings) -> Bool { c.enabled && c.format == .wae }
}
