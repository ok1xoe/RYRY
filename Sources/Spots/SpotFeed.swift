// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Observation

public struct SpotEndpoint: Sendable, Equatable {
    public var host: String
    public var port: UInt16
    public var commands: [String]
    public init(host: String, port: UInt16, commands: [String] = []) { self.host = host; self.port = port; self.commands = commands }
}

public struct SpotFeedConfig: Sendable, Equatable {
    public var call: String
    public var cluster: SpotEndpoint?
    public var rbn: SpotEndpoint?
    /// Initial state of the display filter (bands + modes; does not filter reception, no effect on QSOs, so not in `==`).
    public var filter = SpotFilter()
    public var maxAgeMinutes = 30
    public var clientTuning: (initialDelay: Double, maxDelay: Double)?
    /// Wait for the login prompt (s); nil = the client's default (tests shorten it).
    public var loginWait: Double?
    public init(call: String, cluster: SpotEndpoint? = nil, rbn: SpotEndpoint? = nil,
                filter: SpotFilter = SpotFilter(), maxAgeMinutes: Int = 30) {
        self.call = call; self.cluster = cluster; self.rbn = rbn; self.filter = filter; self.maxAgeMinutes = maxAgeMinutes
    }
    public static func == (a: Self, b: Self) -> Bool {
        a.call == b.call && a.cluster == b.cluster && a.rbn == b.rbn && a.maxAgeMinutes == b.maxAgeMinutes
    }
}

/// Spot state for the UI: list + state of both connections. The network runs in actors, spots only arrive here in batches.
@MainActor @Observable
public final class SpotFeed {
    public private(set) var book = SpotBook()
    public private(set) var clusterState = TelnetSpotClient.State.off
    public private(set) var rbnState = TelnetSpotClient.State.off
    /// The DX cluster accepts commands (logged in, or a server with no prompt after the greeting) – command buttons only then.
    public var clusterCommandsReady: Bool { clusterLoggedIn && clusterState == .connected }
    /// The client reports readiness for commands (after login / a greeting without a prompt).
    private var clusterLoggedIn = false
    public private(set) var config = SpotFeedConfig(call: "")
    /// Display filter (checked bands and mode groups) – display only (list, band map, labels in the waterfall);
    /// spots of all bands and modes are stored.
    public var filter = SpotFilter()
    /// The last ~500 non-spot lines from the DX cluster (command replies, the greeting) and the commands sent (`> command`).
    public private(set) var consoleLines: [String] = []
    public static let consoleMax = 500
    /// Called for every newly added spot (a call + band that was not in the list yet).
    @ObservationIgnored public var onNewSpot: (@MainActor (Spot) -> Void)?

    /// Number of starts (`start`) – a test that changing the filter does not reconnect.
    @ObservationIgnored public private(set) var starts = 0
    @ObservationIgnored private var clients: [TelnetSpotClient] = []
    @ObservationIgnored private var clusterClient: TelnetSpotClient?
    @ObservationIgnored private var pruneTask: Task<Void, Never>?
    @ObservationIgnored private let clock: @Sendable () -> Date

    public init(clock: @escaping @Sendable () -> Date = { Date() }) { self.clock = clock }

    public var maxAge: TimeInterval { TimeInterval(config.maxAgeMinutes) * 60 }
    public var visible: [Spot] { book.visible(filter) }
    public var isRunning: Bool { !clients.isEmpty }

    /// Stops the old clients and starts those the configuration enables. The spot list is kept.
    public func start(_ cfg: SpotFeedConfig) {
        stop()
        starts += 1
        config = cfg
        filter = cfg.filter
        book = SpotBook(maxCount: SpotBook.absoluteMax)
        clusterState = .off; rbnState = .off; clusterLoggedIn = false
        consoleLines = []
        let clock = self.clock
        func make(_ e: SpotEndpoint, _ src: SpotSource) -> TelnetSpotClient {
            var c = TelnetSpotClient.Config(host: e.host, port: e.port, login: cfg.call, commands: e.commands, source: src)
            if let t = cfg.clientTuning { c.initialDelay = t.initialDelay; c.maxDelay = t.maxDelay }
            if let w = cfg.loginWait { c.loginWait = w }
            var lineSink: (@Sendable ([String]) -> Void)?
            var readySink: (@Sendable (Bool) -> Void)?
            if src == .cluster {
                lineSink = { [weak self] lines in Task { @MainActor in self?.appendConsole(lines) } }
                readySink = { [weak self] r in Task { @MainActor in self?.setCommandsReady(r) } }
            }
            return TelnetSpotClient(config: c, now: clock,
                onSpots: { [weak self] spots in Task { @MainActor in self?.ingest(spots) } },
                onState: { [weak self] st in Task { @MainActor in self?.setState(src, st) } },
                onLines: lineSink, onCommandReady: readySink)
        }
        if let e = cfg.cluster { let c = make(e, .cluster); clusterClient = c; clients.append(c) }
        if let e = cfg.rbn { clients.append(make(e, .rbn)) }
        let started = clients
        Task { for c in started { await c.start() } }
        pruneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                self?.prune()
            }
        }
    }

    public func stop() {
        let old = clients
        clients = []; clusterClient = nil
        pruneTask?.cancel(); pruneTask = nil
        Task { for c in old { await c.stop() } }
        clusterState = .off; rbnState = .off; clusterLoggedIn = false
    }

    /// Sends a command to the DX cluster (not RBN) over the existing connection: `command\r\n`; none → `ClusterCommandError`.
    public func sendClusterCommand(_ line: String) async throws {
        let clean = try ClusterCommand.validate(line)
        guard let c = clusterClient, clusterCommandsReady else { throw ClusterCommandError.notConnected }
        try await c.sendLine(clean)
        appendConsole(["> " + clean])
    }

    func appendConsole(_ lines: [String]) {
        guard isRunning else { return }
        consoleLines += lines.map { String($0.prefix(500)) }
        if consoleLines.count > Self.consoleMax { consoleLines.removeFirst(consoleLines.count - Self.consoleMax) }
    }

    public func clearConsole() { consoleLines = [] }

    func ingest(_ spots: [Spot]) {
        guard isRunning else { return }
        let now = clock()
        for s in spots {
            let isNew = book.byID[s.id] == nil
            if book.add(s, now: now, maxAge: maxAge), isNew { onNewSpot?(s) }
        }
    }

    private func setState(_ src: SpotSource, _ st: TelnetSpotClient.State) {
        guard isRunning else { return }
        switch src { case .cluster: clusterState = st; case .rbn: rbnState = st }
    }

    private func setCommandsReady(_ r: Bool) {
        guard isRunning else { return }
        clusterLoggedIn = r
    }

    public func prune() { book.prune(now: clock(), maxAge: maxAge) }
}
