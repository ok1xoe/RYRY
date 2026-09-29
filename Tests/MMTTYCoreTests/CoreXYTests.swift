import Testing
import MMTTYCore
import RTTYSignalKit

@Test func xyScopeDeliversMarkSpacePairs() throws {
    let core = try #require(makeCore())
    defer { rttycore_destroy(core) }
    var x = [Float](repeating: 0, count: 512), y = x
    #expect(rttycore_read_xy(core, &x, &y, 512) == 0)          // vypnuto
    rttycore_set_xy(core, 1)
    let s = RTTYSignalGenerator().generate(text: "RYRYRYRY", leadIn: 0.5)
    _ = decode(core, s)
    let n = rttycore_read_xy(core, &x, &y, 512)
    #expect(n == 512)
    #expect(x.prefix(n).contains { $0 != 0 } && y.prefix(n).contains { $0 != 0 })
    // po přečtení se sběr znovu spustí
    _ = decode(core, s)
    #expect(rttycore_read_xy(core, &x, &y, 512) == 512)
}
