import Testing
import MMTTYCore
import RTTYSignalKit

/// Vygeneruje `seconds` TX vzorků a vrátí je + znaky přečtené z RX bufferu téhož jádra.
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

// Review #1: echo=1 dekóduje vlastní TX zvuk (jako MMTTY), RX vstup během TX se ignoruje.
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
    #expect(!decode(core, other).contains("ZZZ"))   // RX vstup během TX se nedekóduje
}

// Review #2: znaky bez Baudot kódu a řídicí znaky MMTTY se z textu nevysílají.
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

// Review #5: tune = čistá nosná mark, bez diddle, text se nepřijímá.
@Test func tuneIsSteadyMarkCarrier() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    rttycore_tx_begin(core, 1)
    #expect(rttycore_queue_tx(core, "RYRY") == 0)
    let s = runTx(core, seconds: 2).samples.drop { $0 == 0 }
    let win = 551                                   // 50 ms okna
    var i = s.startIndex + 2205                     // přeskočit náběh
    while i + win < s.endIndex {
        var c = 0
        for k in (i + 1)..<(i + win) where (s[k - 1] < 0) != (s[k] < 0) { c += 1 }
        let f = Double(c) / 2 / (Double(win) / 11025)
        #expect(abs(f - 2125) < 25, "okno \(i): \(f) Hz")
        i += win
    }
}

/// echo=1: i poslední znak vysílání se musí objevit v echu (demodulátor potřebuje doběh filtrů).
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
