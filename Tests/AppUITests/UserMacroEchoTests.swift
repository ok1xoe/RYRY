import Foundation
import Testing
import AppCore
import Engine
import MacroEngine
import ModemKit
import Settings
@testable import AppUI

// Echo vysílání v okně příjmu s nastavením uživatele (squelch, zářez, mark 1740).
@Test(arguments: [0, 1, 2, 4, 5])
@MainActor func macroEchoMatchesTextWithUserParams(index: Int) async throws {
    let f = Fixture()
    f.configure = {
        $0.rtty = ["afc": .bool(false), "mark": .double(1740), "lms": .bool(true), "notchFreq": .int(1016),
                   "squelch": .bool(true), "demodType": .string("iir")]
    }
    await f.model.start()
    await f.model.setQSOField("call", "DL1ABC")
    let expected = MacroEngine.expand(f.model.settings.macros[index].text, context: await f.model.app!.macroContext()).plainText
    await f.model.runMacro(index)
    for _ in 0..<400 { await f.pump(); if await f.engine.state == .rx { break } }
    await f.settle()
    let echo = f.model.rxRuns.filter(\.echo).map(\.text).joined()
    let norm = { (s: String) in s.replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "|") }
    print("F\(index + 1) EXP :", norm(expected))
    print("F\(index + 1) ECHO:", norm(echo))
    #expect(norm(echo).contains(norm(expected).trimmingCharacters(in: CharacterSet(charactersIn: "|"))))
    await f.model.stop()
}
