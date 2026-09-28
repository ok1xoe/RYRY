import Foundation
import Network

/// Falešný rigctld (výchozí protokol) pro testy. Běží na náhodném portu na 127.0.0.1.
final class FakeRigctld: @unchecked Sendable {
    enum Mode { case normal, rejectAll, silent, garbageFreq }
    private let queue = DispatchQueue(label: "FakeRigctld")
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private(set) var port: UInt16 = 0
    var mode: Mode = .normal
    var freq = 14_080_000.0
    var rigMode = "PKTUSB"
    var ptt = false
    var replyDelayMs = 0          // zpoždění odpovědi (odhalí souběžné požadavky)
    private(set) var commands: [String] = []

    func start() async throws {
        let l = try NWListener(using: .tcp, on: .any)
        listener = l
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let once = Once()
            l.stateUpdateHandler = { st in
                if case .ready = st, once.first() { cont.resume() }
            }
            l.start(queue: queue)
        }
        port = l.port?.rawValue ?? 0
    }

    /// Restartuje na stejném portu (simulace znovuspuštění rigctld).
    func restart() async throws {
        let p = port
        stop()
        try await Task.sleep(for: .milliseconds(50))
        let l = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: p)!)
        listener = l
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let once = Once()
            l.stateUpdateHandler = { st in
                if case .ready = st, once.first() { cont.resume() }
            }
            l.start(queue: queue)
        }
    }

    func dropConnections() { queue.sync { connections.forEach { $0.cancel() }; connections.removeAll() } }

    func stop() {
        listener?.cancel(); listener = nil
        dropConnections()
    }

    private func accept(_ c: NWConnection) {
        connections.append(c)
        c.start(queue: queue)
        receive(c, buffer: "")
    }

    private func receive(_ c: NWConnection, buffer: String) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let data { buf += String(decoding: data, as: UTF8.self) }
            while let r = buf.range(of: "\n") {
                let line = String(buf[..<r.lowerBound])
                buf.removeSubrange(..<r.upperBound)
                self.handle(line, c)
            }
            if done || err != nil { c.cancel(); return }
            self.receive(c, buffer: buf)
        }
    }

    private func handle(_ line: String, _ c: NWConnection) {
        commands.append(line)
        if mode == .silent { return }
        let parts = line.split(separator: " ").map(String.init)
        var reply: String
        if mode == .rejectAll {
            reply = "RPRT -1\n"
        } else {
            switch parts.first {
            case "f": reply = mode == .garbageFreq ? "abc\n" : "\(Int(freq))\n"
            case "F": freq = Double(parts[1]) ?? freq; reply = "RPRT 0\n"
            case "m": reply = "\(rigMode)\n2400\n"
            case "M": rigMode = parts[1]; reply = "RPRT 0\n"
            case "t": reply = ptt ? "1\n" : "0\n"
            case "T": ptt = parts[1] == "1"; reply = "RPRT 0\n"
            default: reply = "RPRT -11\n"
            }
        }
        if replyDelayMs > 0 {
            queue.asyncAfter(deadline: .now() + .milliseconds(Int.random(in: 0...replyDelayMs))) {
                c.send(content: Data(reply.utf8), completion: .contentProcessed { _ in })
            }
        } else {
            c.send(content: Data(reply.utf8), completion: .contentProcessed { _ in })
        }
    }
}

final class Once: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func first() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}
