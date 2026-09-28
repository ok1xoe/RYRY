// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
public enum SerialError: Error, Equatable, Sendable {
    case openFailed(String), unsupportedBaud(Double), ioError(String), closed
}
public protocol SerialPort: AnyObject, Sendable {
    var path: String { get }
    func open() throws
    func close()
    func setRTS(_ on: Bool) throws
    func setDTR(_ on: Bool) throws
    func setBreak(_ on: Bool) throws
    func configure(baud: Double, dataBits: Int, stopBits: Int) throws
    func write(_ bytes: [UInt8]) throws
    func drain() throws
}
public protocol Clock: Sendable {
    func now() -> UInt64
    func sleep(untilNanos: UInt64)
}
