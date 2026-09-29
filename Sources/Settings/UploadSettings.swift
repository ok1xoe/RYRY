// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Nahrávání spojení na LoTW (TQSL), eQSL a Club Log. Hesla a API klíč jsou v Klíčence, ne tady.
public struct UploadSettings: Codable, Sendable, Equatable {
    public var lotwEnabled = false
    public var lotwLocation = ""            // název Station Location v TQSL
    public var lotwTqslPath = ""            // prázdné = autodetekce
    public var lotwAuto = false
    public var eqslEnabled = false
    public var eqslUser = ""
    public var eqslAuto = false
    public var clublogEnabled = false
    public var clublogEmail = ""
    public var clublogAuto = false

    enum CodingKeys: String, CodingKey {
        case lotwEnabled, lotwLocation, lotwTqslPath, lotwAuto, eqslEnabled, eqslUser, eqslAuto,
             clublogEnabled, clublogEmail, clublogAuto
    }
    public init() {}
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "upload", x = UploadSettings()
        lotwEnabled = c.tolerant(.lotwEnabled, x.lotwEnabled, w, s); lotwLocation = c.tolerant(.lotwLocation, x.lotwLocation, w, s)
        lotwTqslPath = c.tolerant(.lotwTqslPath, x.lotwTqslPath, w, s); lotwAuto = c.tolerant(.lotwAuto, x.lotwAuto, w, s)
        eqslEnabled = c.tolerant(.eqslEnabled, x.eqslEnabled, w, s); eqslUser = c.tolerant(.eqslUser, x.eqslUser, w, s)
        eqslAuto = c.tolerant(.eqslAuto, x.eqslAuto, w, s)
        clublogEnabled = c.tolerant(.clublogEnabled, x.clublogEnabled, w, s); clublogEmail = c.tolerant(.clublogEmail, x.clublogEmail, w, s)
        clublogAuto = c.tolerant(.clublogAuto, x.clublogAuto, w, s)
    }
}
