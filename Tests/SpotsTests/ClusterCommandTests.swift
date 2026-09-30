import Foundation
import Testing
@testable import Spots

@Test func clusterCommandValidation() throws {
    #expect(try ClusterCommand.validate("  sh/dx 30 \r\n") == "sh/dx 30")
    #expect(throws: ClusterCommandError.empty) { try ClusterCommand.validate("  \r\n") }
    #expect(throws: ClusterCommandError.controlCharacter) { try ClusterCommand.validate("sh/dx\r\nset/skimmer") }
    #expect(throws: ClusterCommandError.controlCharacter) { try ClusterCommand.validate("sh/dx\u{1B}") }
    #expect(throws: ClusterCommandError.tooLong) { try ClusterCommand.validate(String(repeating: "x", count: 251)) }
    #expect(try ClusterCommand.validate(String(repeating: "x", count: 250)).count == 250)
}

@Test @MainActor func sendWithoutConnectionFailsClearly() async {
    let feed = SpotFeed()
    await #expect(throws: ClusterCommandError.notConnected) { try await feed.sendClusterCommand("sh/dx 30") }
    await #expect(throws: ClusterCommandError.empty) { try await feed.sendClusterCommand("") }
    await #expect(throws: ClusterCommandError.tooLong) { try await feed.sendClusterCommand(String(repeating: "x", count: 300)) }
    #expect(feed.consoleLines.isEmpty)
}

@Test @MainActor func commandGoesToClusterOnlyAndRepliesLandInConsole() async throws {
    let t = hhmmZ()
    let wwv = ["Date Hour   SFI   A   K Forecast", "26-Sep 1200Z  150   8   2 No Storms"]
    let cluster = try FakeCluster(spots: sampleLines(t), responses: ["sh/wwv": wwv])
    let rbn = try FakeCluster(prompt: "Please enter your call: ", spots: [])
    await cluster.start(); await rbn.start()
    defer { cluster.stop(); rbn.stop() }
    let now = Date()
    let feed = SpotFeed(clock: { now })
    var cfg = SpotFeedConfig(call: "OK1XOE", cluster: SpotEndpoint(host: "127.0.0.1", port: cluster.port),
                             rbn: SpotEndpoint(host: "127.0.0.1", port: rbn.port), rttyOnly: false)
    cfg.clientTuning = (0.05, 0.1)
    feed.start(cfg)
    defer { feed.stop() }
    // příkaz jde až po přihlášení – zkoušíme, dokud se neodešle
    nonisolated(unsafe) var sent = false
    #expect(await waitUntil {
        if sent { return true }
        sent = (try? await feed.sendClusterCommand("sh/wwv")) != nil
        return sent
    })
    #expect(await waitUntil { await MainActor.run { wwv.allSatisfy(feed.consoleLines.contains) } })
    #expect(cluster.received.contains("sh/wwv"))
    #expect(cluster.received.first == "OK1XOE")
    #expect(!rbn.received.contains("sh/wwv"))                  // RBN příkazy nedostává
    // spoty jdou do seznamu, ne do konzole; uvítání a odpovědi do konzole; odeslaný příkaz jako „> …“
    #expect(await waitUntil { await MainActor.run { feed.book.count >= 3 } })
    #expect(!feed.consoleLines.contains { $0.hasPrefix("DX de") })
    #expect(feed.consoleLines.contains { $0.hasSuffix("Hello, OK1XOE") })     // výzva „login:“ se slepí s prvním řádkem
    #expect(feed.consoleLines.contains("garbage line without structure"))
    #expect(feed.consoleLines.contains("> sh/wwv"))
    feed.clearConsole()
    #expect(feed.consoleLines.isEmpty)
}

@Test @MainActor func consoleIgnoresLinesWhenNotRunning() {
    let feed = SpotFeed()
    feed.appendConsole(["x"])
    #expect(feed.consoleLines.isEmpty)
}

@Test @MainActor func consoleIsCappedAt500() async throws {
    let cluster = try FakeCluster(spots: [])
    await cluster.start()
    defer { cluster.stop() }
    let feed = SpotFeed()
    var cfg = SpotFeedConfig(call: "OK1XOE", cluster: SpotEndpoint(host: "127.0.0.1", port: cluster.port))
    cfg.clientTuning = (0.05, 0.1)
    feed.start(cfg)
    defer { feed.stop() }
    feed.clearConsole()
    feed.appendConsole((0..<700).map { "line \($0)" })
    #expect(feed.consoleLines.count == SpotFeed.consoleMax)
    #expect(feed.consoleLines.first == "line 200" && feed.consoleLines.last == "line 699")
}

@Test @MainActor func sendAfterStopFails() async throws {
    let cluster = try FakeCluster(spots: [])
    await cluster.start()
    defer { cluster.stop() }
    let feed = SpotFeed()
    var cfg = SpotFeedConfig(call: "OK1XOE", cluster: SpotEndpoint(host: "127.0.0.1", port: cluster.port))
    cfg.clientTuning = (0.05, 0.1)
    feed.start(cfg)
    #expect(await waitUntil { await MainActor.run { feed.clusterState == .connected } })
    feed.stop()
    await #expect(throws: ClusterCommandError.notConnected) { try await feed.sendClusterCommand("sh/dx") }
}
