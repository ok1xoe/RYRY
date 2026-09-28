// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

public enum FSKLine: String, Sendable, Codable, CaseIterable { case txdBreak, dtr, rts }

/// Softwarově časované FSK na TxD (break), DTR nebo RTS – náhrada EXTFSK.
/// Aktivní linka = space, klidová = mark (invert prohodí). Časy se počítají absolutně
/// od začátku znaku, takže se chyba nekumuluje.
public final class SoftFSKKeyer: FSKKeyer, @unchecked Sendable {
    private let port: SerialPort
    private let line: FSKLine
    private let bitNs: Double
    private let stopBits: Double
    private let invert: Bool
    private let clock: Clock
    private let cond = NSCondition()
    private var queue: [UInt8] = []
    private var sending = 0
    private var running = false
    private var generation = 0
    private var thread: Thread?
    public private(set) var lastError: Error?

    public init(port: SerialPort, line: FSKLine, baud: Double = 45.45, stopBits: Double = 1.5,
                invert: Bool = false, clock: Clock = HostClock()) {
        self.port = port; self.line = line; self.bitNs = 1e9 / baud
        self.stopBits = stopBits; self.invert = invert; self.clock = clock
    }

    private func setLevel(mark: Bool) {
        let active = mark == invert          // space = aktivní (bez invert)
        do {
            switch line {
            case .txdBreak: try port.setBreak(active)
            case .dtr: try port.setDTR(active)
            case .rts: try port.setRTS(active)
            }
        } catch { lastError = error }
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
        cond.unlock()
        let t = Thread { [weak self] in self?.run(gen) }
        t.qualityOfService = .userInteractive
        t.name = "SoftFSKKeyer"
        thread = t
        t.start()
    }

    public func send(codes: [UInt8]) {
        cond.lock()
        queue += codes
        cond.signal()
        cond.unlock()
    }

    public var pending: Int {
        cond.lock(); defer { cond.unlock() }
        return queue.count + sending
    }

    public func stop() {
        cond.lock()
        running = false
        queue.removeAll()
        sending = 0
        generation += 1
        cond.broadcast()
        cond.unlock()
        // vlákno při ukončení nastaví mark; pro jistotu i zde
        setLevel(mark: true)
    }

    /// Real-time priorita vlákna (best effort) – přesnost hran v řádu desítek µs.
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
            while queue.isEmpty && running && generation == gen { cond.wait() }
            guard running, generation == gen else { cond.unlock(); break }
            let code = queue.removeFirst()
            sending = 1
            cond.unlock()

            let now = clock.now()
            let t0 = max(now, nextStart)          // navazující znak bez mezery
            let ita2 = UARTFSKKeyer.reverse5(code)
            var levels: [Bool] = [false]          // start = space
            for b in 0..<5 { levels.append(ita2 & (1 << b) != 0) }
            var last: Bool? = nil
            var aborted = false
            for (i, mark) in levels.enumerated() {
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
