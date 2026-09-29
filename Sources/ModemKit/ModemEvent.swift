public struct ModemCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let fskKeying    = ModemCapabilities(rawValue: 1 << 0)
    public static let afc          = ModemCapabilities(rawValue: 1 << 1)
    public static let multiChannel = ModemCapabilities(rawValue: 1 << 2)
    public static let imageOutput  = ModemCapabilities(rawValue: 1 << 3)
    public static let textOutput   = ModemCapabilities(rawValue: 1 << 4)
}

public struct SpectrumFrame: Sendable {
    public let binHz: Double
    public let magnitudes: [Float]
    public init(binHz: Double, magnitudes: [Float]) { self.binHz = binHz; self.magnitudes = magnitudes }
}

public struct TuningInfo: Sendable, Equatable {
    public let mark: Double
    public let space: Double
    public init(mark: Double, space: Double) { self.mark = mark; self.space = space }
}

public enum ModemEvent: Sendable, Equatable {
    case rxText(Character, echo: Bool)
    case signal(level: Double, squelchOpen: Bool)
    case tuning(TuningInfo)
    case shift(fig: Bool)
    case overflow
    case txFinished
}

public enum TxStatus: Sendable, Equatable { case active, finished }

/// Bod XY scope (mark, space), přibližně ±1.
public struct XYPoint: Sendable, Equatable {
    public let x: Float, y: Float
    public init(x: Float, y: Float) { self.x = x; self.y = y }
}
