import Testing
import MMTTYCore
import RTTYSignalKit

func runWithTicks(_ core: OpaquePointer, _ samples: [Float]) -> String {
    var text = ""
    var buf = [RTTYCoreChar](repeating: RTTYCoreChar(), count: 256)
    let block = 1103   // ≈ 100 ms při 11025 Hz
    var i = 0
    while i < samples.count {
        let n = min(block, samples.count - i)
        samples.withUnsafeBufferPointer { p in rttycore_process_rx(core, p.baseAddress! + i, n) }
        _ = rttycore_tick(core)
        i += n
        let got = rttycore_read_chars(core, &buf, buf.count)
        for k in 0..<got { text.unicodeScalars.append(UnicodeScalar(UInt8(bitPattern: buf[k].ch))) }
    }
    return text
}

@Test func spectrumPeaksAtMarkTone() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    let s = RTTYSignalGenerator().generate(codes: [], leadIn: 2.0, tail: 0)   // čistý mark 2125 Hz
    _ = runWithTicks(core, s)
    var spec = [Float](repeating: 0, count: 2048)
    var binHz = 0.0
    let n = rttycore_spectrum(core, &spec, spec.count, &binHz)
    #expect(n > 0 && binHz > 0)
    let peak = spec[0..<n].enumerated().max { $0.element < $1.element }!.offset
    #expect(abs(Double(peak) * binHz - 2125) < 3 * binHz)
}

@Test func afcTracksOffsetSignalAndDecodes() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_get_param(core, RC_AFC) == 1)
    // signál o 60 Hz níž, než je nastaveno (2065/2235 místo 2125/2295)
    let text = String(repeating: "RYRYRYRY CQ TEST DE OK1XOE ", count: 6)
    let s = RTTYSignalGenerator(markHz: 2065).generate(text: text, leadIn: 1.0)
    let out = runWithTicks(core, s)
    let sig = rttycore_signal(core)
    #expect(abs(sig.mark - 2065) < 6)
    #expect(abs(sig.space - 2235) < 6)
    #expect(out.contains("CQ TEST DE OK1XOE"))
}

@Test func afcOffKeepsFrequencies() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_AFC, 0) == RC_OK)
    let s = RTTYSignalGenerator(markHz: 2065).generate(text: "RYRYRYRY", leadIn: 1.0)
    _ = runWithTicks(core, s)
    #expect(rttycore_signal(core).mark == 2125)
}

/// Průměrný kmitočet TX signálu (tune + diddle) po příjmu signálu posunutého o -60 Hz.
func txAverageFrequency(net: Bool) throws -> Double {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_NET, net ? 1 : 0) == RC_OK)
    let s = RTTYSignalGenerator(markHz: 2065).generate(text: String(repeating: "RYRYRYRY ", count: 8))
    _ = runWithTicks(core, s)
    rttycore_tx_begin(core, 1)
    var buf = [Float](repeating: 0, count: 11025)
    _ = rttycore_generate_tx(core, &buf, buf.count)
    var crossings = 0
    for i in 1..<buf.count where (buf[i - 1] < 0) != (buf[i] < 0) { crossings += 1 }
    return Double(crossings) / 2
}

@Test func netMakesTransmitterFollowAFC() throws {
    let on = try txAverageFrequency(net: true)
    let off = try txAverageFrequency(net: false)
    // AFC posunulo RX o ~60 Hz dolů; s NET musí vysílač jít s ním, bez NET zůstat.
    #expect(abs((off - on) - 60) < 10)
}

@Test func bpfAndLmsDoNotBreakCleanDecoding() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_RX_BPF, 1) == RC_OK)
    #expect(rttycore_set_param(core, RC_RX_LMS, 1) == RC_OK)
    let s = RTTYSignalGenerator().generate(text: sample)
    #expect(runWithTicks(core, s).contains("CQ CQ DE OK1XOE"))
}
