// Copyright 2026 OK1XOE (RYRY), LGPL v3

public enum RigError: Error, Equatable, Sendable {
    case offline
    case timeout
    case protocolError(String)
    case rejected(Int)          // rigctld RPRT <n>
}

public struct RigStatus: Sendable, Equatable {
    public var online: Bool
    public var frequency: Double?
    public var mode: String?
    public var ptt: Bool?
    public init(online: Bool, frequency: Double? = nil, mode: String? = nil, ptt: Bool? = nil) {
        self.online = online; self.frequency = frequency; self.mode = mode; self.ptt = ptt
    }
}

/// Transceiver control (hamlib rigctld, flrig, or none).
public protocol Rig: AnyObject, Sendable {
    var name: String { get }
    func connect() async throws
    func disconnect() async
    func frequency() async throws -> Double
    func setFrequency(_ hz: Double) async throws
    func mode() async throws -> String
    func setMode(_ mode: String) async throws
    func setPTT(_ on: Bool) async throws
    /// The connection to the radio is not open (port closed, rigctld not running) – a command would have to open it.
    var isIdle: Bool { get }
}

public extension Rig {
    var isIdle: Bool { false }
}

/// No rig control: everything reports offline.
public final class NoRig: Rig {
    public init() {}
    public var name: String { "none" }
    public func connect() async throws { throw RigError.offline }
    public func disconnect() async {}
    public func frequency() async throws -> Double { throw RigError.offline }
    public func setFrequency(_ hz: Double) async throws { throw RigError.offline }
    public func mode() async throws -> String { throw RigError.offline }
    public func setMode(_ mode: String) async throws { throw RigError.offline }
    public func setPTT(_ on: Bool) async throws { throw RigError.offline }
}
