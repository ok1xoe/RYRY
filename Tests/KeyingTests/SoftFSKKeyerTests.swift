import Foundation
import Testing
import TestSupport
@testable import Keying

func waitIdle(_ k: FSKKeyer) {
    let deadline = Date().addingTimeInterval(2)
    while k.pending > 0 && Date() < deadline { usleep(1000) }
    usleep(5000)
}

@Test func softKeyerTimingForY() throws {
    let clock = ManualClock()
    let port = FakeSerialPort(); port.clock = clock
    let k = SoftFSKKeyer(port: port, line: .dtr, clock: clock)
    try k.start()
    port.clearEvents()
    let t0 = clock.now()
    k.send(codes: [0x15])              // Y (MMTTY) → ITA2 10101
    waitIdle(k)
    k.stop()
    let bit = 1e9 / 45.45
    let ev = port.timedEvents.filter { if case .dtr = $0.1 { return true } else { return false } }
    let want: [(Double, Bool)] = [(0, true), (1, false), (2, true), (3, false), (4, true), (5, false)]
    #expect(ev.count >= want.count)
    for (i, w) in want.enumerated() where i < ev.count {
        #expect(ev[i].1 == .dtr(w.1), "přechod \(i)")
        let dt = Double(ev[i].0 - t0) - w.0 * bit
        #expect(abs(dt) < 1000, "přechod \(i) posun \(dt) ns")
    }
    // znak trvá 7,5 bitu: další znak by začal až po stop bitu
    #expect(clock.now() - t0 >= UInt64(7.5 * bit) - 1000)
}

@Test func invertSwapsLevels() throws {
    let clock = ManualClock()
    let port = FakeSerialPort(); port.clock = clock
    let k = SoftFSKKeyer(port: port, line: .rts, invert: true, clock: clock)
    try k.start()
    #expect(port.events.last == .rts(true))          // mark = sepnuto při invert
    port.clearEvents()
    k.send(codes: [0x1F])                            // LTRS = samé mark → jen start bit space
    waitIdle(k)
    #expect(port.events.first == .rts(false))
    k.stop()
}

@Test func breakLineAndStopReturnsToMark() throws {
    let clock = ManualClock()
    let port = FakeSerialPort(); port.clock = clock
    let k = SoftFSKKeyer(port: port, line: .txdBreak, clock: clock)
    try k.start()
    k.send(codes: [0x00, 0x00])
    waitIdle(k)
    k.stop()
    #expect(port.events.contains(.brk(true)))
    #expect(port.events.last == .brk(false))
    #expect(k.pending == 0)
}

@Test func pendingCountsQueuedCodes() throws {
    let port = FakeSerialPort()
    let k = SoftFSKKeyer(port: port, line: .dtr)   // skutečné hodiny: 3 znaky ≈ 0,5 s
    try k.start()
    k.send(codes: [0x1F, 0x1F, 0x1F])
    #expect(k.pending >= 2)
    k.stop()
    #expect(k.pending == 0)
}

/// Review: po stop() už vlákno nesmí sáhnout na linku a linka musí zůstat na mark.
@Test func stopJoinsThreadAndLeavesMark() throws {
    for _ in 0..<5 {
        let port = FakeSerialPort()
        let k = SoftFSKKeyer(port: port, line: .dtr)          // skutečné hodiny
        try k.start()
        k.send(codes: [0x00, 0x00, 0x00, 0x00])               // samé space bity
        usleep(40_000)                                        // uprostřed znaku
        k.stop()
        let n = port.events.count
        #expect(port.events.last == .dtr(false))
        usleep(80_000)
        #expect(port.events.count == n, "vlákno sáhlo na linku po stop()")
    }
}
