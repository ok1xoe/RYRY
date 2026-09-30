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
    /// Počáteční stav filtru zobrazení (pásma + módy; příjem nefiltruje, na spojení nemá vliv, proto není v `==`).
    public var filter = SpotFilter()
    public var maxAgeMinutes = 30
    public var clientTuning: (initialDelay: Double, maxDelay: Double)?
    /// Čekání na výzvu k přihlášení (s); nil = výchozí klienta (testy zkracují).
    public var loginWait: Double?
    public init(call: String, cluster: SpotEndpoint? = nil, rbn: SpotEndpoint? = nil,
                filter: SpotFilter = SpotFilter(), maxAgeMinutes: Int = 30) {
        self.call = call; self.cluster = cluster; self.rbn = rbn; self.filter = filter; self.maxAgeMinutes = maxAgeMinutes
    }
    public static func == (a: Self, b: Self) -> Bool {
        a.call == b.call && a.cluster == b.cluster && a.rbn == b.rbn && a.maxAgeMinutes == b.maxAgeMinutes
    }
}

/// Stav spotů pro UI: seznam + stav obou spojení. Síť běží v aktorech, sem se spoty jen předávají po dávkách.
@MainActor @Observable
public final class SpotFeed {
    public private(set) var book = SpotBook()
    public private(set) var clusterState = TelnetSpotClient.State.off
    public private(set) var rbnState = TelnetSpotClient.State.off
    /// DX cluster přijímá příkazy (přihlášeno, nebo server bez výzvy po uvítání) – tlačítka příkazů jen tehdy.
    public var clusterCommandsReady: Bool { clusterLoggedIn && clusterState == .connected }
    /// Klient hlásí připravenost na příkazy (po přihlášení / uvítání bez výzvy).
    private var clusterLoggedIn = false
    public private(set) var config = SpotFeedConfig(call: "")
    /// Filtr zobrazení (zaškrtnutá pásma a skupiny módů) – jen zobrazení (seznam, band mapa, štítky);
    /// ukládají se spoty všech pásem a módů.
    public var filter = SpotFilter()
    /// Posledních ~500 ne-spotových řádků z DX clusteru (odpovědi na příkazy, uvítání) a odeslané příkazy (`> příkaz`).
    public private(set) var consoleLines: [String] = []
    public static let consoleMax = 500
    /// Volá se pro každý nově přidaný spot (značka + pásmo, které v seznamu ještě nebylo).
    @ObservationIgnored public var onNewSpot: (@MainActor (Spot) -> Void)?

    /// Počet spuštění (`start`) – test, že změna filtru nepřipojuje znovu.
    @ObservationIgnored public private(set) var starts = 0
    @ObservationIgnored private var clients: [TelnetSpotClient] = []
    @ObservationIgnored private var clusterClient: TelnetSpotClient?
    @ObservationIgnored private var pruneTask: Task<Void, Never>?
    @ObservationIgnored private let clock: @Sendable () -> Date

    public init(clock: @escaping @Sendable () -> Date = { Date() }) { self.clock = clock }

    public var maxAge: TimeInterval { TimeInterval(config.maxAgeMinutes) * 60 }
    public var visible: [Spot] { book.visible(filter) }
    public var isRunning: Bool { !clients.isEmpty }

    /// Zastaví staré klienty a spustí ty, které konfigurace zapíná. Seznam spotů zůstává.
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

    /// Pošle příkaz do DX clusteru (ne do RBN) přes existující spojení: `příkaz\r\n`. Bez spojení vyhodí `ClusterCommandError`.
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
