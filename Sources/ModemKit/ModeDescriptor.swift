/// Modem mode (e.g. RTTY-45) including the ADIF designation for the log.
public struct ModeDescriptor: Sendable, Hashable, Codable {
    public let id: String
    public let displayName: String
    public let adifMode: String
    public let adifSubmode: String?

    public init(id: String, displayName: String, adifMode: String, adifSubmode: String? = nil) {
        self.id = id; self.displayName = displayName
        self.adifMode = adifMode; self.adifSubmode = adifSubmode
    }
}
