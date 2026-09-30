import Foundation
import Testing
@testable import Spots

// Výpis `sh/dx` (DXSpider, AR-Cluster, CC Cluster): řádky se skutečným datem a časem a spotterem v <…>.

private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
    return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

@Test func parsesDXSpiderShowDXLine() throws {
    let now = utc(2026, 9, 30, 7, 20)
    let s = try #require(SpotParser.parse("  14080.0  JA1ABC      30-Sep-2026 0701Z  RTTY cq                  <OK1XOE>", now: now))
    #expect(s.frequencyKHz == 14080.0 && s.call == "JA1ABC" && s.spotter == "OK1XOE")
    #expect(s.time == utc(2026, 9, 30, 7, 1))
    #expect(s.comment == "RTTY cq" && s.mode == "RTTY" && s.source == .cluster)
}

@Test func parsesARAndCCClusterVariants() throws {
    let now = utc(2026, 9, 30, 7, 20)
    // AR-Cluster: jedna mezera, skimmer spotter s „-#“
    let ar = try #require(SpotParser.parse("14083.5 DL1ABC 30-Sep-2026 0655Z 22 dB 45 BPS CQ <W3LPL-#>", now: now))
    #expect(ar.call == "DL1ABC" && ar.spotter == "W3LPL-#" && ar.time == utc(2026, 9, 30, 6, 55))
    #expect(ar.mode == "RTTY" && ar.snr == 22)                                  // RTTY segment, SNR z komentáře
    // CC Cluster: rok dvouciferně, za spotterem lokátor
    let cc = try #require(SpotParser.parse(" 7033.0  UA3XYZ  30-Sep-26 0610Z  CW 599  <DK9IP>  JO40", now: now))
    #expect(cc.call == "UA3XYZ" && cc.spotter == "DK9IP" && cc.mode == "CW" && cc.time == utc(2026, 9, 30, 6, 10))
    // datum bez roku (přes Nový rok = loňský rok)
    let ny = try #require(SpotParser.parse("14085.0 K1ABC 31-Dec 2350Z RTTY <W1AW>", now: utc(2027, 1, 1, 0, 10)))
    #expect(ny.time == utc(2026, 12, 31, 23, 50))
    // prázdný komentář
    let bare = try #require(SpotParser.parse("21080.0 VK2ABC 30-Sep-2026 0700Z <ZL1AA>", now: now))
    #expect(bare.comment.isEmpty && bare.mode == "RTTY")
}

@Test func listingNeedsFullPatternAndClusterSource() {
    let now = utc(2026, 9, 30, 7, 20)
    // RBN výpisy nepřijímá (jen DX cluster)
    #expect(SpotParser.parse("14080.0 JA1ABC 30-Sep-2026 0701Z RTTY <OK1XOE>", now: now, source: .rbn) == nil)
    for junk in [
        "14080.0 JA1ABC 30-Sep-2026 0701Z RTTY",                 // bez <spottera>
        "14080.0 JA1ABC 0701Z RTTY <OK1XOE>",                    // bez data
        "14080.0 JA1ABC 30-Sep-2026 RTTY <OK1XOE>",              // bez času
        "14080.0 JA1ABC 31-Feb-2026 0701Z RTTY <OK1XOE>",        // neplatné datum
        "JA1ABC 14080.0 30-Sep-2026 0701Z RTTY <OK1XOE>",        // prohozené pořadí
        "sh/dx 30",
        "Date Hour   SFI   A   K Forecast",
        "30-Sep-2026 0700Z dxspider >",
        "14080.0 RTTY 30-Sep-2026 0701Z cq <OK1XOE>",            // RTTY není značka
    ] {
        #expect(SpotParser.parse(junk, now: now) == nil, "\(junk)")
    }
}

@Test @MainActor func showDXReplyFillsSpotTableNotConsole() async throws {
    let now = Date()
    var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = c.timeZone
    f.dateFormat = "dd-MMM-yyyy HHmm'Z'"
    let fresh = f.string(from: now.addingTimeInterval(-120)), old = f.string(from: now.addingTimeInterval(-3 * 3600))
    let reply = [
        "  14080.0  JA1ABC      \(fresh)  RTTY cq                  <OK1XOE>",
        "   7040.0  PY2ABC      \(fresh)  CW                       <PY1XX>",
        "  21080.0  VK2ABC      \(old)  RTTY                     <ZL1AA>",       // starší než maxAge
        "sh/dx: 3 spots",
    ]
    let cluster = try FakeCluster(spots: [], responses: ["sh/dx 3": reply])
    await cluster.start()
    defer { cluster.stop() }
    let feed = SpotFeed(clock: { now })
    var cfg = SpotFeedConfig(call: "OK1XOE", cluster: SpotEndpoint(host: "127.0.0.1", port: cluster.port), filter: .all)
    cfg.clientTuning = (0.05, 0.1)
    feed.start(cfg)
    defer { feed.stop() }
    #expect(await waitUntil { await MainActor.run { feed.clusterCommandsReady } })
    try await feed.sendClusterCommand("sh/dx 3")
    #expect(await waitUntil { await MainActor.run { feed.consoleLines.contains("sh/dx: 3 spots") } })
    #expect(await waitUntil { await MainActor.run { feed.book.count == 2 } })
    #expect(Set(feed.book.byID.values.map(\.call)) == ["JA1ABC", "PY2ABC"])
    #expect(!feed.consoleLines.contains { $0.contains("JA1ABC") })
}
