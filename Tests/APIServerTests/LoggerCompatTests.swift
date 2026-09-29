import Foundation
import Testing
import RigControl
import RTTYSignalKit
import XMLRPC
@testable import APIServer

/// Sekvence volání RUMlogNG (metody zjištěné z binárky: main.get_trx_status, main.get_frequency,
/// main.set_frequency, rig.get_mode, rig.get_modes, rig.set_mode, rx.get_data, text.add_tx,
/// text.clear_tx, main.tx, tx.get_data, main.abort).
@Test func rumlogNGCallSequence() async throws {
    let h = try await makeAPIHarness()
    let (srv, t) = try await fldigi(h)
    defer { srv.stop() }
    #expect(try await t.call("main.get_trx_status", []) == .string("rx"))
    guard case .double(let f0) = try await t.call("main.get_frequency", []) else { Issue.record("freq"); return }
    #expect(f0 > 0)
    _ = try await t.call("main.set_frequency", [.double(14_085_000)])
    await h.engine.pollRig()
    #expect(try await t.call("main.get_frequency", []) == .double(14_085_000))
    guard case .string = try await t.call("rig.get_mode", []) else { Issue.record("mode"); return }
    guard case .array = try await t.call("rig.get_modes", []) else { Issue.record("modes"); return }
    _ = try await t.call("rig.set_mode", [.string("USB")])
    // příjem: rx.get_data vrací jen nové znaky
    h.audio.feedRx(RTTYSignalGenerator().generate(text: "CQ DE DL1ABC K"))
    await h.run { h.audio.rxRemaining == 0 }
    try await Task.sleep(for: .milliseconds(100))
    guard case .base64(let rx1) = try await t.call("rx.get_data", []) else { Issue.record("rx"); return }
    #expect(String(decoding: rx1, as: UTF8.self).contains("CQ DE DL1ABC K"))
    guard case .base64(let rx2) = try await t.call("rx.get_data", []) else { Issue.record("rx2"); return }
    #expect(rx2.isEmpty)
    // vysílání: clear_tx, add_tx, tx, abort
    _ = try await t.call("text.clear_tx", [])
    _ = try await t.call("text.add_tx", [.string("DL1ABC DE OK1XOE 599 599 K")])
    _ = try await t.call("main.tx", [])
    #expect(try await t.call("main.get_trx_status", []) == .string("tx"))
    await h.run { h.audio.writeCalls > 20 }
    _ = try await t.call("main.abort", [])
    await h.run { await h.engine.state == .rx }
    #expect(try await t.call("main.get_trx_status", []) == .string("rx"))
    guard case .base64(let txd) = try await t.call("tx.get_data", []) else { Issue.record("tx"); return }
    #expect(!txd.isEmpty)
    await h.app.stop()
}
