// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import Foundation
import Settings

public enum WordKind: Equatable, Sendable { case call, rst, name, other }

/// Rozpozná, co je slovo z RX textu (klik → pole QSO okna).
public enum WordClassifier {
    static let stopWords: Set<String> = [
        "CQ", "DE", "TU", "PSE", "RST", "UR", "UR", "K", "KN", "SK", "BK", "AR", "QTH", "NAME", "HW", "HR", "ES",
        "TNX", "TKS", "FB", "OM", "YL", "GM", "GA", "GE", "GL", "GD", "DX", "TEST", "QRZ", "QSL", "QSO", "BTU",
        "AGN", "NR", "MY", "IS", "THE", "AND", "FER", "FOR", "OP", "RIG", "ANT", "WX", "PWR", "ALL", "OK", "SRI",
        "RRR", "R", "CFM", "INFO", "VIA", "BURO", "EQSL", "LOTW", "CL", "QRL", "QRM", "QRN", "QSB", "QSY",
    ]
    // ITU značka: [prefix/]znaky s číslicí uprostřed[/suffix]
    static let callRegex = try! NSRegularExpression(
        pattern: "^([A-Z0-9]{1,4}/)?([A-Z]{1,2}[0-9]{1,2}[A-Z]{1,4}|[0-9][A-Z][0-9]{1,2}[A-Z]{2,4})(/[A-Z0-9]{1,4})?$")
    // RST 3 znaky, nebo 599/5NN + číslo závodu
    static let rstRegex = try! NSRegularExpression(pattern: "^([1-5][1-9N][1-9N]|5[1-9N][9N][0-9]{1,4})$")

    public static func classify(_ word: String) -> WordKind {
        let w = word.uppercased().trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "/")))
        guard !w.isEmpty else { return .other }
        let r = NSRange(w.startIndex..., in: w)
        if rstRegex.firstMatch(in: w, range: r) != nil { return .rst }
        // značka: min. 4 znaky (nebo s lomítkem), aby šum typu E5T nepřepsal pole
        if !stopWords.contains(w), w.count >= 4 || w.contains("/"), callRegex.firstMatch(in: w, range: r) != nil {
            return .call
        }
        if !stopWords.contains(w), w.count >= 2, w.count <= 10, w.allSatisfy({ $0.isLetter && $0.isASCII }),
           !w.contains(where: \.isNumber),
           !(w.first == "Q" && w.count == 3) {
            return .name
        }
        return .other
    }

    /// Závod (MMTTY „Misc“): slovo z RX textu jako přijaté číslo, RST nebo výměna; nil = nevkládat.
    /// `serialMode` = výměna je pořadové číslo („599“ + číslo), jinak libovolná výměna (zóna, stát…).
    public static func contestField(_ word: String, serialMode: Bool) -> (String, String)? {
        let w = word.uppercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        guard !w.isEmpty, !stopWords.contains(w) else { return nil }
        if w == "599" { return ("rstRcvd", w) }
        var rest = Substring(w)
        if w.count >= 4, w.hasPrefix("599") { rest = rest.dropFirst(3) }     // 599015 → 015
        if serialMode {
            guard !rest.isEmpty, rest.count <= 5, rest.allSatisfy(\.isNumber), let n = Int(rest) else { return nil }
            return ("serialRcvd", String(n))
        }
        guard rest.count <= 8, rest.allSatisfy({ ($0.isLetter || $0.isNumber) && $0.isASCII }) else { return nil }
        return ("exchangeRcvd", String(rest))
    }

    /// Klik na slovo v závodě podle formátu (MMTTY TMmttyWd::PBoxRxMouseDown, StoreZone/StoreQTH/StoreNR/StoreUTC).
    /// Vrací pole QSO okna k nastavení. PED řeší volající (každé slovo = značka).
    public static func contestUpdate(_ word: String, format: ContestFormat, serialMode: Bool,
                                     current q: QSOFields) -> [(String, String)] {
        let w = word.uppercased().trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: ":"))
            .union(.whitespaces))
        // státy/provincie, které jsou zároveň běžné zkratky (CQ WW RTTY: OK = Oklahoma, AR = Arkansas)
        let qthAbbrev: Set<String> = ["OK", "AR", "OR", "ME", "HI", "IN", "MA", "ON", "AB"]
        guard !w.isEmpty, !stopWords.contains(w) || (format == .cqrj && qthAbbrev.contains(w)) else { return [] }
        if w == "599" { return [("rstRcvd", w)] }
        var rest = Substring(w)
        if w.count >= 4, w.hasPrefix("599"), w.dropFirst(3).allSatisfy(\.isNumber) { rest = rest.dropFirst(3) }
        switch format {
        case .zone:
            // RST + CQ zóna: číslo 1–40 (i „59914“) = zóna protistanice
            guard !rest.isEmpty, rest.count <= 2, rest.allSatisfy(\.isNumber), let z = Int(rest), (1...40).contains(z) else { return [] }
            return [("exchangeRcvd", String(z))]
        case .serial, .ped, .wae:
            return contestField(word, serialMode: serialMode).map { [$0] } ?? []
        case .cqrj:
            // „ZZ QTH“: číslo = zóna, text = QTH (druhá část zůstane)
            let parts = q.exchangeRcvd.split(separator: " ", maxSplits: 1).map(String.init)
            var zone = parts.first.flatMap { Int($0) != nil ? $0 : nil } ?? ""
            var qth = parts.count > 1 ? parts[1] : (zone.isEmpty ? (parts.first ?? "") : "")
            if rest.allSatisfy(\.isNumber) {
                guard let z = Int(rest), z >= 0 else { return [] }
                zone = String(format: "%02d", z)
            } else {
                guard rest.count <= 8, rest.allSatisfy({ ($0.isLetter || $0.isNumber) && $0.isASCII }) else { return [] }
                qth = String(rest)
            }
            return [("exchangeRcvd", [zone, qth].filter { !$0.isEmpty }.joined(separator: " "))]
        case .bartg:
            if rest.contains(":") {
                let hm = rest.split(separator: ":")
                guard hm.count == 2, let h = Int(hm[0]), let m = Int(hm[1]), h < 24, m < 60 else { return [] }
                return [("exchangeRcvd", String(format: "%02d%02d", h, m))]
            }
            guard !rest.isEmpty, rest.count <= 5, rest.allSatisfy(\.isNumber), let n = Int(rest) else { return [] }
            // MMTTY: do 3 číslic číslo, delší = čas HHMM, pokud je platný (StoreUTC → jinak StoreNR)
            if rest.count > 3, n / 100 < 24, n % 100 < 60 { return [("exchangeRcvd", String(format: "%02d%02d", n / 100, n % 100))] }
            return [("serialRcvd", String(n))]
        }
    }
}
