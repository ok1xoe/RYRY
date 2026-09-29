import Testing
@testable import AppCore

@Test func textHistoryClearResetsLengthAndCursors() {
    let t = TextHistory(limit: 10)
    t.append("HELLO")
    var cur = 0
    _ = t.takeNew(cursor: &cur)
    t.clear()
    #expect(t.totalLength == 0)
    t.append("AB")
    #expect(t.takeNew(cursor: &cur) == "AB")          // kurzor za koncem se srovná
}

@Test func textHistoryTrimIsChunked() {
    let t = TextHistory(limit: 1000)
    for _ in 0..<5000 { t.append("X") }
    #expect(t.totalLength == 5000)
    #expect(t.range(start: 4000, length: 1000).count == 1000)
    #expect(t.range(start: 0, length: 10) == "")
}
