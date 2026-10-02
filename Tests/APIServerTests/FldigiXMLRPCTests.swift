import Foundation
import Testing
import RigControl
import RTTYSignalKit
import XMLRPC
@testable import APIServer

func fldigi(_ h: APIHarness) async throws -> (FldigiXMLRPCServer, HTTPXMLRPCTransport) {
    let srv = FldigiXMLRPCServer(app: h.app, host: "127.0.0.1", port: 0)
    let port = try await srv.start()
    return (srv, HTTPXMLRPCTransport(url: URL(string: "http://127.0.0.1:\(port)/RPC2")!, timeout: 5))
}

@Test func identityAndList() async throws {
    let h = try await makeAPIHarness()
    let (srv, t) = try await fldigi(h)
    defer { srv.stop() }
    #expect(try await t.call("fldigi.name", []) == .string("RYRY"))
    guard case .array(let list) = try await t.call("fldigi.list", []) else { Issue.record("list"); return }
    #expect(list.count > 40)
    await h.app.stop()
}

@Test func txRxCycleAndStatus() async throws {
    let h = try await makeAPIHarness()
    let (srv, t) = try await fldigi(h)
    defer { srv.stop() }
    #expect(try await t.call("main.get_trx_status", []) == .string("rx"))
    _ = try await t.call("text.add_tx", [.string("CQ DE OK1XOE K")])
    _ = try await t.call("main.tx", [])
    #expect(try await t.call("main.get_trx_status", []) == .string("tx"))
    _ = try await t.call("main.rx", [])
    await h.run { await h.engine.state == .rx && h.audio.writeCalls > 0 }
    #expect(try await t.call("main.get_trx_status", []) == .string("rx"))
    guard case .base64(let d) = try await t.call("tx.get_data", []) else { Issue.record("tx data"); return }
    #expect(String(decoding: d, as: UTF8.self).contains("CQ DE OK1XOE K"))
    await h.app.stop()
}

@Test func rxDataSinceLastQuery() async throws {
    let h = try await makeAPIHarness(ptt: .none)
    let (srv, t) = try await fldigi(h)
    defer { srv.stop() }
    h.audio.feedRx(RTTYSignalGenerator().generate(text: "HELLO WORLD"))
    await h.run { h.audio.rxRemaining == 0 }
    try await Task.sleep(for: .milliseconds(100))
    guard case .base64(let d1) = try await t.call("rx.get_data", []) else { Issue.record("rx"); return }
    #expect(String(decoding: d1, as: UTF8.self).contains("HELLO WORLD"))
    guard case .base64(let d2) = try await t.call("rx.get_data", []) else { Issue.record("rx2"); return }
    #expect(d2.isEmpty)
    let len = try await t.call("text.get_rx_length", []).intValue ?? 0
    #expect(len >= 11)
    guard case .base64(let d3) = try await t.call("text.get_rx", [.int(0), .int(len)]) else { Issue.record("get_rx"); return }
    #expect(String(decoding: d3, as: UTF8.self).contains("HELLO"))
    await h.app.stop()
}

@Test func logFieldsAndFrequency() async throws {
    let h = try await makeAPIHarness()
    let (srv, t) = try await fldigi(h)
    defer { srv.stop() }
    _ = try await t.call("log.set_call", [.string("dl1abc")])
    #expect(try await t.call("log.get_call", []) == .string("DL1ABC"))
    #expect(try await t.call("main.get_frequency", []) == .double(14_083_000))
    #expect(try await t.call("main.set_frequency", [.double(7_045_000)]) == .double(14_083_000))
    #expect(h.rig.freq == 7_045_000)
    #expect(try await t.call("log.get_band", []) == .string("40m"))
    _ = try await t.call("main.set_afc", [.bool(false)])
    #expect(try await t.call("main.get_afc", []) == .bool(false))
    #expect(try await t.call("modem.get_name", []) == .string("RTTY"))
    #expect(try await t.call("modem.get_carrier", []) == .int(2210))
    _ = try await t.call("modem.set_carrier", [.int(1500)])
    #expect(await h.app.modemParam("mark") == .double(1415))
    await h.app.stop()
}

@Test func unknownMethodAndBadParamsAreFaults() async throws {
    let h = try await makeAPIHarness()
    let (srv, t) = try await fldigi(h)
    defer { srv.stop() }
    await #expect(throws: XMLRPCFault.self) { _ = try await t.call("no.such", []) }
    do { _ = try await t.call("no.such", []) } catch let f as XMLRPCFault { #expect(f.code == -32601) }
    do { _ = try await t.call("main.set_frequency", [.string("abc")]) } catch let f as XMLRPCFault { #expect(f.code == -32602) }
    await h.app.stop()
}

// Review Focus 3
@Test func txWithoutPTTIsFault() async throws {
    let h = try await makeAPIHarness(ptt: .cat, rig: NoRig())
    let (srv, t) = try await fldigi(h)
    defer { srv.stop() }
    await #expect(throws: XMLRPCFault.self) { _ = try await t.call("main.tx", []) }
    #expect(try await t.call("main.get_trx_status", []) == .string("rx"))
    await h.app.stop()
}

// Review Focus 1
@Test func malformedXMLIsFault() async throws {
    let h = try await makeAPIHarness()
    let srv = FldigiXMLRPCServer(app: h.app, host: "127.0.0.1", port: 0)
    let port = try await srv.start()
    defer { srv.stop() }
    var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/RPC2")!)
    req.httpMethod = "POST"; req.httpBody = Data("<methodCall><broken".utf8)
    let (d, _) = try await URLSession.shared.data(for: req)
    #expect(throws: XMLRPCFault.self) { _ = try XMLRPCCodec.decodeResponse(d) }
    #expect(try await HTTPXMLRPCTransport(url: URL(string: "http://127.0.0.1:\(port)/RPC2")!).call("fldigi.name", []) == .string("RYRY"))
    await h.app.stop()
}
