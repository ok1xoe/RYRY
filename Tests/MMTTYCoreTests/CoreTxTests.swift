import Testing
import MMTTYCore
import RTTYSignalKit

/// Generates the TX signal from the core (instance A); it is decoded by an independent instance B.
func transmit(_ text: String, configure: (OpaquePointer) -> Void = { _ in }) throws -> [Float] {
    let tx = try #require(makeCore())
    defer { rttycore_destroy(tx) }
    configure(tx)
    rttycore_tx_begin(tx, 0)
    var remaining = Array(text.utf8CString.dropLast())   // without the trailing 0
    var out: [Float] = []
    var buf = [Float](repeating: 0, count: 1024)
    var stopRequested = false
    for _ in 0..<100_000 {
        if !remaining.isEmpty {
            var tmp = remaining + [0]
            let used = rttycore_queue_tx(tx, &tmp)
            remaining.removeFirst(used)
        } else if !stopRequested && rttycore_tx_pending(tx) == 0 {
            rttycore_tx_stop(tx); stopRequested = true
        }
        let n = rttycore_generate_tx(tx, &buf, buf.count)
        out += buf[0..<n]
        if n < buf.count { break }
    }
    // A pause after the last character (like the PTT tail) so that the receiver finishes the last character.
    return out + [Float](repeating: 0, count: 2000)
}

@Test func loopbackDecodesTransmittedText() throws {
    let text = "CQ CQ DE OK1XOE OK1XOE K\r\n"
    let s = try transmit(text)
    let rx = try #require(makeCore())
    defer { rttycore_destroy(rx) }
    let padded = [Float](repeating: 0, count: 5000) + s + [Float](repeating: 0, count: 5000)
    #expect(decode(rx, padded).contains("CQ CQ DE OK1XOE OK1XOE K"))
}

@Test func figuresAndLettersSwitchCorrectly() throws {
    let text = "RST 599 NR 001 QTH PRAGUE 73"
    let s = try transmit(text)
    let rx = try #require(makeCore())
    defer { rttycore_destroy(rx) }
    #expect(decode(rx, s).contains(text))
}

@Test func transmittedToneIsWithinMarkSpaceBand() throws {
    let all = try transmit("RYRYRYRY")
    // MMTTY starts with ~3×1024 samples of silence (SetCount(m_BuffSize*3)) – we only count the part with the carrier.
    let first = try #require(all.firstIndex { $0 != 0 })
    let last = try #require(all.lastIndex { $0 != 0 })
    #expect(first >= 3000 && first <= 3200)
    let s = Array(all[first...last])
    var crossings = 0
    for i in 1..<s.count where (s[i - 1] < 0) != (s[i] < 0) { crossings += 1 }
    let f = Double(crossings) / 2 / (Double(s.count) / 11025)
    #expect(f > 2100 && f < 2320)
    #expect(s.allSatisfy { abs($0) <= 1.0 })
}

@Test func stopEndsTransmissionAndIsTxClears() throws {
    let tx = try #require(makeCore())
    defer { rttycore_destroy(tx) }
    rttycore_tx_begin(tx, 0)
    #expect(rttycore_is_tx(tx) == 1)
    var buf = [Float](repeating: 0, count: 1024)
    _ = rttycore_generate_tx(tx, &buf, buf.count)
    rttycore_tx_stop(tx)
    var total = 0
    for _ in 0..<100 {
        let n = rttycore_generate_tx(tx, &buf, buf.count)
        total += n
        if n < buf.count { break }
    }
    #expect(rttycore_is_tx(tx) == 0)
    #expect(total < 11025)            // finished within 1 s
}

@Test func abortStopsImmediately() throws {
    let tx = try #require(makeCore())
    defer { rttycore_destroy(tx) }
    rttycore_tx_begin(tx, 0)
    _ = rttycore_queue_tx(tx, "CQ CQ CQ CQ CQ CQ CQ")
    rttycore_tx_abort(tx)
    var buf = [Float](repeating: 1, count: 256)
    #expect(rttycore_generate_tx(tx, &buf, buf.count) == 0)
    #expect(buf.allSatisfy { $0 == 0 })
    #expect(rttycore_tx_pending(tx) == 0)
}

// Review Focus 3
@Test func unsupportedCharactersAreSkippedAndLowercaseUppercased() throws {
    let s = try transmit("cq é@\t😀 de ok1xoe")
    let rx = try #require(makeCore())
    defer { rttycore_destroy(rx) }
    #expect(decode(rx, s).contains("CQ  DE OK1XOE"))
}

@Test func queueReportsBackpressure() throws {
    let tx = try #require(makeCore())
    defer { rttycore_destroy(tx) }
    rttycore_tx_begin(tx, 0)
    let long = String(repeating: "RYRYRYRYRY", count: 500)     // 5000 characters > 2048 codes
    let used = rttycore_queue_tx(tx, long)
    #expect(used > 0 && used < 5000)
    #expect(rttycore_tx_space(tx) < 3)
}
