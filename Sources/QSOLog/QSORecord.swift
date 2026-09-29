// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Jedno spojení. Zdroj pravdy je JSONL (Codable), ADIF se z něj odvozuje.
public struct QSORecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var call: String
    public var timeOn: Date
    public var timeOff: Date?
    public var frequency: Double?          // Hz
    public var mode: String
    public var submode: String?
    public var rstSent: String?
    public var rstRcvd: String?
    public var name: String?
    public var qth: String?
    public var grid: String?
    public var serialSent: Int?
    public var serialRcvd: Int?
    public var exchangeSent: String?
    public var exchangeRcvd: String?
    public var comment: String?
    public var stationCallsign: String?
    // DXCC (z cty.dat při zalogování)
    public var country: String?
    public var continent: String?
    public var cqZone: Int?
    public var ituZone: Int?
    /// Kdy bylo spojení nahráno na online služby (klíč = `UploadTarget.rawValue`). Starší logy pole nemají.
    public var uploads: [String: Date]?

    public init(id: UUID = UUID(), call: String, timeOn: Date, mode: String = "RTTY") {
        self.id = id; self.call = call.uppercased(); self.timeOn = timeOn; self.mode = mode
    }

    public func isUploaded(_ t: UploadTarget) -> Bool { uploads?[t.rawValue] != nil }
    public mutating func markUploaded(_ t: UploadTarget, at: Date = Date()) {
        var u = uploads ?? [:]; u[t.rawValue] = at; uploads = u
    }

    public var band: String? { Bands.band(forHz: frequency) }

    public static func normalizeCall(_ c: String) -> String {
        c.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Značka bez /P, /M, prefixu země apod. (nejdelší část mezi lomítky).
    public static func baseCall(_ call: String) -> String {
        let parts = call.uppercased().split(separator: "/").map(String.init)
        return parts.max { $0.count < $1.count } ?? call.uppercased()
    }
}

/// Online služby, na které se spojení nahrávají.
public enum UploadTarget: String, Codable, Sendable, CaseIterable { case lotw, eqsl, clublog }

public enum Bands {
    static let table: [(String, Double, Double)] = [
        ("2190m", 0.1357, 0.1378), ("630m", 0.472, 0.479), ("160m", 1.8, 2.0), ("80m", 3.5, 4.0),
        ("60m", 5.06, 5.45), ("40m", 7.0, 7.3), ("30m", 10.1, 10.15), ("20m", 14.0, 14.35),
        ("17m", 18.068, 18.168), ("15m", 21.0, 21.45), ("12m", 24.89, 24.99), ("10m", 28.0, 29.7),
        ("6m", 50, 54), ("4m", 70, 71), ("2m", 144, 148), ("1.25m", 222, 225), ("70cm", 420, 450),
    ]
    public static func band(forHz hz: Double?) -> String? {
        guard let hz, hz.isFinite else { return nil }
        let mhz = hz / 1e6
        return table.first { mhz >= $0.1 && mhz <= $0.2 }?.0
    }
}
