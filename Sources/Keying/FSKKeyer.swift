// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3

/// FSK klíčovač: dostává kódy v pořadí bitů MMTTY (viz rttycore_read_fsk_codes).
public protocol FSKKeyer: AnyObject, Sendable {
    func start() throws          // linka na mark
    func send(codes: [UInt8])
    var pending: Int { get }     // kódy čekající na odvysílání
    func stop()                  // linka na mark, fronta se zahodí
}

/// FSK přes UART TxD (45,45 Bd přes IOSSIOSPEED; spolehlivé s FTDI).
public final class UARTFSKKeyer: FSKKeyer, @unchecked Sendable {
    private let port: SerialPort
    private let baud: Double
    private let invert: Bool
    public private(set) var lastError: Error?

    public init(port: SerialPort, baud: Double = 45.45, invert: Bool = false) {
        self.port = port; self.baud = baud; self.invert = invert
    }

    /// MMTTY kód → ITA2 (LSB se vysílá první).
    public static func reverse5(_ c: UInt8) -> UInt8 {
        var r: UInt8 = 0
        for b in 0..<5 where c & (1 << b) != 0 { r |= 1 << (4 - b) }
        return r
    }

    public func start() throws {
        if invert {
            throw SerialError.openFailed("invertovaná polarita není u UART FSK možná, použijte fsk-soft")
        }
        do {
            try port.open()
            try port.configure(baud: baud, dataBits: 5, stopBits: 2)
            try port.setBreak(false)
        } catch SerialError.unsupportedBaud(let b) {
            throw SerialError.openFailed("\(port.path) nepodporuje \(b) Bd (typicky CH340/PL2303); použijte fsk-soft nebo adaptér FTDI")
        }
    }

    public func send(codes: [UInt8]) {
        guard !codes.isEmpty else { return }
        do { try port.write(codes.map(Self.reverse5)) } catch { lastError = error }
    }

    public var pending: Int { 0 }   // o časování se stará UART; modulátor dodává kódy v reálném čase

    public func stop() { try? port.setBreak(false) }
}
