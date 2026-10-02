// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Foundation
import Network

/// Telnet client for a DX cluster / RBN: logs in with the call, sends commands, reads spots, reconnects after an outage
/// with a growing delay. Everything runs off the main thread; spots are handed over in batches (one batch = one block).
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
        public var connectTimeout: Duration = .seconds(10)
        public var initialDelay: Double = 2
        public var maxDelay: Double = 120
        /// A connection that has lasted at least this long resets the delay.
        public var stableAfter: Double = 15
        /// How long after connecting to wait for the login prompt; a server with no prompt (only a greeting) then accepts
        /// commands without a login – at the earliest after the first data received.
        public var loginWait: Double = 5
        public init(host: String, port: UInt16, login: String, commands: [String] = [], source: SpotSource = .cluster) {
            self.host = host; self.port = port; self.login = login; self.commands = commands; self.source = source
        }
    }

    private let config: Config
    private let onSpots: @Sendable ([Spot]) -> Void
    private let onState: @Sendable (State) -> Void
    private let onLines: (@Sendable ([String]) -> Void)?
    /// Change of command readiness (true = `sendLine` may be called: after login, or without a prompt after the greeting).
    private let onCommandReady: (@Sendable (Bool) -> Void)?
    private let now: @Sendable () -> Date
    private var task: Task<Void, Never>?
    private var connection: NWConnection?
    /// The connection commands can be sent to (after login); otherwise nil.
    private var sendable: NWConnection? {
        didSet { if (oldValue == nil) != (sendable == nil) { onCommandReady?(sendable != nil) } }
    }
    /// State of the current connection for deciding "a server without a login prompt".
    private var loginSeen = false, gotText = false, loginWaitOver = false
    private let queue = DispatchQueue(label: "TelnetSpotClient")

    public init(config: Config, now: @escaping @Sendable () -> Date = { Date() },
                onSpots: @escaping @Sendable ([Spot]) -> Void, onState: @escaping @Sendable (State) -> Void,
                onLines: (@Sendable ([String]) -> Void)? = nil, onCommandReady: (@Sendable (Bool) -> Void)? = nil) {
        self.config = config; self.now = now; self.onSpots = onSpots; self.onState = onState; self.onLines = onLines
        self.onCommandReady = onCommandReady
    }

    /// Sends a line to the server (`line\r\n`) after login; no connection → `.notConnected`. Must be valid (`ClusterCommand`).
    public func sendLine(_ line: String) async throws {
        let clean = try ClusterCommand.validate(line)
        guard let c = sendable, c.state == .ready else { throw ClusterCommandError.notConnected }
        if let e = await Self.sendChecked(c, Data((clean + "\r\n").utf8)) { throw ClusterCommandError.sendFailed("\(e)") }
    }

    public func start() {
        guard task == nil else { return }
        let login = config.login.trimmingCharacters(in: .whitespaces)
        guard !login.isEmpty, config.port > 0, !config.host.isEmpty else { onState(.failed("config")); return }
        task = Task { await self.run(login: login) }
    }

    public func stop() {
        task?.cancel(); task = nil
        connection?.cancel(); connection = nil; sendable = nil
    }

    // MARK: Connection loop

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

    /// A single connection; returns true if it was established.
    private func session(login: String) async -> Bool {
        guard let port = NWEndpoint.Port(rawValue: config.port) else { return false }
        let c = NWConnection(host: NWEndpoint.Host(config.host), port: port, using: .tcp)
        connection = c
        defer { c.cancel(); if connection === c { connection = nil }; if sendable === c { sendable = nil } }
        let timer = Task { [timeout = config.connectTimeout] in
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { c.cancel() }
        }
        let ready = await Self.waitReady(c, queue: queue)
        timer.cancel()
        guard ready, !Task.isCancelled else { return false }
        onState(.connected)
        loginSeen = false; gotText = false; loginWaitOver = false
        let wait = Task { [weak self, loginWait = config.loginWait] in
            try? await Task.sleep(for: .seconds(loginWait))
            if !Task.isCancelled { await self?.loginWaitEnded(c) }
        }
        defer { wait.cancel() }

        var filter = TelnetFilter(), splitter = LineSplitter()
        var loginSent = false, commandsSent = false
        while !Task.isCancelled {
            guard let chunk = try? await Self.receive(c) else { break }
            if chunk.isEmpty { continue }
            let (text, reply) = filter.process(chunk)
            if !reply.isEmpty { await Self.send(c, reply) }
            let lines = splitter.feed(text)
            if !text.isEmpty { gotText = true }
            if loginSent, !commandsSent, !(text.isEmpty) {
                commandsSent = true
                try? await Task.sleep(for: .milliseconds(300))
                for cmd in config.commands where !cmd.trimmingCharacters(in: .whitespaces).isEmpty {
                    await Self.send(c, Data((cmd + "\r\n").utf8))
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
            if !loginSent, (lines + [splitter.pending]).contains(where: TelnetPrompt.isLogin) {
                loginSent = true; loginSeen = true
                await Self.send(c, Data((login + "\r\n").utf8))
                sendable = c
            }
            if !loginSeen, loginWaitOver, gotText, sendable == nil { sendable = c }      // server without a login prompt
            let t = now()
            var spots: [Spot] = []
            var other: [String] = []
            for l in lines {
                guard let s = SpotParser.parse(l, now: t, source: config.source) else {
                    if !l.trimmingCharacters(in: .whitespaces).isEmpty { other.append(l) }
                    continue
                }
                spots.append(s)
            }
            if !spots.isEmpty { onSpots(spots) }
            if !other.isEmpty { onLines?(other) }
        }
        return true
    }

    /// The wait for the login prompt has elapsed: without a prompt but with a greeting, commands can already be sent.
    private func loginWaitEnded(_ c: NWConnection) {
        guard connection === c else { return }
        loginWaitOver = true
        if !loginSeen, gotText, sendable == nil { sendable = c }
    }

    // MARK: NWConnection helpers

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

    /// The next block of data; empty = nothing (retry), an error or the end of the connection = throw.
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
        _ = await sendChecked(c, data)
    }

    /// Sends the data; returns a connection error, nil = sent.
    private static func sendChecked(_ c: NWConnection, _ data: Data) async -> NWError? {
        await withCheckedContinuation { (cont: CheckedContinuation<NWError?, Never>) in
            c.send(content: data, completion: .contentProcessed { e in cont.resume(returning: e) })
        }
    }
}
