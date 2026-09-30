// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Alerts: somebody is calling my call, watched calls and needed countries (in reception and in spots).
public struct AlertSettings: Codable, Sendable, Equatable {
    /// My call appeared in the received text: sound / system notification (only when the app is not active).
    public var myCallSound = true
    public var myCallNotification = false
    /// Watched calls, one per line (the base call without /P etc. is compared).
    public var watchCalls = ""
    /// A country that is not in the log on the current band yet / that is not in the log at all.
    public var newCountryBand = false
    public var newCountryAny = false
    /// Alerts for needed calls and countries by sound / system notification (the line in the status bar is always there).
    public var neededSound = true
    public var neededNotification = false
    public init() {}

    public static let maxWatchLength = 20_000

    enum CodingKeys: String, CodingKey {
        case myCallSound, myCallNotification, watchCalls, newCountryBand, newCountryAny, neededSound, neededNotification
    }

    /// Watched calls as a set of base calls (upper case; separator: line, comma, space, semicolon).
    public var watchSet: Set<String> { Self.parseWatch(watchCalls) }

    public static func parseWatch(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" })
            .map { String($0).uppercased() }.filter { !$0.isEmpty }.map { baseCall($0) })
    }

    /// The same definition as QSORecord.baseCall (Settings does not depend on QSOLog).
    static func baseCall(_ call: String) -> String {
        let parts = call.uppercased().split(separator: "/").map(String.init)
        return parts.max { $0.count < $1.count } ?? call.uppercased()
    }

    /// Is any system notification enabled (permission will be requested).
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
