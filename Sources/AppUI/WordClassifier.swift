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
        pattern: "^([A-Z0-9]{1,4}/)?([0-9]?[A-Z]{1,2}[0-9][A-Z0-9]*[A-Z])(/[A-Z0-9]{1,4})?$")
    static let rstRegex = try! NSRegularExpression(pattern: "^[1-5][1-9N][1-9N]([0-9]{1,4})?$")

    public static func classify(_ word: String) -> WordKind {
        let w = word.uppercased().trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "/")))
        guard !w.isEmpty else { return .other }
        let r = NSRange(w.startIndex..., in: w)
        if rstRegex.firstMatch(in: w, range: r) != nil { return .rst }
        if !stopWords.contains(w), callRegex.firstMatch(in: w, range: r) != nil { return .call }
        if !stopWords.contains(w), w.count >= 2, w.count <= 10, w.allSatisfy({ $0.isLetter && $0.isASCII }),
           !(w.first == "Q" && w.count == 3) {
            return .name
        }
        return .other
    }
}
