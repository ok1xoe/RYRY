import Foundation
import Testing
import RigControl
import RTTYSignalKit
@testable import APIServer

final class WSClient: @unchecked Sendable {
    let task: URLSessionWebSocketTask
    private var nextId = 1
    private var pending: [[String: Any]] = []          // received messages not processed yet
    init(port: UInt16) {
        task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/v1")!)
        task.resume()
    }
    func sendRaw(_ s: String) async throws { try await task.send(.string(s)) }
    func receive(timeout: Double = 3) async throws -> [String: Any] {
        if !pending.isEmpty { return pending.removeFirst() }
        let msg = try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { g in
            g.addTask { try await self.task.receive() }
            g.addTask { try await Task.sleep(for: .seconds(timeout)); throw URLError(.timedOut) }
            let m = try await g.next()!; g.cancelAll(); return m
        }
        guard case .string(let s) = msg,
              let o = try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { return [:] }
        return o
    }
    /// Calls a method and returns the response (notifications arriving meanwhile are stored).
    func call(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        let id = nextId; nextId += 1
        let req: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        try await sendRaw(String(decoding: try JSONSerialization.data(withJSONObject: req), as: UTF8.self))
        var stash: [[String: Any]] = []
        while true {
            let m = try await receive()
            if (m["id"] as? Int) == id { pending = stash + pending; return m }
            stash.append(m)
        }
    }
    func notifications(_ method: String, count: Int, timeout: Double = 5) async throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        let end = Date().addingTimeInterval(timeout)
        while out.count < count, Date() < end {
            let m = try await receive(timeout: max(0.1, end.timeIntervalSinceNow))
            if m["method"] as? String == method { out.append(m) }
        }
        return out
    }
}

func jsonServer(_ h: APIHarness, maxQueue: Int = 1000) async throws -> (JSONRPCServer, UInt16) {
    let s = JSONRPCServer(app: h.app, host: "127.0.0.1", port: 0, maxQueue: maxQueue)
    return (s, try await s.start())
}

@Test func statusAndErrors() async throws {
    let h = try await makeAPIHarness()
    let (srv, port) = try await jsonServer(h)
    defer { srv.stop() }
    let c = WSClient(port: port)
    let st = try await c.call("engine.status")
    #expect((st["result"] as? [String: Any])?["state"] as? String == "rx")
    #expect(((try await c.call("no.such"))["error"] as? [String: Any])?["code"] as? Int == -32601)
    #expect(((try await c.call("rig.setFreq"))["error"] as? [String: Any])?["code"] as? Int == -32602)
    try await c.sendRaw("{not json")
    #expect((try await c.receive()["error"] as? [String: Any])?["code"] as? Int == -32700)
    await h.app.stop()
}

// Review Focus 3
@Test func txWithoutPTTIsError32001() async throws {
    let h = try await makeAPIHarness(ptt: .cat, rig: NoRig())
    let (srv, port) = try await jsonServer(h)
    defer { srv.stop() }
    let c = WSClient(port: port)
    _ = try await c.call("tx.send", ["text": "CQ"])
    let r = try await c.call("engine.tx")
    #expect((r["error"] as? [String: Any])?["code"] as? Int == -32001)
    await h.app.stop()
}

@Test func subscribeReceivesRxChars() async throws {
    let h = try await makeAPIHarness(ptt: .none)
    let (srv, port) = try await jsonServer(h)
    defer { srv.stop() }
    let c = WSClient(port: port)
    _ = try await c.call("events.subscribe", ["events": ["rx.char"]])
    h.audio.feedRx(RTTYSignalGenerator().generate(text: "HELLO"))
    await h.run { h.audio.rxRemaining == 0 }
    let n = try await c.notifications("rx.char", count: 5)
    let s = n.compactMap { ($0["params"] as? [String: Any])?["char"] as? String }.joined()
    #expect(s.contains("HELLO"))
    await h.app.stop()
}

