// Copyright 2026 OK1XOE (RYRY), LGPL v3

/// FSK keyer: receives codes in MMTTY bit order (see rttycore_read_fsk_codes).
public protocol FSKKeyer: AnyObject, Sendable {
    func start() throws          // line to mark
    func send(codes: [UInt8])
    var pending: Int { get }     // codes waiting to be transmitted
    func stop()                  // line to mark, the queue is discarded
    /// Waits until everything has been transmitted (UART: tcdrain; soft: empty queue), at most `timeout`.
    func finish(timeout: Duration) async
}

/// FSK via UART TxD (45.45 Bd through IOSSIOSPEED; reliable with FTDI).
public final class UARTFSKKeyer: FSKKeyer, @unchecked Sendable {
    private let port: SerialPort
    private let baud: Double
    private let invert: Bool
    public private(set) var lastError: Error?

    public init(port: SerialPort, baud: Double = 45.45, invert: Bool = false) {
        self.port = port; self.baud = baud; self.invert = invert
    }

    /// MMTTY code → ITA2 (the LSB is transmitted first).
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

    public var pending: Int { 0 }   // the UART handles the timing; the modulator supplies codes in real time

    public func stop() {
        port.flushOutput()           // discard the characters not yet transmitted
        try? port.setBreak(false)
    }

    public func finish(timeout: Duration) async {
        let p = port
        await withTaskGroup(of: Void.self) { g in
            g.addTask { await Task.detached { try? p.drain() }.value }
            g.addTask { try? await Task.sleep(for: timeout) }
            await g.next(); g.cancelAll()
        }
    }
}
