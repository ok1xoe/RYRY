import Testing
import Foundation
import MMTTYCore
import RTTYSignalKit

/// Plan 7 / T1: the AA6YQ and notch/LMS filters, the PLL and TX parameters.

private let filterText = "CQ CQ DE OK1XOE OK1XOE PSE K\r\n599 001 TU 73 DE OK1XOE\r\n"

/// An RTTY signal (2125/2295 Hz) plus a strong interfering carrier tone.
private func jammed(toneHz: Double, toneAmp: Float) -> [Float] {
    var s = RTTYSignalGenerator(amplitude: 0.2).generate(text: filterText)
    for i in s.indices { s[i] += toneAmp * Float(sin(2 * Double.pi * toneHz * Double(i) / 11025)) }
    return s
}

private func errors(_ got: String, _ want: String) -> Int {
    let g = Array(got), w = Array(want)
    var e = abs(g.count - w.count)
    for i in 0..<min(g.count, w.count) where g[i] != w[i] { e += 1 }
    return e
}

@Test func aa6yqFilterDecodesCleanSignal() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_AA6YQ, 1) == RC_OK)
    #expect(rttycore_get_param(core, RC_AA6YQ) == 1)
    #expect(decode(core, RTTYSignalGenerator().generate(text: filterText)) == filterText)
}

@Test func aa6yqRemovesCarrierBetweenMarkAndSpace() throws {
    let s = jammed(toneHz: 2210, toneAmp: 1.2)
    let plain = try #require(makeCore()), filtered = try #require(makeCore())
    defer { rttycore_destroy(plain); rttycore_destroy(filtered) }
    #expect(rttycore_set_param(filtered, RC_AA6YQ, 1) == RC_OK)
    let ePlain = errors(decode(plain, s), filterText), eFilt = errors(decode(filtered, s), filterText)
    #expect(ePlain > 10, "bez filtru chyb: \(ePlain)")
    #expect(eFilt <= 2, "s AA6YQ chyb: \(eFilt)")
}

@Test func notchRemovesInterferingCarrier() throws {
    let s = jammed(toneHz: 1950, toneAmp: 3.0)
    let plain = try #require(makeCore()), notched = try #require(makeCore())
    defer { rttycore_destroy(plain); rttycore_destroy(notched) }
    #expect(rttycore_set_param(notched, RC_LMS_TYPE, 1) == RC_OK)
    #expect(rttycore_set_param(notched, RC_NOTCH_FREQ, 1950) == RC_OK)
    #expect(rttycore_set_param(notched, RC_RX_LMS, 1) == RC_OK)
    let ePlain = errors(decode(plain, s), filterText), eNotch = errors(decode(notched, s), filterText)
    #expect(ePlain > 10, "bez notch chyb: \(ePlain)")
    #expect(eNotch <= 2, "s notch chyb: \(eNotch)")
}

/// MMTTY TMmttyWd::PBoxFFTINMouseDown (right button, notch type).
@Test func notchClickFollowsMMTTY() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_LMS_TYPE, 1) == RC_OK)
    rttycore_notch_click(core, 1800.4)
    #expect(rttycore_get_param(core, RC_RX_LMS) == 1)
    #expect(rttycore_get_param(core, RC_NOTCH_FREQ) == 1800)
    #expect(rttycore_get_param(core, RC_NOTCH2_FREQ) == 0)
    rttycore_notch_click(core, 2500)
    #expect(rttycore_get_param(core, RC_NOTCH_FREQ) == 2500)
    #expect(rttycore_get_param(core, RC_NOTCH2_FREQ) == 1800)
    // LMS type: the click changes nothing
    #expect(rttycore_set_param(core, RC_LMS_TYPE, 0) == RC_OK)
    rttycore_notch_click(core, 1000)
    #expect(rttycore_get_param(core, RC_NOTCH_FREQ) == 2500)
}

