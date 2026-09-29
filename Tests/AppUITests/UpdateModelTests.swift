// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
import Updates
@testable import AppUI

private final class FakeNet: UpdateNetwork, @unchecked Sendable {
    var json: String
    init(_ j: String) { json = j }
    func fetch(_ url: URL) async throws -> Data { Data(json.utf8) }
    func download(_ url: URL) async throws -> URL {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("x".utf8).write(to: f); return f
    }
}

@MainActor private final class OpenedBox { var urls: [URL] = [] }

private let feedJSON = #"{"latest":{"version":"0.13.0","build":150,"url":"https://example.com/mmtty4mac-0.13.0.dmg","notes":{"en":"N"}}}"#

@MainActor private func makeModel(_ net: FakeNet, feed: String? = "https://example.com/a.json",
                                  opened: OpenedBox = OpenedBox()) -> (UpdateModel, OpenedBox, URL) {
    let name = "um-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    let c = UpdateChecker(feedURL: feed, network: net, defaults: d, current: AppVersion("0.12.0", build: 1)!)
    let m = UpdateModel(checker: c, network: net, downloadsDirectory: dir, opener: { opened.urls.append($0) })
    return (m, opened, dir)
}

@MainActor @Test func launchCheckOpensWindowOnlyForNewVersion() async {
    let (m, _, _) = makeModel(FakeNet(feedJSON))
    var shown = 0; m.showWindow = { shown += 1 }
    await m.checkAtLaunch(enabled: false); #expect(shown == 0)
    await m.checkAtLaunch(enabled: true); #expect(shown == 1)
    guard case .available = m.status else { Issue.record("available"); return }
    let (m2, _, _) = makeModel(FakeNet(feedJSON), feed: "")
    m2.showWindow = { shown += 1 }
    await m2.checkAtLaunch(enabled: true); #expect(shown == 1 && m2.status == .idle)   // nenastaveno: ticho
}

@MainActor @Test func manualCheckShowsResultsAndDownloadOpensDMG() async {
    let (m0, _, _) = makeModel(FakeNet(feedJSON), feed: "")
    await m0.checkManually(); #expect(m0.status == .notConfigured)
    let (m1, _, _) = makeModel(FakeNet("{"))
    await m1.checkManually()
    guard case .failed = m1.status else { Issue.record("failed"); return }
    let (m, opened, dir) = makeModel(FakeNet(feedJSON))
    await m.checkManually()
    await m.download()
    guard case .downloaded(let f) = m.status else { Issue.record("downloaded: \(m.status)"); return }
    #expect(f.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL && opened.urls == [f])
}