@Test func modemParamsAndQSOLog() async throws {
    let h = try await makeAPIHarness()
    let (srv, port) = try await jsonServer(h)
    defer { srv.stop() }
    let c = WSClient(port: port)
    _ = try await c.call("modem.setParams", ["params": ["baud": 75, "afc": false]])
    let p = (try await c.call("modem.getParams"))["result"] as? [String: Any]
    #expect(p?["baud"] as? Double == 75 && p?["afc"] as? Bool == false)
    let bad = try await c.call("modem.setParams", ["params": ["baud": 99999]])
    #expect((bad["error"] as? [String: Any])?["code"] as? Int == -32602)
    _ = try await c.call("events.subscribe", ["events": ["qso.logged"]])
    _ = try await c.call("qso.setField", ["name": "call", "value": "DL1ABC"])
    let logged = try await c.call("qso.log")
    #expect((logged["result"] as? [String: Any])?["call"] as? String == "DL1ABC")
    let n = try await c.notifications("qso.logged", count: 1)
    #expect(n.count == 1)
    let q = (try await c.call("log.query", ["call": "DL1ABC"]))["result"] as? [[String: Any]]
    #expect(q?.count == 1)
    await h.app.stop()
}

// Review Focus 2: a client that cannot keep up with sending is disconnected once the queue overflows
final class StuckSink: WSSink, @unchecked Sendable {
    var sent = 0, closed = false
    func send(_ text: String, completion: @escaping @Sendable (Error?) -> Void) { sent += 1 }   // never finishes
    func close() { closed = true }
}

@Test func stuckClientIsDroppedAfterQueueLimit() {
    let sink = StuckSink()
    let s = ClientSession(sink: sink, maxQueue: 20)
    s.subscribe(["rx.char"])
    for _ in 0..<25 { s.notify("rx.char", ["char": "R"]) }
    #expect(sink.closed)
    #expect(s.isClosed)
    #expect(sink.sent == 20)
}

@Test func twoClientsBothReceiveEvents() async throws {
    let h = try await makeAPIHarness(ptt: .none)
    let (srv, port) = try await jsonServer(h)
    defer { srv.stop() }
    let a = WSClient(port: port), b = WSClient(port: port)
    _ = try await a.call("events.subscribe", ["events": ["rx.char"]])
    _ = try await b.call("events.subscribe", ["events": ["rx.char"]])
    #expect(await srv.clientCount == 2)
    h.audio.feedRx(RTTYSignalGenerator().generate(text: "RYRYRY TEST"))
    await h.run { h.audio.rxRemaining == 0 }
    #expect(try await a.notifications("rx.char", count: 8).count >= 8)
    #expect(try await b.notifications("rx.char", count: 8).count >= 8)
    await h.app.stop()
}

// Review Focus 1
@Test func binaryFrameIsRejectedServerSurvives() async throws {
    let h = try await makeAPIHarness()
    let (srv, port) = try await jsonServer(h)
    defer { srv.stop() }
    let c = WSClient(port: port)
    try await c.task.send(.data(Data([0, 1, 2])))
    let r = try await c.receive()
    #expect((r["error"] as? [String: Any])?["code"] as? Int == -32600)
    let c2 = WSClient(port: port)
    #expect((try await c2.call("engine.status"))["result"] != nil)
    await h.app.stop()
}

/// Requests from one client are processed in order (qso.setField must run before macro.run).
@Test func requestsFromOneClientAreProcessedInOrder() async throws {
    let h = try await makeAPIHarness()
    let (srv, port) = try await jsonServer(h)
    defer { srv.stop() }
    let c = WSClient(port: port)
    for i in 1...60 {
        let method = i % 2 == 0 ? "qso.getCurrent" : "engine.status"
        try await c.sendRaw(#"{"jsonrpc":"2.0","id":\#(i),"method":"\#(method)"}"#)
    }
    var ids: [Int] = []
    while ids.count < 60 { if let id = (try await c.receive())["id"] as? Int { ids.append(id) } }
    #expect(ids == Array(1...60))
    await h.app.stop()
}
