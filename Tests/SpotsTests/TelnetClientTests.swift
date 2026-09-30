import Foundation
import Network
import Testing
@testable import Spots

/// Lokální „cluster“: pošle výzvu, po přihlášení uvítání a spoty; zaznamenává, co klient poslal.
final class FakeCluster: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "FakeCluster")
    private let lock = NSLock()
    private var _received: [String] = []
    private var _connections = 0
    let prompt: String
    let spots: [String]
    let dropAfterSpots: Bool
    /// Odpovědi na příkazy po přihlášení (klíč = příkaz).
    let responses: [String: [String]]
    private(set) var port: UInt16 = 0

    var received: [String] { lock.withLock { _received } }
    var connections: Int { lock.withLock { _connections } }

    init(prompt: String = "login: ", spots: [String], dropAfterSpots: Bool = false, responses: [String: [String]] = [:]) throws {
        self.prompt = prompt; self.spots = spots; self.dropAfterSpots = dropAfterSpots; self.responses = responses
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async {
        listener.newConnectionHandler = { [weak self] c in self?.handle(c) }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let flag = NSLock(); nonisolated(unsafe) var done = false
            listener.stateUpdateHandler = { st in
                if case .ready = st { flag.lock(); defer { flag.unlock() }; if !done { done = true; cont.resume() } }
            }
            listener.start(queue: queue)
        }
        port = listener.port?.rawValue ?? 0
    }

    func stop() { listener.cancel() }

    private func handle(_ c: NWConnection) {
        lock.withLock { _connections += 1 }
        c.start(queue: queue)
        // telnetová vyjednávání + výzva bez konce řádku
        c.send(content: Data([255, 253, 24]) + Data(prompt.utf8), completion: .idempotent)
        nonisolated(unsafe) var buf = ""
        nonisolated(unsafe) var loggedIn = false
        func loop() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, err in
                guard let self else { return }
                if let data { buf += String(decoding: data.filter { $0 != 255 && $0 != 252 && $0 != 24 }, as: UTF8.self) }
                while let r = buf.range(of: "\r\n") {
                    let line = String(buf[..<r.lowerBound]); buf.removeSubrange(..<r.upperBound)
                    self.lock.withLock { self._received.append(line) }
                    if loggedIn, let r = self.responses[line] {
                        c.send(content: Data((r.joined(separator: "\r\n") + "\r\n").utf8), completion: .idempotent)
                    }
                    if !loggedIn {
                        loggedIn = true
                        let text = "Hello, " + line + "\r\n" + self.spots.joined(separator: "\r\n") + "\r\n"
                        c.send(content: Data(text.utf8), completion: .contentProcessed { _ in
                            if self.dropAfterSpots { c.cancel() }
                        })
                    }
                }
                if err == nil && !done { loop() }
            }
        }
        loop()
    }
}

func waitUntil(_ timeout: Double = 5, _ cond: @Sendable () async -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if await cond() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await cond()
}

final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var _spots: [Spot] = [], _states: [TelnetSpotClient.State] = []
    var spots: [Spot] { lock.withLock { _spots } }
    var states: [TelnetSpotClient.State] { lock.withLock { _states } }
    func add(_ s: [Spot]) { lock.withLock { _spots += s } }
    func add(_ s: TelnetSpotClient.State) { lock.withLock { _states.append(s) } }
}

/// Čas HHMMZ aktuální minuty (spoty musí být „čerstvé“, aby je seznam přijal).
func hhmmZ(_ d: Date = Date()) -> String {
    var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
    let p = c.dateComponents([.hour, .minute], from: d)
    return String(format: "%02d%02dZ", p.hour!, p.minute!)
}

func sampleLines(_ t: String = hhmmZ()) -> [String] { [
    "DX de W3LPL-#:    14080.0  DL1ABC       RTTY 25 dB 45 BPS CQ      \(t)",
    "DX de DK9IP-#:    14033.2  UA3XYZ       CW 22 dB 26 WPM CQ        \(t)",
    "garbage line without structure",
    "DX de OK1ABC:      7040.5  JA1XYZ       599 rtty                  \(t) JN79",
] }

@Test func clientLogsInSendsCommandsAndParsesSpots() async throws {
    let server = try FakeCluster(spots: sampleLines())
    await server.start()
    defer { server.stop() }
    let col = Collector()
    var cfg = TelnetSpotClient.Config(host: "127.0.0.1", port: server.port, login: "OK1XOE",
                                      commands: ["set/skimmer", "sh/dx 30"], source: .cluster)
    cfg.initialDelay = 0.05
    // hodiny nastavené tak, aby HHMM ve spotech bylo „dnes“
    let now = Date()
    let client = TelnetSpotClient(config: cfg, now: { now }, onSpots: { col.add($0) }, onState: { col.add($0) })
    await client.start()
    #expect(await waitUntil { col.spots.count >= 3 && server.received.count >= 3 })
    #expect(server.received == ["OK1XOE", "set/skimmer", "sh/dx 30"])
    #expect(col.spots.map(\.call) == ["DL1ABC", "UA3XYZ", "JA1XYZ"])
    #expect(col.states.contains(.connected))
    await client.stop()
}

