import Foundation
import Testing
@testable import Spots

// Review plan18: kontrola řádků pro cluster, spot bez značky/kmitočtu, připravenost příkazů až po přihlášení.

@Test func clusterCommandRejectsC1AndUnicodeLineSeparators() throws {
    for bad in ["sh/dx\u{85}30", "sh/dx\u{80}", "sh/dx\u{9F}", "sh/dx\u{2028}set/skimmer", "sh/dx\u{2029}"] {
        #expect(throws: ClusterCommandError.controlCharacter) { try ClusterCommand.validate(bad) }
    }
    #expect(try ClusterCommand.validate("talk OK1ABC Ahoj, díky ÄÖÜ") == "talk OK1ABC Ahoj, díky ÄÖÜ")
}

@Test func dxSpotCommandNeedsCallAndFrequency() throws {
    #expect(throws: ClusterCommandError.incompleteSpot) { try ClusterCommand.validate("dx 14085.0 RTTY") }     // %c prázdné
    #expect(throws: ClusterCommandError.incompleteSpot) { try ClusterCommand.validate("dx  DL1ABC RTTY") }    // %k prázdné
    #expect(throws: ClusterCommandError.incompleteSpot) { try ClusterCommand.validate("DX 14085") }
    #expect(try ClusterCommand.validate("DX 14085.0 DL1ABC RTTY") == "DX 14085.0 DL1ABC RTTY")
    #expect(try ClusterCommand.validate("dx DL1ABC 14085") == "dx DL1ABC 14085")
    #expect(try ClusterCommand.validate("dxstat") == "dxstat")                           // jiný příkaz
    #expect(try ClusterCommand.validate("sh/dx 30") == "sh/dx 30")
}

/// Cluster bez výzvy k přihlášení: posílá jen uvítání (nebo nic).
@Test @MainActor func commandsReadyOnlyAfterLoginOrGreetingWithoutPrompt() async throws {
    // server nepošle nic kromě telnetového vyjednávání: TCP je připojené, ale příkazy se ještě posílat nesmí
    let silent = try FakeCluster(prompt: "", spots: [])
    await silent.start()
    defer { silent.stop() }
    let feed = SpotFeed()
    var cfg = SpotFeedConfig(call: "OK1XOE", cluster: SpotEndpoint(host: "127.0.0.1", port: silent.port))
    cfg.clientTuning = (0.05, 0.1)
    cfg.loginWait = 0.2
    feed.start(cfg)
    #expect(await waitUntil { await MainActor.run { feed.clusterState == .connected } })
    #expect(!feed.clusterCommandsReady)
    try await Task.sleep(for: .milliseconds(400))
    #expect(!feed.clusterCommandsReady)
    await #expect(throws: ClusterCommandError.notConnected) { try await feed.sendClusterCommand("sh/dx") }
    feed.stop()

    // uvítání bez výzvy: po uplynutí čekání na výzvu lze posílat (bez přihlášení)
    let greet = try FakeCluster(prompt: "Welcome to the cluster\r\n", spots: [])
    await greet.start()
    defer { greet.stop() }
    cfg.cluster = SpotEndpoint(host: "127.0.0.1", port: greet.port)
    feed.start(cfg)
    defer { feed.stop() }
    #expect(await waitUntil { await MainActor.run { feed.clusterCommandsReady } })
    try await feed.sendClusterCommand("sh/wwv")
    #expect(await waitUntil { greet.received.contains("sh/wwv") })
    #expect(greet.received.first == "sh/wwv")                     // přihlášení se neposlalo
}

@Test @MainActor func commandsReadyAfterLoginAndResetOnStop() async throws {
    let cluster = try FakeCluster(spots: [])
    await cluster.start()
    defer { cluster.stop() }
    let feed = SpotFeed()
    var cfg = SpotFeedConfig(call: "OK1XOE", cluster: SpotEndpoint(host: "127.0.0.1", port: cluster.port))
    cfg.clientTuning = (0.05, 0.1)
    feed.start(cfg)
    #expect(await waitUntil { await MainActor.run { feed.clusterCommandsReady } })
    #expect(cluster.received.first == "OK1XOE")
    feed.stop()
    #expect(!feed.clusterCommandsReady)
}

// „Jen RTTY“ = jen filtr zobrazení: CW spot se uloží i při zapnutém filtru, po vypnutí filtru je hned vidět.
@Test @MainActor func rttyOnlyIsDisplayFilterOnly() async throws {
    let cluster = try FakeCluster(spots: sampleLines())
    await cluster.start()
    defer { cluster.stop() }
    let now = Date()
    let feed = SpotFeed(clock: { now })
    var cfg = SpotFeedConfig(call: "OK1XOE", cluster: SpotEndpoint(host: "127.0.0.1", port: cluster.port), rttyOnly: true)
    cfg.clientTuning = (0.05, 0.1)
    feed.start(cfg)
    defer { feed.stop() }
    #expect(await waitUntil { await MainActor.run { feed.book.count >= 3 } })
    #expect(feed.book.byID.values.contains { $0.call == "UA3XYZ" && $0.mode == "CW" })     // uložen
    #expect(!feed.visible.contains { $0.call == "UA3XYZ" })                                  // skrytý
    let starts = feed.starts
    feed.rttyOnly = false
    #expect(feed.visible.contains { $0.call == "UA3XYZ" })
    #expect(feed.starts == starts && cluster.connections == 1)                               // bez nového připojení
}
