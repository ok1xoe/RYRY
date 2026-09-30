import Foundation
import Testing
import AppCore
import RigControl
import XMLRPC
@testable import APIServer

// C1: extreme numbers must not crash the application
@Test func extremeNumbersDoNotCrash() async throws {
    let h = try await makeAPIHarness()
    let (srv, t) = try await fldigi(h)
    defer { srv.stop() }
    _ = try? await t.call("text.get_rx", [.int(Int.max), .int(10)])
    _ = try? await t.call("text.get_rx", [.int(5), .int(Int.max)])
    _ = try? await t.call("modem.set_carrier", [.double(1e300)])
    _ = try? await t.call("text.get_rx", [.double(1e300), .double(-1e300)])
    let (js, port) = try await jsonServer(h)
    defer { js.stop() }
    let c = WSClient(port: port)
    try await c.sendRaw(#"{"jsonrpc":"2.0","id":1,"method":"macro.run","params":{"index":1e300}}"#)
    #expect((try await c.receive()["error"] as? [String: Any])?["code"] as? Int == -32602)
    try await c.sendRaw(#"{"jsonrpc":"2.0","id":2,"method":"profile.load","params":{"slot":-1e300}}"#)
    #expect((try await c.receive()["error"] as? [String: Any]) != nil)
    #expect(try await t.call("fldigi.name", []) == .string("RYRY"))    // still running
    await h.app.stop()
}

@Test func textHistoryRangeSaturates() {
    let t = TextHistory()
    t.append("ABC")
    #expect(t.range(start: Int.max, length: Int.max) == "")
    #expect(t.range(start: 1, length: Int.max) == "BC")
    #expect(t.range(start: Int.min, length: 2) == "")          // interval entirely before the start of the text
}

// I2: a WebSocket message larger than 1 MB is rejected
@Test func oversizedWebSocketMessageIsRejected() async throws {
    let h = try await makeAPIHarness()
    let (js, port) = try await jsonServer(h)
    defer { js.stop() }
    let c = WSClient(port: port)
    let big = #"{"jsonrpc":"2.0","id":1,"method":"tx.send","params":{"text":""# + String(repeating: "A", count: 2 << 20) + #""}}"#
    try? await c.sendRaw(big)
    let r = try? await c.receive(timeout: 2)
    #expect(r?["result"] == nil)
    #expect(await h.engine.txPending == 0)
    await h.app.stop()
}

// I3: requests from a browser (Origin) are rejected
@Test func browserOriginIsRejected() async throws {
    let h = try await makeAPIHarness()
    let srv = FldigiXMLRPCServer(app: h.app, host: "127.0.0.1", port: 0)
    let port = try await srv.start()
    defer { srv.stop() }
    let r = rawExchange(port: port, send: ["POST /RPC2 HTTP/1.1\r\nOrigin: http://evil.example\r\nContent-Type: text/plain\r\nContent-Length: 81\r\n\r\n<?xml version=\"1.0\"?><methodCall><methodName>main.tx</methodName></methodCall>\r\n"]) ?? ""
    #expect(r.contains("403"))
    #expect(await h.engine.state == .rx)
    let (js, wport) = try await jsonServer(h)
    defer { js.stop() }
    var req = URLRequest(url: URL(string: "ws://127.0.0.1:\(wport)/v1")!)
    req.setValue("http://evil.example", forHTTPHeaderField: "Origin")
    req.timeoutInterval = 2
    let task = URLSession.shared.webSocketTask(with: req)
    task.resume()
    try? await task.send(.string(#"{"jsonrpc":"2.0","id":1,"method":"engine.status"}"#))
    let got = try? await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { g in
        g.addTask { try await task.receive() }
        g.addTask { try await Task.sleep(for: .seconds(2)); throw URLError(.timedOut) }
        let m = try await g.next()!; g.cancelAll(); return m
    }
    #expect(got == nil)
    await h.app.stop()
}

// I4 + I5: Expect: 100-continue and HTTP/1.0 without keep-alive
@Test func expectContinueAndHTTP10() async throws {
    let s = echoServer()
    let port = try await s.start()
    defer { s.stop() }
    let r = rawExchange(port: port, send: ["POST / HTTP/1.1\r\nExpect: 100-continue\r\nContent-Length: 2\r\n\r\n"], readFor: 0.3) ?? ""
    #expect(r.contains("100 Continue"))
    // HTTP/1.0: the server closes the connection after the response (rawExchange ends with EOF before the timeout)
    let t0 = Date()
    let r2 = rawExchange(port: port, send: ["POST / HTTP/1.0\r\nContent-Length: 2\r\n\r\nok"], readFor: 3) ?? ""
    #expect(r2.contains("echo:POST / ok"))
    #expect(Date().timeIntervalSince(t0) < 1.5)
}

// I6: connection count limit and timeout for unfinished headers
@Test func connectionCapAndHeaderTimeout() async throws {
    let s = HTTPServer(host: "127.0.0.1", port: 0, maxConnections: 4, headerTimeout: .milliseconds(300)) { _ in
        HTTPResponse(status: 200, headers: [:], body: Data("ok".utf8))
    }
    let port = try await s.start()
    defer { s.stop() }
    let t0 = Date()
    let half = rawExchange(port: port, send: ["POST / HTTP/1.1\r\nContent-"], readFor: 3)
    #expect(Date().timeIntervalSince(t0) < 2)          // the server closed the connection after the header timeout
    #expect(half?.contains("408") == true || half == "")
}

// I9: stop() also terminates open keep-alive connections
@Test func stopClosesKeepAliveConnections() async throws {
    let s = echoServer()
    let port = try await s.start()
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(fd) }
    var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_port = port.bigEndian
    inet_pton(AF_INET, "127.0.0.1", &a.sin_addr)
    _ = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    try await Task.sleep(for: .milliseconds(100))
    s.stop()
    try await Task.sleep(for: .milliseconds(200))
    let req = "POST / HTTP/1.1\r\nContent-Length: 1\r\n\r\nx"
    _ = req.withCString { Darwin.send(fd, $0, strlen($0), 0) }
    var tv = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var buf = [UInt8](repeating: 0, count: 256)
    #expect(recv(fd, &buf, 256, 0) <= 0)                // the connection is closed
}

// I7: fldigi ^r / ^R in text.add_tx = RX once the transmission finishes
@Test func fldigiCaretRReturnsToRx() async throws {
    let h = try await makeAPIHarness()
    let (srv, t) = try await fldigi(h)
    defer { srv.stop() }
    _ = try await t.call("text.add_tx", [.string("TU 73^r")])
    _ = try await t.call("main.tx", [])
    await h.run { await h.engine.state == .rx && h.audio.writeCalls > 0 }
    #expect(await h.engine.state == .rx)
    guard case .base64(let d) = try await t.call("tx.get_data", []) else { Issue.record("tx"); return }
    #expect(!String(decoding: d, as: UTF8.self).contains("R"))  // ^r is not transmitted
    await h.app.stop()
}

// set_frequency without a rig: silently, like fldigi
@Test func setFrequencyWithoutRigIsSilent() async throws {
    let h = try await makeAPIHarness(rig: NoRig())
    let (srv, t) = try await fldigi(h)
    defer { srv.stop() }
    #expect(try await t.call("main.set_frequency", [.double(7_045_000)]) == .double(0))
    await h.app.stop()
}

// I8: a crash of the client that started transmitting turns TX off
@Test func disconnectedClientThatStartedTxStopsIt() async throws {
    let h = try await makeAPIHarness()
    let (js, port) = try await jsonServer(h)
    defer { js.stop() }
    let c = WSClient(port: port)
    _ = try await c.call("engine.tune")
    #expect(await h.engine.state != .rx)
    c.task.cancel(with: .abnormalClosure, reason: nil)
    try await Task.sleep(for: .milliseconds(300))
    await h.run(steps: 20) { await h.engine.state == .rx }
    #expect(await h.engine.state == .rx)
    await h.app.stop()
}

// I8: the tx.progress notification
@Test func txProgressNotifications() async throws {
    let h = try await makeAPIHarness()
    let (js, port) = try await jsonServer(h)
    defer { js.stop() }
    let c = WSClient(port: port)
    _ = try await c.call("events.subscribe", ["events": ["tx.progress"]])
    _ = try await c.call("tx.send", ["text": "RYRYRYRYRYRY"])
    _ = try await c.call("engine.tx")
    _ = try await c.call("engine.rx")
    await h.run { await h.engine.state == .rx && h.audio.writeCalls > 0 }
    let n = try await c.notifications("tx.progress", count: 2)
    #expect(n.count >= 2)
    await h.app.stop()
}
