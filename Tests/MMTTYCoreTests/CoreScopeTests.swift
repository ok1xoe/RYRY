import Testing
import MMTTYCore
import RTTYSignalKit

/// Plan 8 / T3: the demodulator scope (MMTTY TTScope, CFSKDEM m_ScopeMark/Space/Sync/Bit).
@Test(arguments: [0, 1, 2, 3])   // IIR, FIR, PLL, FFT
func scopeCollectsBatchWithBitsAndSync(demod: Int) throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_DEMOD_TYPE, Double(demod)) == RC_OK)
    let n = 8192
    var m = [Float](repeating: 0, count: n), s = m, b = m, y = m
    // nothing until it is turned on
    _ = decode(core, RTTYSignalGenerator().generate(text: "RYRY"))
    #expect(rttycore_read_scope(core, 2, &m, &s, &b, &y, n) == 0)
    #expect(rttycore_scope_ready(core) == 0)
    rttycore_set_scope(core, 1)
    _ = decode(core, RTTYSignalGenerator().generate(text: String(repeating: "RYRYRYRY ", count: 12)))
    #expect(rttycore_scope_ready(core) == 1)
    // all the sources of the same batch (except ATC when ATC is off) – reading does not clear the batch
    for src: Int32 in [0, 1, 2] where !(src == 1 && demod != 2) {
        #expect(rttycore_read_scope(core, src, &m, &s, &b, &y, n) == n, "zdroj \(src)")
    }
    let got = rttycore_read_scope(core, 2, &m, &s, &b, &y, n)
    #expect(got == n)
    #expect(b.contains(1) && b.contains(0))                       // bit: both mark and space
    #expect(y.contains { $0 < -0.4 })                              // the start bits (−8192/8192)
    #expect(m.contains { $0 > 0 } && s.contains { $0 > 0 })        // the LPF outputs
    // after rearm the next batch is being collected – it is not there yet
    rttycore_scope_rearm(core)
    #expect(rttycore_scope_ready(core) == 0)
    #expect(rttycore_read_scope(core, 2, &m, &s, &b, &y, n) == 0)
    #expect(rttycore_read_scope(core, 7, &m, &s, &b, &y, n) == 0)  // an invalid source
}
