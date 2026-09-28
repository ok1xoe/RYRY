import Testing
import MMTTYCore
import RTTYSignalKit

/// Pomocník: pustí vzorky jádrem po blocích 512 a vrátí dekódovaný text.
func decode(_ core: OpaquePointer, _ samples: [Float], block: Int = 512) -> String {
    var text = ""
    var buf = [RTTYCoreChar](repeating: RTTYCoreChar(), count: 256)
    var i = 0
    while i < samples.count {
        let n = min(block, samples.count - i)
        samples.withUnsafeBufferPointer { p in rttycore_process_rx(core, p.baseAddress! + i, n) }
        i += n
        let got = rttycore_read_chars(core, &buf, buf.count)
        for k in 0..<got { text.unicodeScalars.append(UnicodeScalar(UInt8(bitPattern: buf[k].ch))) }
    }
    return text
}

func makeCore(sampleRate: Double = 11025) -> OpaquePointer? {
    var cfg = rttycore_default_config()
    cfg.sampleRate = sampleRate
    return rttycore_create(&cfg)
}

let sample = "RYRYRY CQ CQ DE OK1XOE OK1XOE PSE K\r\n599 001 TU 73\r\n"

@Test(arguments: [0, 1, 2, 3])   // IIR, FIR, PLL, FFT
func decodesCleanSignalWithEveryDemodulator(demod: Int) throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_DEMOD_TYPE, Double(demod)) == RC_OK)
    let s = RTTYSignalGenerator().generate(text: sample)
    #expect(decode(core, s) == sample)
}

@Test(arguments: [(45.45, 170.0), (50.0, 170.0), (75.0, 170.0), (45.45, 850.0)])
func decodesOtherBaudAndShift(baud: Double, shift: Double) throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    // Široký shift: space musí zůstat pod Nyquistem demodulátoru (11025/4 ≈ 2756 Hz),
    // proto 850 Hz s mark 1275 Hz (běžné nastavení v MMTTY).
    let mark = shift > 200 ? 1275.0 : 2125.0
    #expect(rttycore_set_param(core, RC_BAUD, baud) == RC_OK)
    #expect(rttycore_set_param(core, RC_MARK, mark) == RC_OK)
    #expect(rttycore_set_param(core, RC_SPACE, mark + shift) == RC_OK)
    let s = RTTYSignalGenerator(baud: baud, markHz: mark, shiftHz: shift).generate(text: sample)
    #expect(decode(core, s) == sample)
}

@Test func decodesAt12000Hz() throws {
    let core = try #require(makeCore(sampleRate: 12000))
    defer { rttycore_destroy(core) }
    let s = RTTYSignalGenerator(sampleRate: 12000).generate(text: sample)
    #expect(decode(core, s) == sample)
}

@Test func decodesWithModerateNoise() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    var s = RTTYSignalGenerator(amplitude: 0.3).generate(text: sample)
    var noise = NoiseGenerator(seed: 1)
    noise.addNoise(to: &s, rms: 0.1)          // SNR ≈ 6,5 dB v celém pásmu 0–5,5 kHz
    #expect(decode(core, s) == sample)
}

@Test func reverseSettingDecodesReversedSignal() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_REVERSE, 1) == RC_OK)
    let s = RTTYSignalGenerator(reverse: true).generate(text: sample)
    #expect(decode(core, s) == sample)
}

// Review Focus 1
@Test(arguments: [44100.0, 48000.0, 8000.0, 0.0, -1.0, .nan])
func rejectsUnsupportedSampleRate(rate: Double) {
    #expect(makeCore(sampleRate: rate) == nil)
}

// Review Focus 2
@Test func rejectsOutOfRangeParametersWithoutChangingState() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    let before = rttycore_get_param(core, RC_BAUD)
    #expect(rttycore_set_param(core, RC_BAUD, 0) == RC_ERR_RANGE)
    #expect(rttycore_set_param(core, RC_BAUD, .nan) == RC_ERR_RANGE)
    #expect(rttycore_set_param(core, RC_MARK, 0) == RC_ERR_RANGE)
    #expect(rttycore_set_param(core, RC_FIR_TAP, 10000) == RC_ERR_RANGE)
    #expect(rttycore_set_param(core, RC_DEMOD_TYPE, 7) == RC_ERR_RANGE)
    #expect(rttycore_set_param(core, RTTYCoreParam(rawValue: 9999), 1) == RC_ERR_UNKNOWN)
    #expect(rttycore_get_param(core, RC_BAUD) == before)
}

@Test func defaultsMatchMMTTY() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_get_param(core, RC_MARK) == 2125)
    #expect(rttycore_get_param(core, RC_SPACE) == 2295)
    #expect(abs(rttycore_get_param(core, RC_BAUD) - 45.45) < 1e-9)
    #expect(rttycore_get_param(core, RC_BIT_LENGTH) == 5)
    #expect(rttycore_get_param(core, RC_AFC) == 1)
}

@Test func twoInstancesWithDifferentRatesAreIndependent() throws {
    let a = try #require(makeCore(sampleRate: 11025))
    let b = try #require(makeCore(sampleRate: 12000))
    defer { rttycore_destroy(a); rttycore_destroy(b) }
    // Přenastavení po vytvoření b: návrh filtrů čte vzorkovací frekvenci – musí být ta z a.
    #expect(rttycore_set_param(a, RC_SPACE, 2300) == RC_OK)
    #expect(rttycore_set_param(a, RC_SPACE, 2295) == RC_OK)
    #expect(rttycore_set_param(a, RC_IIR_BW, 60) == RC_OK)
    #expect(rttycore_set_param(a, RC_BAUD, 45.45) == RC_OK)
    let sa = RTTYSignalGenerator(sampleRate: 11025).generate(text: sample)
    let sb = RTTYSignalGenerator(sampleRate: 12000).generate(text: sample)
    var ta = "", tb = ""
    var buf = [RTTYCoreChar](repeating: RTTYCoreChar(), count: 256)
    var ia = 0, ib = 0
    while ia < sa.count || ib < sb.count {           // prokládané zpracování
        if ia < sa.count {
            let n = min(512, sa.count - ia)
            sa.withUnsafeBufferPointer { rttycore_process_rx(a, $0.baseAddress! + ia, n) }; ia += n
            let g = rttycore_read_chars(a, &buf, 256)
            for k in 0..<g { ta.unicodeScalars.append(UnicodeScalar(UInt8(bitPattern: buf[k].ch))) }
        }
        if ib < sb.count {
            let n = min(512, sb.count - ib)
            sb.withUnsafeBufferPointer { rttycore_process_rx(b, $0.baseAddress! + ib, n) }; ib += n
            let g = rttycore_read_chars(b, &buf, 256)
            for k in 0..<g { tb.unicodeScalars.append(UnicodeScalar(UInt8(bitPattern: buf[k].ch))) }
        }
    }
    #expect(ta == sample)
    #expect(tb == sample)
}
