// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Upozornění: někdo volá mou značku, hlídané značky a potřebné země (v příjmu i ve spotech).
public struct AlertSettings: Codable, Sendable, Equatable {
    /// V přijatém textu se objevila moje značka: zvuk / systémové oznámení (jen když aplikace není aktivní).
    public var myCallSound = true
    public var myCallNotification = false
    /// Hlídané značky, jedna na řádek (porovnává se základní značka bez /P apod.).
    public var watchCalls = ""
    /// Země, která na aktuálním pásmu ještě není v logu / která v logu není vůbec.
    public var newCountryBand = false
    public var newCountryAny = false
    /// Upozornění na potřebné značky a země zvukem / systémovým oznámením (řádek ve stavovém řádku je vždy).
    public var neededSound = true
    public var neededNotification = false
    public init() {}

    public static let maxWatchLength = 20_000

    enum CodingKeys: String, CodingKey {
        case myCallSound, myCallNotification, watchCalls, newCountryBand, newCountryAny, neededSound, neededNotification
    }

    /// Hlídané značky jako množina základních značek (velká písmena; oddělovač řádek, čárka, mezera, středník).
    public var watchSet: Set<String> { Self.parseWatch(watchCalls) }

    public static func parseWatch(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
            .map { String($0).uppercased() }.filter { !$0.isEmpty }.map { baseCall($0) })
    }

    /// Stejná definice jako QSORecord.baseCall (Settings nezávisí na QSOLog).
    static func baseCall(_ call: String) -> String {
        let parts = call.uppercased().split(separator: "/").map(String.init)
        return parts.max { $0.count < $1.count } ?? call.uppercased()
    }

    /// Je zapnuté některé systémové oznámení (vyžádá se oprávnění).
    public var wantsNotifications: Bool { myCallNotification || neededNotification }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "alerts", x = AlertSettings()
        myCallSound = c.tolerant(.myCallSound, x.myCallSound, w, s)
        myCallNotification = c.tolerant(.myCallNotification, x.myCallNotification, w, s)
        let wc = c.tolerant(.watchCalls, x.watchCalls, w, s)
        watchCalls = wc.count <= Self.maxWatchLength ? wc : x.watchCalls
        newCountryBand = c.tolerant(.newCountryBand, x.newCountryBand, w, s)
        newCountryAny = c.tolerant(.newCountryAny, x.newCountryAny, w, s)
        neededSound = c.tolerant(.neededSound, x.neededSound, w, s)
        neededNotification = c.tolerant(.neededNotification, x.neededNotification, w, s)
    }
}
