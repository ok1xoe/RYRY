// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Network

/// Telnet klient DX clusteru / RBN: přihlásí se značkou, pošle příkazy, čte spoty, po výpadku se znovu připojuje
/// s rostoucí prodlevou. Vše běží mimo hlavní vlákno; spoty se předávají po dávkách (jedna dávka = jeden příchozí blok).
public actor TelnetSpotClient {
    public enum State: Sendable, Equatable {
        case off, connecting, connected
        case reconnecting(seconds: Double)
        case failed(String)
    }

    public struct Config: Sendable, Equatable {
        public var host: String
        public var port: UInt16
        public var login: String
        public var commands: [String]
        public var source: SpotSource
        public var rttyOnly: Bool
        public var connectTimeout: Duration = .seconds(10)
        public var initialDelay: Double = 2
        public var maxDelay: Double = 120
        /// Spojení, které vydrželo aspoň tak dlouho, vynuluje prodlevu.
        public var stableAfter: Double = 15
        public init(host: String, port: UInt16, login: String, commands: [String] = [], source: SpotSource = .cluster,
                    rttyOnly: Bool = false) {
            self.host = host; self.port = port; self.login = login; self.commands = commands
            self.source = source; self.rttyOnly = rttyOnly
        }
    }

    private let config: Config
    private let onSpots: @Sendable ([Spot]) -> Void
    private let onState: @Sendable (State) -> Void
    private let now: @Sendable () -> Date
    private var task: Task<Void, Never>?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "TelnetSpotClient")

    public init(config: Config, now: @escaping @Sendable () -> Date = { Date() },
                onSpots: @escaping @Sendable ([Spot]) -> Void, onState: @escaping @Sendable (State) -> Void) {
        self.config = config; self.now = now; self.onSpots = onSpots; self.onState = onState
    }

    public func start() {
        guard task == nil else { return }
        let login = config.login.trimmingCharacters(in: .whitespaces)
        guard !login.isEmpty, config.port > 0, !config.host.isEmpty else { onState(.failed("config")); return }
        task = Task { await self.run(login: login) }
    }

    public func stop() {
        task?.cancel(); task = nil
        connection?.cancel(); connection = nil
    }

    // MARK: Smyčka připojení

    private func run(login: String) async {
        var delay = config.initialDelay
        while !Task.isCancelled {
            onState(.connecting)
            let began = Date()
            let connected = await session(login: login)
            if Task.isCancelled { return }
            if connected, Date().timeIntervalSince(began) >= config.stableAfter { delay = config.initialDelay }
            onState(.reconnecting(seconds: delay))
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, config.maxDelay)
        }
    }

    /// Jedno spojení; vrací true, pokud se podařilo navázat.
    private func session(login: String) async -> Bool {
        guard let port = NWEndpoint.Port(rawValue: config.port) else { return false }
        let c = NWConnection(host: NWEndpoint.Host(config.host), port: port, using: .tcp)
        connection = c
        defer { c.cancel(); if connection === c { connection = nil } }
        let timer = Task { [timeout = config.connectTimeout] in
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { c.cancel() }
        }
        let ready = await Self.waitReady(c, queue: queue)
        timer.cancel()
        guard ready, !Task.isCancelled else { return false }
        onState(.connected)

        var filter = TelnetFilter(), splitter = LineSplitter()
        var loginSent = false, commandsSent = false
        while !Task.isCancelled {
            guard let chunk = try? await Self.receive(c) else { break }
            if chunk.isEmpty { continue }
            let (text, reply) = filter.process(chunk)
            if !reply.isEmpty { await Self.send(c, reply) }
            let lines = splitter.feed(text)
            if loginSent, !commandsSent, !(text.isEmpty) {
                commandsSent = true
                try? await Task.sleep(for: .milliseconds(300))
                for cmd in config.commands where !cmd.trimmingCharacters(in: .whitespaces).isEmpty {
                    await Self.send(c, Data((cmd + "\r\n").utf8))
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
            if !loginSent, (lines + [splitter.pending]).contains(where: TelnetPrompt.isLogin) {
                loginSent = true
                await Self.send(c, Data((login + "\r\n").utf8))
            }
            let t = now()
            var spots: [Spot] = []
            for l in lines {
                guard let s = SpotParser.parse(l, now: t, source: config.source) else { continue }
                if config.rttyOnly, !s.isRTTY { continue }
                spots.append(s)
            }
            if !spots.isEmpty { onSpots(spots) }
        }
        return true
    }

    // MARK: NWConnection pomocníci

    private final class Once: @unchecked Sendable {
        private let lock = NSLock(); private var done = false
        func first() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
    }

    private static func waitReady(_ c: NWConnection, queue: DispatchQueue) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let once = Once()
            c.stateUpdateHandler = { st in
                switch st {
                case .ready: if once.first() { cont.resume(returning: true) }
                case .failed, .cancelled, .waiting: if once.first() { cont.resume(returning: false) }
                default: break
                }
            }
            c.start(queue: queue)
        }
    }

    /// Další blok dat; prázdný = nic (znovu), chyba nebo konec spojení = throw.
    private static func receive(_ c: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, isComplete, error in
                if let error { cont.resume(throwing: error) }
                else if let data, !data.isEmpty { cont.resume(returning: data) }
                else if isComplete { cont.resume(throwing: NWError.posix(.ECONNRESET)) }
                else { cont.resume(returning: Data()) }
            }
        }
    }

    private static func send(_ c: NWConnection, _ data: Data) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            c.send(content: data, completion: .contentProcessed { _ in cont.resume() })
        }
    }
}
