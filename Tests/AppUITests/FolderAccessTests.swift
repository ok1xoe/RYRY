// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
import Settings
@testable import AppUI

@MainActor final class FakeFolderPrompt: FolderAccessPrompt {
    var answer: URL?
    var asked: [URL] = []
    init(_ a: URL?) { answer = a }
    func requestFolder(suggested: URL, message: String) async -> URL? { asked.append(suggested); return answer }
}

struct FakeBookmarkCodec: BookmarkCodec {
    var stale = false, fail = false
    func make(_ url: URL) throws -> Data { Data(url.path.utf8) }
    func resolve(_ d: Data) throws -> (url: URL, stale: Bool) {
        if fail { throw CocoaError(.fileNoSuchFile) }
        return (URL(fileURLWithPath: String(decoding: d, as: UTF8.self)), stale)
    }
}

private let container = "/Users/x/Library/Containers/cz.ok1xoe.mmtty4mac/Data"

@Test @MainActor func noBookmarkAsksOnceAndRemembers() async {
    let p = FakeFolderPrompt(URL(fileURLWithPath: "/Users/x/Documents/mmtty4mac"))
    let fa = FolderAccess(prompt: p, codec: FakeBookmarkCodec(), sandboxed: true, containerHome: container)
    var b = FolderBookmarks()
    let u = await fa.acquire("/Users/x/Documents/mmtty4mac", bookmarks: &b, message: "m")
    #expect(u?.path == "/Users/x/Documents/mmtty4mac" && p.asked.map(\.path) == ["/Users/x/Documents/mmtty4mac"])
    _ = await fa.acquire("/Users/x/Documents/mmtty4mac/", bookmarks: &b, message: "m")
    #expect(p.asked.count == 1)                                   // remembered, trailing slash ignored
}

@Test @MainActor func cancelReturnsNilAndStoresNothing() async {
    let fa = FolderAccess(prompt: FakeFolderPrompt(nil), codec: FakeBookmarkCodec(), sandboxed: true, containerHome: container)
    var b = FolderBookmarks()
    #expect(await fa.acquire("/Users/x/logs", bookmarks: &b, message: "m") == nil && b.entries.isEmpty)
}

@Test @MainActor func brokenBookmarkAsksAgainAndReplacesIt() async {
    let p = FakeFolderPrompt(URL(fileURLWithPath: "/Users/x/logs"))
    var b = FolderBookmarks(); b.set(Data("garbage".utf8), for: "/Users/x/logs")
    let fa = FolderAccess(prompt: p, codec: FakeBookmarkCodec(fail: true), sandboxed: true, containerHome: container)
    #expect(await fa.acquire("/Users/x/logs", bookmarks: &b, message: "m") != nil && p.asked.count == 1)
    #expect(b.bookmark(for: "/Users/x/logs") == Data("/Users/x/logs".utf8))
}

@Test @MainActor func aBookmarkThatNowPointsElsewhereAsksAgain() async {
    // the folder was moved: the bookmark resolves, but to a different path than the log settings name
    let p = FakeFolderPrompt(URL(fileURLWithPath: "/Users/x/logs"))
    var b = FolderBookmarks(); b.set(Data("/Users/x/Trash/logs".utf8), for: "/Users/x/logs")
    let fa = FolderAccess(prompt: p, codec: FakeBookmarkCodec(), sandboxed: true, containerHome: container)
    #expect(await fa.acquire("/Users/x/logs", bookmarks: &b, message: "m")?.path == "/Users/x/logs" && p.asked.count == 1)
}

@Test @MainActor func aChosenDifferentFolderIsReturnedAndRemembered() async {
    let p = FakeFolderPrompt(URL(fileURLWithPath: "/Users/x/Other"))
    var b = FolderBookmarks()
    let fa = FolderAccess(prompt: p, codec: FakeBookmarkCodec(), sandboxed: true, containerHome: container)
    #expect(await fa.acquire("/Users/x/logs", bookmarks: &b, message: "m")?.path == "/Users/x/Other")
    #expect(b.bookmark(for: "/Users/x/Other") != nil && b.bookmark(for: "/Users/x/logs") == nil)
}

