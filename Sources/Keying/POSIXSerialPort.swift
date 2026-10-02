// Copyright 2026 OK1XOE (RYRY), LGPL v3
import CSerial
import Foundation

/// A real serial port (termios + IOSSIOSPEED). Calls are serialized by an internal lock.
public final class POSIXSerialPort: SerialPort, @unchecked Sendable {
    public let path: String
    private var fd: Int32 = -1
    private let lock = NSLock()

    public init(path: String) { self.path = path }
    deinit { if fd >= 0 { _ = cserial_close(fd) } }

    private func err(_ code: Int32) -> String { String(cString: strerror(code)) }

    public func open() throws {
        try lock.withLock {
            if fd >= 0 { return }
            var f: Int32 = -1
            let e = cserial_open(path, &f)
            if e != 0 { throw SerialError.openFailed("\(path): \(err(e))") }
            fd = f
            let c = cserial_configure(fd, 8, 1)
            if c != 0 { throw SerialError.ioError("configure: \(err(c))") }
        }
    }

    public func close() {
        lock.withLock { if fd >= 0 { _ = cserial_close(fd); fd = -1 } }
    }

    private func op(_ name: String, _ body: (Int32) -> Int32) throws {
        try lock.withLock {
            guard fd >= 0 else { throw SerialError.closed }
            let e = body(fd)
            if e != 0 {
                // disconnected device (USB): close the fd, the next open() reopens the port
                if e == ENXIO || e == EIO || e == ENODEV || e == EBADF {
                    _ = cserial_close(fd); fd = -1
                }
                throw SerialError.ioError("\(name): \(err(e))")
            }
        }
    }

    public func setRTS(_ on: Bool) throws { try op("RTS") { cserial_set_rts($0, on ? 1 : 0) } }
    public func setDTR(_ on: Bool) throws { try op("DTR") { cserial_set_dtr($0, on ? 1 : 0) } }
    public func setBreak(_ on: Bool) throws { try op("break") { cserial_set_break($0, on ? 1 : 0) } }

    public func configure(baud: Double, dataBits: Int, stopBits: Int) throws {
        try op("configure") { cserial_configure($0, Int32(dataBits), Int32(stopBits)) }
        do {
            try op("speed") { cserial_set_speed($0, UInt(baud.rounded())) }
        } catch {
            throw SerialError.unsupportedBaud(baud)
        }
    }

    public func write(_ bytes: [UInt8]) throws {
        try op("write") { fd in bytes.withUnsafeBufferPointer { cserial_write(fd, $0.baseAddress, UInt($0.count)) } }
    }

    public func drain() throws { try op("drain") { cserial_drain($0) } }
    public func flushOutput() { try? op("flush") { cserial_flush_output($0) } }

    /// Serial devices (/dev/cu.*).
    public static func availablePorts() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return items.filter { $0.hasPrefix("cu.") }.sorted().map { "/dev/" + $0 }
    }
}

/// System clock (mach_absolute_time / mach_wait_until) in nanoseconds.
public struct HostClock: Clock {
    private static let timebase: mach_timebase_info_data_t = {
        var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb); return tb
    }()
    public init() {}
    public func now() -> UInt64 {
        mach_absolute_time() * UInt64(Self.timebase.numer) / UInt64(Self.timebase.denom)
    }
    public func sleep(untilNanos: UInt64) {
        let ticks = untilNanos * UInt64(Self.timebase.denom) / UInt64(Self.timebase.numer)
        mach_wait_until(ticks)
    }
}
