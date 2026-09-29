import Foundation
import Testing
@testable import APIServer

@Test func jsonRPCNotchMethod() async throws {
    let h = try await makeAPIHarness()
    let (srv, port) = try await jsonServer(h)
    defer { srv.stop() }
    let c = WSClient(port: port)
    let r = try await c.call("modem.notch", ["hz": 1800])
    let p = r["result"] as? [String: Any]
    #expect(p?["notchFreq"] as? Int == 1800)
    #expect(p?["lms"] as? Bool == true)
    let bad = try await c.call("modem.notch", ["hz": "x"])
    #expect((bad["error"] as? [String: Any])?["code"] as? Int == -32602)
}

@Test func jsonRPCExportCabrillo() async throws {
    let h = try await makeAPIHarness()
    let (srv, port) = try await jsonServer(h)
    defer { srv.stop() }
    let c = WSClient(port: port)
    _ = try await c.call("qso.setField", ["name": "call", "value": "DL1ABC"])
    _ = try await c.call("qso.log")
    let r = try await c.call("log.exportCabrillo", ["from": "2000-01-01T00:00:00Z"])
    let text = (r["result"] as? [String: Any])?["text"] as? String ?? ""
    #expect(text.hasPrefix("START-OF-LOG: 3.0") && text.contains(" DL1ABC ") && text.hasSuffix("END-OF-LOG:\r\n"))
    let bad = try await c.call("log.exportCabrillo", ["from": "yesterday"])
    #expect((bad["error"] as? [String: Any])?["code"] as? Int == -32602)
}

@Test func jsonRPCDXCCLookup() async throws {
    let h = try await makeAPIHarness()
    let (srv, port) = try await jsonServer(h)
    defer { srv.stop() }
    let c = WSClient(port: port)
    let r = try await c.call("dxcc.lookup", ["call": "OK/DL1ABC"])
    let o = r["result"] as? [String: Any]
    #expect(o?["name"] as? String == "Czech Republic")
    #expect(o?["cqZone"] as? Int == 15 && o?["continent"] as? String == "EU")
    let none = try await c.call("dxcc.lookup", ["call": "DL1ABC/MM"])
    #expect(none["result"] is NSNull)
    let bad = try await c.call("dxcc.lookup", [:])
    #expect((bad["error"] as? [String: Any])?["code"] as? Int == -32602)
}

@Test func jsonRPCMessages() async throws {
    let h = try await makeAPIHarness()
    let (srv, port) = try await jsonServer(h)
    defer { srv.stop() }
    let c = WSClient(port: port)
    let l = try await c.call("msg.list")
    #expect(((l["result"] as? [[String: Any]])?.count ?? 0) >= 3)
    let r = try await c.call("msg.run", ["index": 0])
    #expect(r["result"] as? Bool == true)
    _ = try await c.call("engine.rxNow")
    let bad = try await c.call("msg.run", ["index": 99])
    #expect((bad["error"] as? [String: Any])?["code"] as? Int == -32602)
}

@Test func jsonRPCQTCStatusAndList() async throws {
    let h = try await makeAPIHarness()
    let (srv, port) = try await jsonServer(h)
    defer { srv.stop() }
    let c = WSClient(port: port)
    let st = try await c.call("qtc.status", ["call": "W1AW"])
    let o = st["result"] as? [String: Any]
    #expect(o?["exchanged"] as? Int == 0 && o?["nextSeries"] as? Int == 1 && (o?["available"] as? [Any]) != nil)
    let l = try await c.call("qtc.list")
    #expect((l["result"] as? [Any])?.isEmpty == true)
}
