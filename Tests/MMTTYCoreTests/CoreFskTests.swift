import Testing
import MMTTYCore

func fskCodes(_ core: OpaquePointer, seconds: Double) -> [UInt8] {
    var codes: [UInt8] = []
    var buf = [Float](repeating: 0, count: 1024)
    var cb = [UInt8](repeating: 0, count: 64)
    for _ in 0..<Int(seconds * 11025 / 1024) {
        _ = rttycore_generate_tx(core, &buf, buf.count)
        let n = rttycore_read_fsk_codes(core, &cb, cb.count)
        codes += cb[0..<n]
    }
    return codes
}

@Test func fskCodesFollowModulatedText() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_DIDDLE, 0) == RC_OK)
    rttycore_tx_begin(core, 0)
    _ = rttycore_queue_tx(core, "RY")
    let codes = fskCodes(core, seconds: 1.5)
    // MMTTY pořadí bitů: LTRS 0x1F, R 0x0A, Y 0x15
    #expect(codes == [0x1F, 0x0A, 0x15])
}

@Test func diddleProducesLtrsCodes() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    rttycore_tx_begin(core, 0)            // výchozí diddle LTR, začíná po 0,25 s
    let codes = fskCodes(core, seconds: 2)
    #expect(codes.count >= 8)
    #expect(codes.allSatisfy { $0 == 0x1F })
}

@Test func controlCodesAreNotEmitted() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    #expect(rttycore_set_param(core, RC_DIDDLE, 0) == RC_OK)
    rttycore_tx_begin(core, 0)
    var raw: [UInt8] = [0xFD, 0x1F, 0xFF, 0xFC]
    _ = rttycore_queue_tx_raw(core, &raw, raw.count)
    let codes = fskCodes(core, seconds: 1)
    #expect(codes.allSatisfy { $0 < 0x20 })
}