@Test func newParametersRoundTripAndValidate() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    let ok: [(RTTYCoreParam, Double)] = [
        (RC_AA6YQ_BPF_TAPS, 256), (RC_AA6YQ_BPF_FW, 50), (RC_AA6YQ_BEF_TAPS, 128), (RC_AA6YQ_BEF_FW, 20),
        (RC_TWO_NOTCH, 1), (RC_NOTCH_TAPS, 128), (RC_LMS_TAPS, 64), (RC_LMS_MU2, 0.002),
        (RC_LMS_GAMMA, 0.999), (RC_LMS_DELAY, 1), (RC_LMS_AGC, 1), (RC_LMS_INV, 1), (RC_LMS_BPF, 0),
        (RC_PLL_VCO_GAIN, 2.5), (RC_PLL_LOOP_ORDER, 3), (RC_PLL_LOOP_FC, 200), (RC_PLL_OUT_ORDER, 5), (RC_PLL_OUT_FC, 150),
        (RC_TX_BPF, 0), (RC_TX_LPF, 1), (RC_TX_LPF_FREQ, 80), (RC_TX_CHAR_WAIT, 20),
        (RC_TX_CHAR_WAIT_DIDDLE, 1), (RC_TX_RANDOM_DIDDLE, 1),
    ]
    for (p, v) in ok {
        #expect(rttycore_set_param(core, p, v) == RC_OK, "\(p)")
        #expect(abs(rttycore_get_param(core, p) - v) < 1e-9, "\(p)")
    }
    let bad: [(RTTYCoreParam, Double)] = [
        (RC_AA6YQ, 2), (RC_AA6YQ_BPF_TAPS, 4), (RC_AA6YQ_BPF_TAPS, 1025), (RC_NOTCH_FREQ, 5000),
        (RC_NOTCH_TAPS, 1000), (RC_LMS_MU2, -1), (RC_LMS_GAMMA, 1.5), (RC_PLL_LOOP_ORDER, 0),
        (RC_PLL_LOOP_ORDER, 32), (RC_TX_LPF_FREQ, 5), (RC_TX_CHAR_WAIT, 51), (RC_PLL_VCO_GAIN, .nan),
    ]
    for (p, v) in bad { #expect(rttycore_set_param(core, p, v) == RC_ERR_RANGE, "\(p) \(v)") }
}

@Test func pllParametersStillDecode() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_DEMOD_TYPE, 2) == RC_OK)
    #expect(rttycore_set_param(core, RC_PLL_VCO_GAIN, 3.0) == RC_OK)
    #expect(rttycore_set_param(core, RC_PLL_LOOP_FC, 250) == RC_OK)
    #expect(decode(core, RTTYSignalGenerator().generate(text: filterText)) == filterText)
}

@Test func charWaitLengthensTransmission() throws {
    let base = try transmit("RYRYRYRYRY")
    let slow = try transmit("RYRYRYRYRY") { #expect(rttycore_set_param($0, RC_TX_CHAR_WAIT, 30) == RC_OK) }
    #expect(slow.count > base.count + 11025 / 4, "\(base.count) → \(slow.count)")
    let rx = try #require(makeCore())
    defer { rttycore_destroy(rx) }
    #expect(decode(rx, slow).contains("RYRYRYRYRY"))
}

// Review I-3: an odd number of taps would leave a coefficient uninitialised → round up to an even number
@Test func oddTapCountsRoundedToEven() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    for p in [RC_AA6YQ_BPF_TAPS, RC_AA6YQ_BEF_TAPS, RC_NOTCH_TAPS, RC_LMS_TAPS] {
        #expect(rttycore_set_param(core, p, 101) == RC_OK)
        #expect(rttycore_get_param(core, p) == 102, "\(p)")
    }
    #expect(rttycore_set_param(core, RC_NOTCH_TAPS, 511) == RC_OK)
    #expect(rttycore_get_param(core, RC_NOTCH_TAPS) == 512)
    #expect(rttycore_set_param(core, RC_AA6YQ, 1) == RC_OK)
    #expect(decode(core, RTTYSignalGenerator().generate(text: filterText)) == filterText)
}
