// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import Engine
import Foundation
import ModemKit
import Network
import QSOLog
import RigControl

/// Odesílač textových zpráv (WebSocket spojení; v testech náhrada).
protocol WSSink: AnyObject, Sendable {
    func send(_ text: String, completion: @escaping @Sendable (Error?) -> Void)
    func close()
}

/// Stav jednoho klienta: odběry a omezená fronta odchozích zpráv.
final class ClientSession: @unchecked Sendable {
    let id = UUID()
    private let sink: WSSink
    private let maxQueue: Int
    private let lock = NSLock()
    private var inFlight = 0
    private var subs: Set<String> = []
    private(set) var isClosed = false
    var spectrumTask: Task<Void, Never>?
    var lastSignal = Date.distantPast
    var onClose: (@Sendable () -> Void)?

    init(sink: WSSink, maxQueue: Int) { self.sink = sink; self.maxQueue = maxQueue }

    func subscribe(_ names: [String]) { lock.withLock { subs.formUnion(names) } }
    func unsubscribe(_ names: [String]) { lock.withLock { subs.subtract(names) } }
    func isSubscribed(_ name: String) -> Bool { lock.withLock { subs.contains(name) || subs.contains("*") } }

    func sendJSON(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        send(String(decoding: d, as: UTF8.self))
    }

    func send(_ text: String) {
        let over: Bool = lock.withLock {
            if isClosed { return false }
            if inFlight >= maxQueue { return true }
            inFlight += 1; return false
        }
        if over { close(); return }
        if lock.withLock({ isClosed }) { return }
        sink.send(text) { [weak self] err in
            guard let self else { return }
            self.lock.withLock { self.inFlight -= 1 }
            if err != nil { self.close() }
        }
    }

    func notify(_ method: String, _ params: Any) {
        guard isSubscribed(method) else { return }
        sendJSON(["jsonrpc": "2.0", "method": method, "params": params])
    }

    func close() {
        let first: Bool = lock.withLock { if isClosed { return false }; isClosed = true; return true }
        guard first else { return }
        spectrumTask?.cancel()
        sink.close()
        onClose?()
    }
}

final class NWSink: WSSink, @unchecked Sendable {
    let c: NWConnection
    init(_ c: NWConnection) { self.c = c }
    func send(_ text: String, completion: @escaping @Sendable (Error?) -> Void) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "text", metadata: [meta])
        c.send(content: Data(text.utf8), contentContext: ctx, isComplete: true,
               completion: .contentProcessed { completion($0) })
    }
    func close() { c.cancel() }
}

struct RPCError: Error {
    let code: Int, message: String
    static func params(_ m: String) -> RPCError { RPCError(code: -32602, message: m) }
}

