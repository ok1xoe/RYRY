import Testing
import MMTTYCore
import RTTYSignalKit

/// Generates `seconds` of TX samples and returns them plus the characters read from the RX buffer of the same core.
func runTx(_ core: OpaquePointer, seconds: Double) -> (samples: [Float], chars: [RTTYCoreChar]) {
    var out: [Float] = [], chars: [RTTYCoreChar] = []
    var buf = [Float](repeating: 0, count: 1024)
    var cb = [RTTYCoreChar](repeating: RTTYCoreChar(), count: 256)
    for _ in 0..<Int(seconds * 11025 / 1024) {
        _ = rttycore_generate_tx(core, &buf, buf.count)
        out += buf
        let n = rttycore_read_chars(core, &cb, cb.count)
        chars += cb[0..<n]
    }
    return (out, chars)
}

func text(_ cs: [RTTYCoreChar]) -> String {
    var s = ""; for c in cs { s.unicodeScalars.append(UnicodeScalar(UInt8(bitPattern: c.ch))) }; return s
}

// Review #1: echo=1 decodes our own TX audio (as MMTTY does), the RX input is ignored during TX.
@Test func echoOneDecodesOwnTransmission() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_get_param(core, RC_ECHO) == 1)
    rttycore_tx_begin(core, 0)
    _ = rttycore_queue_tx(core, "CQ TEST DE OK1XOE ")
    let r = runTx(core, seconds: 6)
    #expect(text(r.chars).contains("CQ TEST DE OK1XOE"))
    #expect(r.chars.allSatisfy { $0.echo == 1 })
}

@Test func rxInputIsIgnoredDuringTxWithEchoOne() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    rttycore_tx_begin(core, 0)
    let other = RTTYSignalGenerator().generate(text: "ZZZZZZZZZZ")
    #expect(!decode(core, other).contains("ZZZ"))   // the RX input is not decoded during TX
}

// Review #2: characters with no Baudot code and the MMTTY control characters are not transmitted from the text.
@Test func unsupportedAndControlCharactersAreNotQueued() throws {
    func pending(_ s: String) throws -> Int {
        let core = try #require(makeCore())
        defer { rttycore_destroy(core) }
        rttycore_tx_begin(core, 0)
        _ = rttycore_queue_tx(core, s)
        return rttycore_tx_pending(core)
    }
    let base = try pending("AB")
    for junk in ["@", "#", "%", "*", "+", "<", "=", ">", "\\", "^", "`", "{", "|", "}", "_", "~", "[", "]"] {
        #expect(try pending("A\(junk)B") == base, "\(junk)")
    }
}

@Test func rawQueueAcceptsControlCodes() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    rttycore_tx_begin(core, 0)
    var codes: [UInt8] = [0xFD, 0x1F, 0xFC]
    #expect(rttycore_queue_tx_raw(core, &codes, codes.count) == 3)
    #expect(rttycore_tx_pending(core) == 3)
}

// Review #5: tune = a clean mark carrier, no diddle, no text is received.
@Test func tuneIsSteadyMarkCarrier() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    rttycore_tx_begin(core, 1)
    #expect(rttycore_queue_tx(core, "RYRY") == 0)
    let s = runTx(core, seconds: 2).samples.drop { $0 == 0 }
    let win = 551                                   // 50 ms windows
    var i = s.startIndex + 2205                     // skip the ramp-up
    while i + win < s.endIndex {
        var c = 0
        for k in (i + 1)..<(i + win) where (s[k - 1] < 0) != (s[k] < 0) { c += 1 }
        let f = Double(c) / 2 / (Double(win) / 11025)
        #expect(abs(f - 2125) < 25, "okno \(i): \(f) Hz")
        i += win
    }
}

/// echo=1: even the last transmitted character must show up in the echo (the demodulator needs the filters to settle).
@Test func echoIncludesLastCharacter() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    rttycore_tx_begin(core, 0)
    _ = rttycore_queue_tx(core, "CQ DE OK1XOE K")
    var buf = [Float](repeating: 0, count: 1024)
    var cb = [RTTYCoreChar](repeating: RTTYCoreChar(), count: 256)
    var echo: [RTTYCoreChar] = []
    var stopped = false
    for _ in 0..<500 {
        if !stopped && rttycore_tx_pending(core) == 0 { rttycore_tx_stop(core); stopped = true }
        let n = rttycore_generate_tx(core, &buf, buf.count)
        let k = rttycore_read_chars(core, &cb, cb.count); echo += cb[0..<k]
        if n < buf.count { break }
    }
    #expect(text(echo).contains("CQ DE OK1XOE K"))
}
