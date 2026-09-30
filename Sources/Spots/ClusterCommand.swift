// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

public enum ClusterCommandError: Error, Equatable, Sendable {
    /// DX cluster není připojený (nebo ještě není přihlášený).
    case notConnected
    case empty
    case tooLong
    /// Řádek obsahuje řídicí znak (kromě CR LF na konci, který se ořízne).
    case controlCharacter
}

/// Kontrola řádku odesílaného do DX clusteru: žádné řídicí znaky, nejvýš 250 znaků, neprázdný.
public enum ClusterCommand {
    public static let maxLength = 250

    /// Vrátí řádek bez okrajových mezer a bez koncového CR/LF, nebo vyhodí chybu.
    public static func validate(_ raw: String) throws -> String {
        var s = raw
        while s.last == "\r\n" || s.last == "\n" || s.last == "\r" { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { throw ClusterCommandError.empty }
        if s.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) { throw ClusterCommandError.controlCharacter }
        if s.count > maxLength { throw ClusterCommandError.tooLong }
        return s
    }
}
