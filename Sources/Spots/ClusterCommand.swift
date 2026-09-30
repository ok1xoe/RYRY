// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

public enum ClusterCommandError: Error, Equatable, Sendable {
    /// The DX cluster is not connected (or not logged in yet).
    case notConnected
    case empty
    case tooLong
    /// The line contains a control character (C0, DEL, C1, line/paragraph separator U+2028/U+2029).
    case controlCharacter
    /// A spot (`dx …`) without a frequency or a call (e.g. the macro `dx %k %c` with an empty call or without a rig).
    case incompleteSpot
    /// Sending failed at the connection level (TCP).
    case sendFailed(String)
}

/// Check of a line sent to the DX cluster: no control characters, at most 250 characters, non-empty, spot complete.
public enum ClusterCommand {
    public static let maxLength = 250

    /// Returns the line without surrounding spaces and without a trailing CR/LF, or throws an error.
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

    /// C0, DEL, C1 (U+0080–U+009F) and U+2028/U+2029 – the server could take them as an end of line or terminal control.
    static func isControl(_ u: Unicode.Scalar) -> Bool {
        u.value < 0x20 || (0x7F...0x9F).contains(u.value) || u.value == 0x2028 || u.value == 0x2029
    }

    /// Spot `dx <kHz> <call> [comment]` (the order of frequency and call is arbitrary) without a frequency or a call.
    /// Call = a word with both a letter and a digit, frequency = a positive number.
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
