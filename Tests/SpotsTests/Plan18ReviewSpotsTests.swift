import Foundation
import Testing
@testable import Spots

// Review plan18: checking the lines for the cluster, a spot with no call/frequency, commands ready only after the login.

@Test func clusterCommandRejectsC1AndUnicodeLineSeparators() throws {
    for bad in ["sh/dx\u{85}30", "sh/dx\u{80}", "sh/dx\u{9F}", "sh/dx\u{2028}set/skimmer", "sh/dx\u{2029}"] {
        #expect(throws: ClusterCommandError.controlCharacter) { try ClusterCommand.validate(bad) }
    }
    #expect(try ClusterCommand.validate("talk OK1ABC Ahoj, díky ÄÖÜ") == "talk OK1ABC Ahoj, díky ÄÖÜ")
}

@Test func dxSpotCommandNeedsCallAndFrequency() throws {
    #expect(throws: ClusterCommandError.incompleteSpot) { try ClusterCommand.validate("dx 14085.0 RTTY") }     // %c empty
    #expect(throws: ClusterCommandError.incompleteSpot) { try ClusterCommand.validate("dx  DL1ABC RTTY") }    // %k empty
    #expect(throws: ClusterCommandError.incompleteSpot) { try ClusterCommand.validate("DX 14085") }
    #expect(try ClusterCommand.validate("DX 14085.0 DL1ABC RTTY") == "DX 14085.0 DL1ABC RTTY")
    #expect(try ClusterCommand.validate("dx DL1ABC 14085") == "dx DL1ABC 14085")
    #expect(try ClusterCommand.validate("dxstat") == "dxstat")                           // a different command
    #expect(try ClusterCommand.validate("sh/dx 30") == "sh/dx 30")
}

/// A cluster with no login prompt: it only sends a greeting (or nothing).
@Test @MainActor func commandsReadyOnlyAfterLoginOrGreetingWithoutPrompt() async throws {
    // the server sends nothing except the telnet negotiation: TCP is connected, but commands must not be sent yet
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

    // a greeting with no prompt: once the wait for the prompt has elapsed, sending is allowed (without a login)
    let greet = try FakeCluster(prompt: "Welcome to the cluster\r\n", spots: [])
    await greet.start()
    defer { greet.stop() }
    cfg.cluster = SpotEndpoint(host: "127.0.0.1", port: greet.port)
    feed.start(cfg)
    defer { feed.stop() }
    #expect(await waitUntil { await MainActor.run { feed.clusterCommandsReady } })
    try await feed.sendClusterCommand("sh/wwv")
    #expect(await waitUntil { greet.received.contains("sh/wwv") })
    #expect(greet.received.first == "sh/wwv")                     // the login was not sent
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

// The mode filter is only a display filter: a CW spot is stored even with the filter on, and it is visible as soon as CW is checked.
@Test @MainActor func modeFilterIsDisplayFilterOnly() async throws {
    let cluster = try FakeCluster(spots: sampleLines())
    await cluster.start()
    defer { cluster.stop() }
    let now = Date()
    let feed = SpotFeed(clock: { now })
    var cfg = SpotFeedConfig(call: "OK1XOE", cluster: SpotEndpoint(host: "127.0.0.1", port: cluster.port), filter: SpotFilter())
    cfg.clientTuning = (0.05, 0.1)
    feed.start(cfg)
    defer { feed.stop() }
    #expect(await waitUntil { await MainActor.run { feed.book.count >= 3 } })
    #expect(feed.book.byID.values.contains { $0.call == "UA3XYZ" && $0.mode == "CW" })     // stored
    #expect(!feed.visible.contains { $0.call == "UA3XYZ" })                                  // hidden
    let starts = feed.starts
    feed.filter.modes = SpotFilter.allModes
    #expect(feed.visible.contains { $0.call == "UA3XYZ" })
    #expect(feed.starts == starts && cluster.connections == 1)                               // without a new connection
}
