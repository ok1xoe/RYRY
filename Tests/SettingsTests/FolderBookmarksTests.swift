// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
@testable import Settings

@Test func bookmarkKeysIgnoreTrailingSlashAndDots() {
    var b = FolderBookmarks()
    b.set(Data([1]), for: "/Users/x/logs/")
    #expect(b.bookmark(for: "/Users/x/logs") == Data([1]))
    #expect(b.bookmark(for: "/Users/x/./logs/") == Data([1]))
    b.remove("/Users/x/logs")
    #expect(b.entries.isEmpty)
}

@Test func logBookmarksRoundTripAndOldSettingsLoadEmpty() throws {
    var s = AppSettings()
    s.log.bookmarks.set(Data([7, 8]), for: "/Users/x/Documents/RYRY")
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    #expect(back.log.bookmarks.bookmark(for: "/Users/x/Documents/RYRY") == Data([7, 8]))
    let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"log":{"directory":"/Users/x/Documents/mmtty4mac"}}"#.utf8))
    #expect(old.log.bookmarks.entries.isEmpty && old.log.directory == "/Users/x/Documents/mmtty4mac")
}

@Test func defaultLogFolderIsRYRYInTheRealHome() {
    #expect(LogSettings().directory == HomeDirectory.real + "/Documents/RYRY")
    #expect(!HomeDirectory.real.contains("/Library/Containers/"))
}
