import Foundation
import Testing
@testable import MacroEngine

func ctx() -> MacroContext {
    var c = MacroContext()
    c.myCall = "OK1XOE"; c.hisCall = "DL1ABC"; c.name = "HANS"; c.qth = "BERLIN"
    c.rstSent = "599001"; c.rstRcvd = "599012-ZZ"
    c.now = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-21 14:13:20 UTC
    return c
}

func text(_ r: MacroResult) -> String {
    r.outputs.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
}

@Test func basicVariables() {
    let r = MacroEngine.expand("%c DE %m %n %q %r %s", context: ctx())
    #expect(text(r) == "DL1ABC DE OK1XOE HANS BERLIN 599012-ZZ 599001")
    #expect(r.end == .none && r.mode == .send && !r.logQSO)
}

@Test func nameDefaultsToOM() {
    var c = ctx(); c.name = ""
    #expect(text(MacroEngine.expand("TNX %n", context: c)) == "TNX OM")
}

@Test func contestSplits() {
    let c = ctx()
    #expect(text(MacroEngine.expand("%R", context: c)) == "599")
    #expect(text(MacroEngine.expand("%N", context: c)) == "012-ZZ")
    #expect(text(MacroEngine.expand("%M", context: c)) == "001")
    #expect(text(MacroEngine.expand("%x|%y", context: c)) == "012|ZZ")
    var short = c; short.rstRcvd = "5"
    #expect(text(MacroEngine.expand("%R%N", context: short)) == "599")
}

@Test func dateTimeAndGreeting() {
    let c = ctx()
    #expect(text(MacroEngine.expand("%D %T %t", context: c)) == "2026-SEP-21 14:13 1413")
    #expect(text(MacroEngine.expand("%g/%f", context: c)) == "GOOD AFTERNOON/GA")
}

@Test func shiftCodesAreRaw() {
    let r = MacroEngine.expand("A%LB%FC", context: ctx())
    #expect(r.outputs == [.text("A"), .raw([0x1F]), .text("B"), .raw([0x1B]), .text("C")])
}

@Test func cwIDForOK() {
    let r = MacroEngine.expand("%{OK}", context: ctx())
    let dash: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFE], dot: [UInt8] = [0xFF, 0xFE], gap: [UInt8] = [0xFE, 0xFE]
    let want: [UInt8] = [0xFD, 0xFE] + dash + dash + dash + gap + dash + dot + dash + gap
    #expect(r.outputs == [.raw(want)])
}

@Test func cwIDExpandsVariablesAndUnknownChars() {
    let r = MacroEngine.expand("%{%m}", context: ctx())
    guard case .raw(let codes)? = r.outputs.first else { Issue.record("čekám raw"); return }
    #expect(codes.count > 30)
    let sp = MacroEngine.expand("%{E E}", context: ctx())
    guard case .raw(let c2)? = sp.outputs.first else { Issue.record("čekám raw"); return }
    // E = tečka, mezera = 5× nosná vyp. + mezera za znakem
    #expect(c2 == [0xFD, 0xFE, 0xFF, 0xFE, 0xFE, 0xFE] + [UInt8](repeating: 0xFE, count: 5) + [0xFE, 0xFE] + [0xFF, 0xFE, 0xFE, 0xFE])
}

@Test func terminators() {
    #expect(MacroEngine.expand("CQ CQ DE %m K\\", context: ctx()).end == .rxAfter)
    #expect(MacroEngine.expand("CQ K\\\r\n", context: ctx()).end == .rxAfter)
    #expect(MacroEngine.expand("RYRY #", context: ctx()).end == .keepTx)
    #expect(!text(MacroEngine.expand("CQ K\\", context: ctx())).contains("\\"))
    #expect(MacroEngine.expand("#%c ", context: ctx()).mode == .toEditor)
    #expect(text(MacroEngine.expand("#%c ", context: ctx())) == "DL1ABC ")
    #expect(MacroEngine.expand("\\%c", context: ctx()).mode == .toEditor)
}

@Test func endAndLogMarker() {
    let r = MacroEngine.expand("TU%l 73%E IGNORED", context: ctx())
    #expect(text(r) == "TU 73")
    #expect(r.logQSO)
}

// Review Focus 3
@Test func malformedTemplatesDoNotCrash() {
    #expect(text(MacroEngine.expand("ABC%", context: ctx())) == "ABC")
    #expect(text(MacroEngine.expand("A%zB", context: ctx())) == "A%%B")
    let open = MacroEngine.expand("X%{OK", context: ctx())
    #expect(open.outputs.first == .text("X"))
    #expect(open.outputs.count == 2)
    #expect(MacroEngine.expand("", context: ctx()).outputs.isEmpty)
}

@Test func plainTextPreview() {
    #expect(MacroEngine.expand("CQ %{%m} K", context: ctx()).plainText == "CQ [CW ID] K")
}

@Test func shiftCodesInsideCWIDAreSevenCarrierOff() {
    guard case .raw(let codes)? = MacroEngine.expand("%{%L}", context: ctx()).outputs.first else { Issue.record("raw"); return }
    #expect(codes == [0xFD, 0xFE] + [UInt8](repeating: 0xFE, count: 7))
}
