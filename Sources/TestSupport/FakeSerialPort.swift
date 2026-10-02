// Copyright 2026 OK1XOE (RYRY), LGPL v3
// Test replacements for hardware (they do not touch real devices).
import Foundation
import Keying

public final class FakeSerialPort: SerialPort, @unchecked Sendable {
    public enum Event: Equatable, Sendable {
        case open, close, rts(Bool), dtr(Bool), brk(Bool), configure(baud: Double, dataBits: Int, stopBits: Int)
        case write([UInt8]), drain, flush
    }
    public let path: String
    private let lock = NSLock()
    private var _events: [(UInt64, Event)] = []
    public var clock: (any Clock)?
    public var failOpen = false
    public var failBaud = false
    public var failLines = false
    public private(set) var isOpen = false

    public init(path: String = "/dev/cu.fake") { self.path = path }

    public var events: [Event] { lock.withLock { _events.map(\.1) } }
    public var timedEvents: [(UInt64, Event)] { lock.withLock { _events } }
    public var written: [UInt8] { events.flatMap { if case .write(let b) = $0 { return b } else { return [] } } }
    public func clearEvents() { lock.withLock { _events.removeAll() } }

    private func record(_ e: Event) { let t = clock?.now() ?? 0; lock.withLock { _events.append((t, e)) } }

    public func open() throws { if failOpen { throw SerialError.openFailed(path) }; isOpen = true; record(.open) }
    public func close() { isOpen = false; record(.close) }
    public func setRTS(_ on: Bool) throws { try check(); record(.rts(on)) }
    public func setDTR(_ on: Bool) throws { try check(); record(.dtr(on)) }
    public func setBreak(_ on: Bool) throws { try check(); record(.brk(on)) }
    public func configure(baud: Double, dataBits: Int, stopBits: Int) throws {
        guard isOpen else { throw SerialError.closed }
        if failBaud { throw SerialError.unsupportedBaud(baud) }
        record(.configure(baud: baud, dataBits: dataBits, stopBits: stopBits))
    }
    public func write(_ bytes: [UInt8]) throws { try check(); record(.write(bytes)) }
    public func drain() throws { try check(); record(.drain) }
    public func flushOutput() { record(.flush) }
    private func check() throws {
        guard isOpen else { throw SerialError.closed }
        if failLines { throw SerialError.ioError("simulated") }
    }
}

/// A clock for deterministic tests: sleep(until) only advances the time.
public final class ManualClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var t: UInt64 = 0
    public init() {}
    public func now() -> UInt64 { lock.withLock { t } }
    public func sleep(untilNanos: UInt64) { lock.withLock { if untilNanos > t { t = untilNanos } } }
    public func advance(ms: Double) { lock.withLock { t += UInt64(ms * 1_000_000) } }
}
