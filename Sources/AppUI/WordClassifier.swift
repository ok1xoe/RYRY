// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

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
}
