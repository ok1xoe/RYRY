import Foundation
import Testing
import MacroEngine
import RTTYModem
import TestSupport
@testable import Engine

func decodeTx(_ samples: [Float]) async throws -> String {
    let m = try RTTYModem()
    let ev = m.events
    (samples + [Float](repeating: 0, count: 4000)).withUnsafeBufferPointer { m.processRx($0) }
    m.finishEvents()
    var t = ""
    for await e in ev { if case .rxText(let c, false) = e { t.append(c) } }
    return t
}

func macroContext() -> MacroContext { var c = MacroContext(); c.myCall = "OK1XOE"; c.hisCall = "DL1ABC"; return c }

@Test func macroTransmitsAndReturnsToRx() async throws {
    let r = try makeEngine()
    try await r.engine.start()
    let m = MacroEngine.expand("CQ CQ DE %m %m K\\", context: macroContext())
    try await r.engine.sendMacro(m)
    await pump(r) { await r.engine.state == .rx && r.audio.writeCalls > 0 }
    #expect(await r.engine.state == .rx)
    #expect(try await decodeTx(r.audio.tx).contains("CQ CQ DE OK1XOE OK1XOE K"))
    await r.engine.stop()
}

@Test func macroKeepTxStaysTransmitting() async throws {
    let r = try makeEngine()
    try await r.engine.start()
    try await r.engine.sendMacro(MacroEngine.expand("RYRY #", context: macroContext()))
    await pump(r, steps: 60) { false }                       // 3 s
    #expect(await r.engine.state == .tx)
    await r.engine.stop()
}

@Test func cwIDProducesCarrierGaps() async throws {
    let r = try makeEngine()
    try await r.engine.start()
    try await r.engine.sendMacro(MacroEngine.expand("%{%m}\\", context: macroContext()))
    await pump(r) { await r.engine.state == .rx && r.audio.writeCalls > 0 }
    // najít úseky ticha ≥ 30 ms uprostřed signálu (nosná vypnutá mezi CW prvky)
    let s = r.audio.tx
    let first = try #require(s.firstIndex { $0 != 0 })
    var gaps = 0, run = 0
    for v in s[first...] { if v == 0 { run += 1 } else { if run >= 330 { gaps += 1 }; run = 0 } }
    #expect(gaps >= 10, "CW mezer: \(gaps)")
}

@Test func shiftMacrosKeepTextCorrect() async throws {
    let r = try makeEngine()
    try await r.engine.start()
    try await r.engine.sendMacro(MacroEngine.expand("ABC %F123 %LXYZ\\", context: macroContext()))
    await pump(r) { await r.engine.state == .rx && r.audio.writeCalls > 0 }
    #expect(try await decodeTx(r.audio.tx).contains("ABC 123 XYZ"))
    await r.engine.stop()
}

@Test func logMarkerEmitsEvent() async throws {
    let r = try makeEngine()
    try await r.engine.start()
    try await r.engine.sendMacro(MacroEngine.expand("TU%l\\", context: macroContext()))
    await pump(r) { await r.engine.state == .rx && r.audio.writeCalls > 0 }
    await r.engine.stop()
    var saw = false
    for await e in r.events { if case .logRequested = e { saw = true } }
    #expect(saw)
}

@Test func editorMacroDoesNotTransmit() async throws {
    let r = try makeEngine()
    try await r.engine.start()
    try await r.engine.sendMacro(MacroEngine.expand("#%c DE %m", context: macroContext()))
    await r.engine.pump()
    #expect(await r.engine.state == .rx)
    await r.engine.stop()
}
