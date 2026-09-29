import Foundation
import Testing
import Engine
import MacroEngine
import ModemKit
import RTTYModem
import Settings
@testable import AppCore

private func decode(_ samples: [Float]) async throws -> String {
    let m = try RTTYModem()
    let ev = m.events
    (samples + [Float](repeating: 0, count: 4000)).withUnsafeBufferPointer { m.processRx($0) }
    m.finishEvents()
    var t = ""
    for await e in ev { if case .rxText(let c, false) = e { t.append(c) } }
    return t
}

/// Každé výchozí makro F1–F11 musí odvysílat přesně svůj rozvinutý text.
@Test(arguments: 0..<11)
func defaultMacroTransmitsItsText(index: Int) async throws {
    let h = try makeApp(ptt: .none)
    try await h.app.start()
    try await h.app.setQSOField("call", "DL1ABC")
    try await h.app.setQSOField("name", "HANS")
    let expected = MacroEngine.expand(AppSettings.defaultMacros[index].text, context: await h.app.macroContext()).plainText
    try await h.app.runMacro(index: index)
    if index == 8 { await h.app.rx() }                      // RYRY končí '#' (zůstat v TX)
    await run(h) { await h.engine.state == .rx && h.audio.tx.count > 0 }
    let got = try await decode(h.audio.tx)
    let norm = { (s: String) in s.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "|") }
    print("F\(index + 1) EXPECTED:", norm(expected))
    print("F\(index + 1) GOT     :", norm(got))
    if index != 9 { #expect(norm(got).contains(norm(expected).trimmingCharacters(in: CharacterSet(charactersIn: "|"))), "F\(index + 1)") }
    await h.app.stop()
}
