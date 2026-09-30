// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Localization
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
            // ARRL RTTY Roundup: W/VE posílají stát/provincii místo čísla (násobič) – přijatá výměna zvlášť
            if c.isRoundupStateExchange {
                return base + [serial, .single("exchangeRcvd", L("Stát/prov. r")), notes]
            }
            return base + [c.exchange.isEmpty ? serial : .pair("exchangeSent", "Exch s", "exchangeRcvd", "Exch r"), notes]
        case .cqrj: return base + [.pair("exchangeSent", L("Zóna/QTH s"), "exchangeRcvd", L("Zóna/QTH r")), notes]
        case .bartg: return base + [serial, .pair("exchangeSent", L("Čas s"), "exchangeRcvd", L("Čas r")), notes]
        case .ped: return base + [notes]
        case .wae: return base + [serial, notes]
        case .zone: return base + [.pair("exchangeSent", L("Zóna s"), "exchangeRcvd", L("Zóna r")), notes]
        }
    }

    /// Panel QTC jen v závodě WAE.
    public static func showsQTC(_ c: ContestSettings) -> Bool { c.enabled && c.format == .wae }
}