// Klient nefiltruje módy: „Jen RTTY“ je jen filtr zobrazení (SpotBook.visible), spoty se při příjmu nezahazují.
@Test func clientPassesAllModes() async throws {
    let server = try FakeCluster(prompt: "Please enter your call: ", spots: sampleLines())
    await server.start()
    defer { server.stop() }
    let col = Collector()
    var cfg = TelnetSpotClient.Config(host: "127.0.0.1", port: server.port, login: "OK1XOE", source: .rbn)
    cfg.initialDelay = 0.05
    let client = TelnetSpotClient(config: cfg, onSpots: { col.add($0) }, onState: { col.add($0) })
    await client.start()
    #expect(await waitUntil { col.spots.count >= 3 })
    try await Task.sleep(for: .milliseconds(100))
    #expect(col.spots.map(\.call) == ["DL1ABC", "UA3XYZ", "JA1XYZ"])
    #expect(col.spots.allSatisfy { $0.source == .rbn })
    await client.stop()
}

@Test func clientReconnectsAfterDrop() async throws {
    let server = try FakeCluster(spots: sampleLines(), dropAfterSpots: true)
    await server.start()
    defer { server.stop() }
    let col = Collector()
    var cfg = TelnetSpotClient.Config(host: "127.0.0.1", port: server.port, login: "OK1XOE")
    cfg.initialDelay = 0.05; cfg.maxDelay = 0.2
    let client = TelnetSpotClient(config: cfg, onSpots: { col.add($0) }, onState: { col.add($0) })
    await client.start()
    #expect(await waitUntil { server.connections >= 3 })
    #expect(col.states.contains { if case .reconnecting = $0 { true } else { false } })
    await client.stop()
}

@Test func clientRetriesWhenServerDown() async throws {
    // port, na kterém nikdo neposlouchá: uvolníme ho po startu listeneru
    let server = try FakeCluster(spots: [])
    await server.start()
    let port = server.port
    server.stop()
    try await Task.sleep(for: .milliseconds(200))
    let col = Collector()
    var cfg = TelnetSpotClient.Config(host: "127.0.0.1", port: port, login: "OK1XOE")
    cfg.initialDelay = 0.05; cfg.maxDelay = 0.1
    let client = TelnetSpotClient(config: cfg, onSpots: { col.add($0) }, onState: { col.add($0) })
    await client.start()
    #expect(await waitUntil { col.states.filter { if case .reconnecting = $0 { true } else { false } }.count >= 2 })
    await client.stop()
}

@Test func clientWithoutCallFails() async {
    let col = Collector()
    let client = TelnetSpotClient(config: .init(host: "127.0.0.1", port: 1, login: "  "), onSpots: { col.add($0) }, onState: { col.add($0) })
    await client.start()
    #expect(col.states == [.failed("config")])
}

@MainActor @Test func feedCollectsFromBothSourcesAndDedupes() async throws {
    let cluster = try FakeCluster(spots: [sampleLines()[0]])
    let rbn = try FakeCluster(prompt: "Please enter your call: ",
                              spots: [sampleLines()[0], sampleLines()[1]])
    await cluster.start(); await rbn.start()
    defer { cluster.stop(); rbn.stop() }
    let now = Date()
    let feed = SpotFeed(clock: { now })
    var cfg = SpotFeedConfig(call: "OK1XOE", cluster: SpotEndpoint(host: "127.0.0.1", port: cluster.port),
                             rbn: SpotEndpoint(host: "127.0.0.1", port: rbn.port), filter: .all)
    cfg.clientTuning = (0.05, 0.1)
    feed.start(cfg)
    #expect(await waitUntil { await MainActor.run { feed.book.count >= 2 && feed.clusterState == .connected && feed.rbnState == .connected } })
    let v = feed.visible
    #expect(v.map(\.call).sorted() == ["DL1ABC", "UA3XYZ"])              // DL1ABC jen jednou
    feed.filter.modes = [.rtty]
    #expect(feed.visible.map(\.call) == ["DL1ABC"])
    feed.filter.bands = ["40m"]
    #expect(feed.visible.isEmpty)
    feed.stop()
    #expect(feed.clusterState == .off && !feed.isRunning)
}
