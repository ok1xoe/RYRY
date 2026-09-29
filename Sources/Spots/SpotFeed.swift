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
    public var rttyOnly = true
    public var maxAgeMinutes = 30
    public var clientTuning: (initialDelay: Double, maxDelay: Double)?
    public init(call: String, cluster: SpotEndpoint? = nil, rbn: SpotEndpoint? = nil, rttyOnly: Bool = true, maxAgeMinutes: Int = 30) {
        self.call = call; self.cluster = cluster; self.rbn = rbn; self.rttyOnly = rttyOnly; self.maxAgeMinutes = maxAgeMinutes
    }
    public static func == (a: Self, b: Self) -> Bool {
        a.call == b.call && a.cluster == b.cluster && a.rbn == b.rbn && a.rttyOnly == b.rttyOnly && a.maxAgeMinutes == b.maxAgeMinutes
    }
}

/// Stav spotů pro UI: seznam + stav obou spojení. Síť běží v aktorech, sem se spoty jen předávají po dávkách.
@MainActor @Observable
public final class SpotFeed {
    public private(set) var book = SpotBook()
    public private(set) var clusterState = TelnetSpotClient.State.off
    public private(set) var rbnState = TelnetSpotClient.State.off
    public private(set) var config = SpotFeedConfig(call: "")
    /// Filtr pásma v okně (např. „20m“); nil = všechna.
    public var bandFilter: String?
    /// Zobrazit jen RTTY (filtr zobrazení; příjem u klienta se řídí `config.rttyOnly`).
    public var rttyOnly = true
    /// Volá se pro každý nově přidaný spot (značka + pásmo, které v seznamu ještě nebylo).
    @ObservationIgnored public var onNewSpot: (@MainActor (Spot) -> Void)?

    @ObservationIgnored private var clients: [TelnetSpotClient] = []
    @ObservationIgnored private var pruneTask: Task<Void, Never>?
    @ObservationIgnored private let clock: @Sendable () -> Date

    public init(clock: @escaping @Sendable () -> Date = { Date() }) { self.clock = clock }

    public var maxAge: TimeInterval { TimeInterval(config.maxAgeMinutes) * 60 }
    public var visible: [Spot] { book.visible(rttyOnly: rttyOnly, band: bandFilter) }
    public var isRunning: Bool { !clients.isEmpty }

    /// Pásma, která se ve spotech vyskytují (pro výběr filtru).
    public var bands: [String] {
        let order = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"]
        let present = Set(book.byID.values.compactMap(\.band))
        return order.filter(present.contains) + present.subtracting(order).sorted()
    }

    /// Zastaví staré klienty a spustí ty, které konfigurace zapíná. Seznam spotů zůstává.
    public func start(_ cfg: SpotFeedConfig) {
        stop()
        config = cfg
        rttyOnly = cfg.rttyOnly
        book = SpotBook(maxCount: SpotBook.absoluteMax)
        clusterState = .off; rbnState = .off
        let clock = self.clock
        func make(_ e: SpotEndpoint, _ src: SpotSource) -> TelnetSpotClient {
            var c = TelnetSpotClient.Config(host: e.host, port: e.port, login: cfg.call, commands: e.commands,
                                            source: src, rttyOnly: cfg.rttyOnly)
            if let t = cfg.clientTuning { c.initialDelay = t.initialDelay; c.maxDelay = t.maxDelay }
            return TelnetSpotClient(config: c, now: clock,
                onSpots: { [weak self] spots in Task { @MainActor in self?.ingest(spots) } },
                onState: { [weak self] st in Task { @MainActor in self?.setState(src, st) } })
        }
        if let e = cfg.cluster { clients.append(make(e, .cluster)) }
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
        clients = []
        pruneTask?.cancel(); pruneTask = nil
        Task { for c in old { await c.stop() } }
        clusterState = .off; rbnState = .off
    }

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

    public func prune() { book.prune(now: clock(), maxAge: maxAge) }
}
