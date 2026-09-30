// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

public enum FSKLine: String, Sendable, Codable, CaseIterable { case txdBreak, dtr, rts }

/// Software-timed FSK on TxD (break), DTR or RTS – a replacement for EXTFSK.
/// An active line = space, an idle one = mark (invert swaps them). The times are computed absolutely
/// from the start of the character, so the error does not accumulate.
public final class SoftFSKKeyer: FSKKeyer, @unchecked Sendable {
    private let port: SerialPort
    private let line: FSKLine
    private let bitNs: Double
    private let stopBits: Double
    private let invert: Bool
    private let clock: Clock
    private let cond = NSCondition()
    private var queue: [UInt8] = []
    private var head = 0                     // read index (no removeFirst in the real-time loop)
    private var sending = 0
    private var running = false
    private var generation = 0
    private var thread: Thread?
    private var exited: DispatchSemaphore?
    private var _lastError: Error?
    /// The last error while writing to the line (read by the Engine; written by the keyer thread).
    public var lastError: Error? { cond.lock(); defer { cond.unlock() }; return _lastError }

    public init(port: SerialPort, line: FSKLine, baud: Double = 45.45, stopBits: Double = 1.5,
                invert: Bool = false, clock: Clock = HostClock()) {
        self.port = port; self.line = line; self.bitNs = 1e9 / baud
        self.stopBits = stopBits; self.invert = invert; self.clock = clock
    }

    private func setLevel(mark: Bool) {
        let active = mark == invert          // space = active (without invert)
        do {
            switch line {
            case .txdBreak: try port.setBreak(active)
            case .dtr: try port.setDTR(active)
            case .rts: try port.setRTS(active)
            }
        } catch { cond.lock(); _lastError = error; cond.unlock() }
    }

    public func start() throws {
        try port.open()
        setLevel(mark: true)
        if let e = lastError { throw e }
        cond.lock()
        if running { cond.unlock(); return }
        running = true
        generation += 1
        let gen = generation
        let done = DispatchSemaphore(value: 0)
        exited = done
        cond.unlock()
        let t = Thread { [weak self] in self?.run(gen); done.signal() }
        t.qualityOfService = .userInteractive
        t.name = "SoftFSKKeyer"
        thread = t
        t.start()
    }

    public func send(codes: [UInt8]) {
        cond.lock()
        if head > 0 && head * 2 >= queue.count { queue.removeFirst(head); head = 0 }   // cleanup outside the RT thread
        queue += codes
        cond.signal()
        cond.unlock()
    }

    public var pending: Int {
        cond.lock(); defer { cond.unlock() }
        return queue.count - head + sending
    }

    public func finish(timeout: Duration) async {
        let deadline = ContinuousClock.now + timeout
        while pending > 0 && ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    public func stop() {
        cond.lock()
        running = false
        queue.removeAll(); head = 0
        sending = 0
        generation += 1
        let done = exited
        exited = nil
        cond.broadcast()
        cond.unlock()
        // wait for the thread (at most ~1 bit) so that it no longer touches the line after stop()
        _ = done?.wait(timeout: .now() + .milliseconds(200))
        setLevel(mark: true)
    }

    /// Real-time thread priority (best effort) – edge accuracy in the order of tens of µs.
    private static func makeRealtime() {
        var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
        func abs(_ ns: Double) -> UInt32 { UInt32(ns * Double(tb.denom) / Double(tb.numer)) }
        var policy = thread_time_constraint_policy_data_t(
            period: abs(22_000_000), computation: abs(500_000), constraint: abs(2_000_000), preemptible: 1)
        let count = mach_msg_type_number_t(MemoryLayout<thread_time_constraint_policy_data_t>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &policy) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_policy_set(pthread_mach_thread_np(pthread_self()),
                                  thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY), $0, count)
            }
        }
    }

    private func run(_ gen: Int) {
        if clock is HostClock { Self.makeRealtime() }
        var nextStart: UInt64 = 0
        while true {
            cond.lock()
            while head >= queue.count && running && generation == gen { cond.wait() }
            guard running, generation == gen else { cond.unlock(); break }
            let code = queue[head]; head += 1
            sending = 1
            cond.unlock()

            let now = clock.now()
            let t0 = max(now, nextStart)          // a following character with no gap
            let ita2 = UARTFSKKeyer.reverse5(code)
            var last: Bool? = nil
            var aborted = false
            for i in 0..<6 {                      // start (space) + 5 data bits, no allocations
                let mark = i == 0 ? false : (ita2 & (1 << (i - 1)) != 0)
                clock.sleep(untilNanos: t0 + UInt64((Double(i) * bitNs).rounded()))
                if isAborted(gen) { aborted = true; break }
                if mark != last { setLevel(mark: mark); last = mark }
            }
            if aborted { break }
            clock.sleep(untilNanos: t0 + UInt64((6 * bitNs).rounded()))
            if last != true { setLevel(mark: true) }
            nextStart = t0 + UInt64(((6 + stopBits) * bitNs).rounded())
            clock.sleep(untilNanos: nextStart)

            cond.lock(); if generation == gen { sending = 0 }; cond.unlock()
        }
        setLevel(mark: true)
    }

    private func isAborted(_ gen: Int) -> Bool {
        cond.lock(); defer { cond.unlock() }
        return !running || generation != gen
    }
}