@Test @MainActor func insideTheContainerOrNotSandboxedNeverAsks() async {
    let p = FakeFolderPrompt(nil)
    var b = FolderBookmarks()
    let a = FolderAccess(prompt: p, codec: FakeBookmarkCodec(), sandboxed: true, containerHome: container)
    #expect(await a.acquire(container + "/Documents/RYRY", bookmarks: &b, message: "m") != nil)
    let n = FolderAccess(prompt: p, codec: FakeBookmarkCodec(), sandboxed: false, containerHome: container)
    #expect(await n.acquire("/tmp/x", bookmarks: &b, message: "m")?.path == "/tmp/x")
    #expect(p.asked.isEmpty && b.entries.isEmpty)
}

// Review focus: the user cancels the access dialog → the app still starts with a log in the container and says where.
@Test @MainActor func refusedLogFolderFallsBackToTheContainer() async throws {
    let f = Fixture()
    f.configure = { $0.log.directory = "/nonexistent/elsewhere" }
    let prompt = FakeFolderPrompt(nil)
    f.model.folderAccess = FolderAccess(prompt: prompt, codec: FakeBookmarkCodec(), sandboxed: true, containerHome: f.dir.path)
    await f.model.start()
    #expect(prompt.asked.map(\.path) == ["/nonexistent/elsewhere"])
    let fallback = f.dir.appendingPathComponent("Documents/RYRY").path
    #expect(f.model.settings.log.directory == fallback)
    #expect(f.model.app?.log != nil)
    #expect(f.model.messages.contains { $0.contains(fallback) })
    await f.model.stop()
}

// Review focus: a log (e.g. from the recent list) in a folder without a bookmark → the folder is asked for, then opened.
@Test @MainActor func openingALogElsewhereAsksForItsFolderOnce() async throws {
    let f = Fixture()
    let other = FileManager.default.temporaryDirectory.appendingPathComponent("elsewhere-\(UUID())")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    try "".write(to: other.appendingPathComponent("contest.jsonl"), atomically: true, encoding: .utf8)
    let prompt = FakeFolderPrompt(other)
    f.model.folderAccess = FolderAccess(prompt: prompt, codec: FakeBookmarkCodec(), sandboxed: true, containerHome: f.dir.path)
    await f.model.start()
    _ = try await f.model.openLog(file: other.appendingPathComponent("contest.adi"))
    #expect(prompt.asked.count == 1 && f.model.settings.log.name == "contest")
    #expect(f.model.settings.log.bookmarks.bookmark(for: other.path) != nil)
    await f.model.stop()
    await f.model.start()                                             // restart: the bookmark is used, no new dialog
    #expect(prompt.asked.count == 1 && f.model.settings.log.name == "contest")
    await f.model.stop()
}

// Refusing the folder of a log being opened keeps the current log.
@Test @MainActor func refusingTheFolderOfALogToOpenKeepsTheCurrentLog() async throws {
    let f = Fixture()
    let other = FileManager.default.temporaryDirectory.appendingPathComponent("elsewhere-\(UUID())")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    try "".write(to: other.appendingPathComponent("contest.jsonl"), atomically: true, encoding: .utf8)
    f.model.folderAccess = FolderAccess(prompt: FakeFolderPrompt(nil), codec: FakeBookmarkCodec(), sandboxed: true, containerHome: f.dir.path)
    await f.model.start()
    let before = f.model.settings.log.name
    await #expect(throws: (any Error).self) { _ = try await f.model.openLog(file: other.appendingPathComponent("contest.adi")) }
    #expect(f.model.settings.log.name == before)
    await f.model.stop()
}
