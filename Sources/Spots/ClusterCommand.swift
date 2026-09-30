// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

public enum ClusterCommandError: Error, Equatable, Sendable {
    /// DX cluster není připojený (nebo ještě není přihlášený).
    case notConnected
    case empty
    case tooLong
    /// Řádek obsahuje řídicí znak (C0, DEL, C1, oddělovač řádku/odstavce U+2028/U+2029).
    case controlCharacter
    /// Spot (`dx …`) bez kmitočtu nebo bez značky (např. makro `dx %k %c` s prázdnou značkou nebo bez rigu).
    case incompleteSpot
    /// Odeslání selhalo na úrovni spojení (TCP).
    case sendFailed(String)
}

/// Kontrola řádku odesílaného do DX clusteru: žádné řídicí znaky, nejvýš 250 znaků, neprázdný, spot úplný.
public enum ClusterCommand {
    public static let maxLength = 250

    /// Vrátí řádek bez okrajových mezer a bez koncového CR/LF, nebo vyhodí chybu.
    public static func validate(_ raw: String) throws -> String {
        var s = raw
        while s.last == "\r\n" || s.last == "\n" || s.last == "\r" { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { throw ClusterCommandError.empty }
        if s.unicodeScalars.contains(where: isControl) { throw ClusterCommandError.controlCharacter }
        if s.count > maxLength { throw ClusterCommandError.tooLong }
        if isIncompleteSpot(s) { throw ClusterCommandError.incompleteSpot }
        return s
    }

    /// C0, DEL, C1 (U+0080–U+009F) a U+2028/U+2029 – server by je mohl brát jako konec řádku nebo řízení terminálu.
    static func isControl(_ u: Unicode.Scalar) -> Bool {
        u.value < 0x20 || (0x7F...0x9F).contains(u.value) || u.value == 0x2028 || u.value == 0x2029
    }

    /// Spot `dx <kHz> <značka> [komentář]` (pořadí kmitočtu a značky libovolné) bez kmitočtu nebo značky.
    /// Značka = slovo s písmenem i číslicí, kmitočet = kladné číslo.
    static func isIncompleteSpot(_ s: String) -> Bool {
        guard s.lowercased().hasPrefix("dx ") else { return false }
        let words = s.split(separator: " ").dropFirst().map(String.init)
        let freq = words.firstIndex { Double($0).map { $0 > 0 } ?? false }
        let call = words.indices.first { i in
            i != freq && Double(words[i]) == nil && words[i].contains(where: \.isLetter) && words[i].contains(where: \.isNumber)
        }
        return freq == nil || call == nil
    }
}
