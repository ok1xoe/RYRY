import Testing
import MMTTYCore
import RTTYSignalKit

/// Plán 8 / T3: scope demodulátoru (MMTTY TTScope, CFSKDEM m_ScopeMark/Space/Sync/Bit).
@Test(arguments: [0, 1, 2, 3])   // IIR, FIR, PLL, FFT
func scopeCollectsBatchWithBitsAndSync(demod: Int) throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_DEMOD_TYPE, Double(demod)) == RC_OK)
    let n = 8192
    var m = [Float](repeating: 0, count: n), s = m, b = m, y = m
    // bez zapnutí nic
    _ = decode(core, RTTYSignalGenerator().generate(text: "RYRY"))
    #expect(rttycore_read_scope(core, 2, &m, &s, &b, &y, n) == 0)
    rttycore_set_scope(core, 1)
    _ = decode(core, RTTYSignalGenerator().generate(text: String(repeating: "RYRYRYRY ", count: 12)))
    let got = rttycore_read_scope(core, 2, &m, &s, &b, &y, n)
    #expect(got == n)
    #expect(b.contains(1) && b.contains(0))                       // bit: mark i space
    #expect(y.contains { $0 < -0.4 })                              // start bity (−8192/8192)
    #expect(m.contains { $0 > 0 } && s.contains { $0 > 0 })        // LPF výstupy
    // další dávka se sbírá znovu – hned po přečtení ještě není
    #expect(rttycore_read_scope(core, 2, &m, &s, &b, &y, n) == 0)
    #expect(rttycore_read_scope(core, 7, &m, &s, &b, &y, n) == 0)  // neplatný zdroj
}