/// JSON-RPC 2.0 přes WebSocket (ws://host:7363/v1).
public final class JSONRPCServer: @unchecked Sendable {
    let app: AppController
    private let host: String, port: UInt16, maxQueue: Int
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "JSONRPCServer")
    private let lock = NSLock()
    private var clients: [UUID: ClientSession] = [:]
    private var eventTask: Task<Void, Never>?

    public init(app: AppController, host: String = "127.0.0.1", port: UInt16 = 7363, maxQueue: Int = 1000) {
        self.app = app; self.host = host; self.port = port; self.maxQueue = maxQueue
    }

    public var clientCount: Int { get async { lock.withLock { clients.count } } }

    public func start() async throws -> UInt16 {
        let l = try makeListener(host: host, port: port, ws: true)
        listener = l
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        let p = try await startListener(l, queue: queue)
        let events = app.events()
        eventTask = Task.detached { [weak self] in
            for await e in events { self?.broadcast(e) }
        }
        return p
    }

    public func stop() {
        listener?.cancel(); listener = nil
        eventTask?.cancel(); eventTask = nil
        for c in lock.withLock({ Array(clients.values) }) { c.close() }
    }

    private func accept(_ c: NWConnection) {
        let session = ClientSession(sink: NWSink(c), maxQueue: maxQueue)
        session.onClose = { [weak self] in self?.lock.withLock { _ = self?.clients.removeValue(forKey: session.id) } }
        lock.withLock { clients[session.id] = session }
        c.stateUpdateHandler = { st in
            if case .failed = st { session.close() }
            if case .cancelled = st { session.close() }
        }
        c.start(queue: queue)
        receive(c, session)
    }

    private func receive(_ c: NWConnection, _ s: ClientSession) {
        c.receiveMessage { [weak self] data, ctx, _, err in
            guard let self else { return }
            if err != nil { s.close(); return }
            let meta = ctx?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            switch meta?.opcode {
            case .text?:
                let text = String(decoding: data ?? Data(), as: UTF8.self)
                Task { await self.handle(text, s) }
            case .close?: s.close(); return
            case .binary?:
                s.sendJSON(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "binary frames not supported"]])
            default: break
            }
            if !s.isClosed { self.receive(c, s) }
        }
    }

    // MARK: Zpracování požadavku

    func handle(_ text: String, _ s: ClientSession) async {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let req = obj as? [String: Any] else {
            s.sendJSON(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]]); return
        }
        let id = req["id"] ?? NSNull()
        guard let method = req["method"] as? String else {
            s.sendJSON(["jsonrpc": "2.0", "id": id, "error": ["code": -32600, "message": "invalid request"]]); return
        }
        let params = req["params"] as? [String: Any] ?? [:]
        do {
            let result = try await dispatch(method, params, s)
            if req["id"] != nil { s.sendJSON(["jsonrpc": "2.0", "id": id, "result": result]) }
        } catch let e as RPCError {
            s.sendJSON(["jsonrpc": "2.0", "id": id, "error": ["code": e.code, "message": e.message]])
        } catch {
            s.sendJSON(["jsonrpc": "2.0", "id": id, "error": ["code": -32603, "message": "\(error)"]])
        }
    }

    // MARK: Události

    func broadcast(_ e: AppEvent) {
        let sessions = lock.withLock { Array(clients.values) }
        guard !sessions.isEmpty else { return }
        var name: String?, params: Any = [:]
        switch e {
        case .engine(.modem(.rxText(let c, let echo))): name = "rx.char"; params = ["char": String(c), "echo": echo]
        case .engine(.state(let st)): name = "engine.state"; params = ["state": st.rawValue]
        case .engine(.modem(.signal(let lvl, let sq))):
            let now = Date()
            for s in sessions where now.timeIntervalSince(s.lastSignal) >= 0.1 {
                s.lastSignal = now; s.notify("signal.level", ["level": lvl, "squelchOpen": sq])
            }
            return
        case .engine(.modem(.tuning(let t))): name = "afc.changed"; params = ["mark": t.mark, "space": t.space]
        case .engine(.modem(.shift(let fig))): name = "fig.changed"; params = ["fig": fig]
        case .engine(.rig(let r)):
            for s in sessions {
                s.notify("rig.status", Self.rigJSON(r))
                if let f = r.frequency { s.notify("rig.freq", ["frequency": f]) }
            }
            return
        case .engine(.error(let err)): name = "error"; params = ["message": "\(err)"]
        case .engine(.pttTimeout): name = "error"; params = ["message": "PTT timeout"]
        case .error(let m): name = "error"; params = ["message": m]
        case .qsoLogged(let r): name = "qso.logged"; params = Self.recordJSON(r)
        case .qsoUpdated(let r): name = "qso.updated"; params = Self.recordJSON(r)
        case .qsoDeleted(let id): name = "qso.deleted"; params = ["id": id.uuidString]
        case .qsoChanged(let q): name = "qso.changed"; params = Self.encodable(q)
        default: return
        }
        guard let name else { return }
        for s in sessions { s.notify(name, params) }
    }

    // MARK: JSON převody

    nonisolated(unsafe) static let iso = ISO8601DateFormatter()   // jen čtení (thread-safe)
    static func encodable<T: Encodable>(_ v: T) -> Any {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        guard let d = try? e.encode(v), let o = try? JSONSerialization.jsonObject(with: d) else { return NSNull() }
        return o
    }
    static func recordJSON(_ r: QSORecord) -> Any {
        var o = encodable(r) as? [String: Any] ?? [:]
        o["band"] = r.band ?? NSNull()
        return o
    }
    static func rigJSON(_ r: RigStatus?) -> [String: Any] {
        ["online": r?.online ?? false, "frequency": r?.frequency ?? NSNull(), "mode": r?.mode ?? NSNull()]
    }
    static func toJSON(_ v: ParameterValue) -> Any {
        switch v { case .bool(let b): return b; case .int(let i): return i; case .double(let d): return d; case .string(let s): return s }
    }
    static func fromJSON(_ a: Any) -> ParameterValue? {
        if let n = a as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            if CFNumberIsFloatType(n) { return .double(n.doubleValue) }
            return .int(n.intValue)
        }
        if let s = a as? String { return .string(s) }
        return nil
    }
    static func descriptorJSON(_ d: ParameterDescriptor) -> [String: Any] {
        var o: [String: Any] = ["id": d.id, "label": d.label, "default": toJSON(d.defaultValue)]
        switch d.kind {
        case .bool: o["type"] = "bool"
        case .int(let r): o["type"] = "int"; o["min"] = r.lowerBound; o["max"] = r.upperBound
        case .double(let r, let u): o["type"] = "double"; o["min"] = r.lowerBound; o["max"] = r.upperBound; o["unit"] = u ?? NSNull()
        case .choice(let c): o["type"] = "choice"; o["options"] = c
        }
        return o
    }
}
