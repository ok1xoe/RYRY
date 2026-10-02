// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation

/// Uploading QSOs to LoTW (TQSL), eQSL and Club Log. Passwords and the API key are in the Keychain, not here.
public struct UploadSettings: Codable, Sendable, Equatable {
    /// LoTW via TrustedQSL: RYRY prepares the ADIF, the user signs and sends it in TQSL (never automatic).
    public var lotwEnabled = false
    public var eqslEnabled = false
    public var eqslUser = ""
    public var eqslAuto = false
    public var clublogEnabled = false
    public var clublogEmail = ""
    public var clublogAuto = false

    enum CodingKeys: String, CodingKey {
        case lotwEnabled, eqslEnabled, eqslUser, eqslAuto,
             clublogEnabled, clublogEmail, clublogAuto
    }
    public init() {}
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self), w = d.warningSink, s = "upload", x = UploadSettings()
        lotwEnabled = c.tolerant(.lotwEnabled, x.lotwEnabled, w, s)
        eqslEnabled = c.tolerant(.eqslEnabled, x.eqslEnabled, w, s); eqslUser = c.tolerant(.eqslUser, x.eqslUser, w, s)
        eqslAuto = c.tolerant(.eqslAuto, x.eqslAuto, w, s)
        clublogEnabled = c.tolerant(.clublogEnabled, x.clublogEnabled, w, s); clublogEmail = c.tolerant(.clublogEmail, x.clublogEmail, w, s)
        clublogAuto = c.tolerant(.clublogAuto, x.clublogAuto, w, s)
    }
}
