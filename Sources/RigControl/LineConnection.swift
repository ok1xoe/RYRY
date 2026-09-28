// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Network

/// TCP spojení s řádkovým protokolem (request → N řádků odpovědi) s timeoutem.
public actor LineConnection {
    private let host: String
    private let port: UInt16
    private let timeout: Duration
    private var connection: NWConnection?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "LineConnection")

    public init(host: String, port: UInt16, timeout: Duration = .seconds(2)) {
        self.host = host; self.port = port; self.timeout = timeout
    }

    public var isOpen: Bool { connection != nil }

    public func open() async throws {
        if connection != nil { return }
        guard let p = NWEndpoint.Port(rawValue: port) else { throw RigError.offline }
        let c = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        let q = queue
        let ready: Bool = try await withTimeout(timeout) {
            await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                let once = OnceFlag()
                c.stateUpdateHandler = { st in
                    switch st {
                    case .ready: if once.first() { cont.resume(returning: true) }
                    case .failed, .cancelled, .waiting: if once.first() { cont.resume(returning: false) }
                    default: break
                    }
                }
                c.start(queue: q)
            }
        } onTimeout: { c.cancel() }
        guard ready else { c.cancel(); throw RigError.offline }
        c.stateUpdateHandler = nil
        connection = c
        buffer.removeAll()
    }

    public func close() {
        connection?.cancel()
        connection = nil
        buffer.removeAll()
    }

    /// Pošle řádek a přečte `responseLines` řádků odpovědi. Při výpadku spojení zavře a hodí `.offline`.
    public func request(_ line: String, responseLines: Int) async throws -> [String] {
        if connection == nil { try await open() }
        guard let c = connection else { throw RigError.offline }
        do {
            try await send(c, Data((line + "\n").utf8))
            var lines: [String] = []
            while lines.count < responseLines {
                if let r = buffer.firstIndex(of: 0x0A) {
                    let l = String(decoding: buffer[buffer.startIndex..<r], as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    buffer.removeSubrange(buffer.startIndex...r)
                    lines.append(l)
                    // chybová odpověď místo dat (RPRT -n) ukončí čtení
                    if l.hasPrefix("RPRT ") { break }
                    continue
                }
                let chunk = try await receive(c)
                buffer.append(chunk)
            }
            return lines
        } catch let e as RigError {
            if e != .timeout { close() } else { close() }   // po timeoutu je stav proudu neznámý
            throw e
        }
    }

    private func send(_ c: NWConnection, _ data: Data) async throws {
        let err: NWError? = await withCheckedContinuation { cont in
            c.send(content: data, completion: .contentProcessed { cont.resume(returning: $0) })
        }
        if err != nil { throw RigError.offline }
    }

    private func receive(_ c: NWConnection) async throws -> Data {
        try await withTimeout(timeout) {
            let r: Result<Data, RigError> = await withCheckedContinuation { cont in
                c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, done, err in
                    if let data, !data.isEmpty { cont.resume(returning: .success(data)) }
                    else if err != nil || done { cont.resume(returning: .failure(.offline)) }
                    else { cont.resume(returning: .failure(.offline)) }
                }
            }
            return try r.get()
        } onTimeout: { c.cancel() }
    }
}

final class OnceFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func first() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
}

/// Spustí operaci s timeoutem; po vypršení zavolá `onTimeout` (který má operaci probudit) a hodí `.timeout`.
func withTimeout<T: Sendable>(_ d: Duration, _ op: @escaping @Sendable () async throws -> T,
                              onTimeout: @escaping @Sendable () -> Void) async throws -> T {
    let timedOut = OnceFlag()
    let timer = Task {
        try? await Task.sleep(for: d)
        if !Task.isCancelled, timedOut.first() { onTimeout() }
    }
    defer { timer.cancel() }
    do {
        let v = try await op()
        if !timedOut.first() { throw RigError.timeout }
        return v
    } catch {
        if !timedOut.first() { throw RigError.timeout }
        throw error
    }
}
