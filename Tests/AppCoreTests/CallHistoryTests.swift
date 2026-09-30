import Foundation
import Testing
import Settings
@testable import AppCore

// MARK: Parser

@Test func callHistoryParsesOrderHeader() {
    let h = CallHistory.parse("""
    # komentář
    !!Order!!,Call,Name,Loc1,Exch1,CQZone,ITUZone,State,Foo
    DL1ABC,HANS,JO62,X,14,28,,zzz
    W1AW,Hiram,FN31,,5,8,CT,q
    """)
    #expect(h.count == 2)
    let e = h.lookup("DL1ABC")
    #expect(e == CallHistoryEntry(name: "HANS", loc: "JO62", exch: "X", cqZone: 14, ituZone: 28, state: ""))
    #expect(h.lookup("w1aw")?.state == "CT" && h.lookup("W1AW")?.exch == "")
}

@Test func callHistoryHeaderIsCaseInsensitiveAndReorders() {
    let h = CallHistory.parse("!!order!!,name,CALL,cqzone\nHANS,DL1ABC,14\n")
    #expect(h.lookup("DL1ABC") == CallHistoryEntry(name: "HANS", cqZone: 14))
}

@Test func callHistoryHeaderlessSimpleCSV() {
    let h = CallHistory.parse("DL1ABC,Hans,14\nOK1XOE,Tom\nOK2AAA\n")
    #expect(h.lookup("DL1ABC") == CallHistoryEntry(name: "Hans", exch: "14"))
    #expect(h.lookup("OK1XOE")?.name == "Tom")
    #expect(h.lookup("OK2AAA") == CallHistoryEntry())
}

@Test func callHistoryPlainHeaderWithoutOrderMarker() {
    let h = CallHistory.parse("Call,Name,Exch1\nDL1ABC,Hans,14\n")
    #expect(h.count == 1 && h.lookup("DL1ABC")?.exch == "14")
}

@Test func callHistoryQuotesEmptyColumnsAndCRLF() {
    let h = CallHistory.parse("!!Order!!,Call,Name,Loc1\r\n\"DL1ABC\",\"Hans, Jr\",\r\n,Nobody,JO60\r\n\"K1\",\"Say \"\"hi\"\"\",FN42\r\n")
    #expect(h.count == 2)
    #expect(h.lookup("DL1ABC")?.name == "Hans, Jr" && h.lookup("DL1ABC")?.loc == "")
    #expect(h.lookup("K1")?.name == "Say \"hi\"")
}

@Test func callHistoryDuplicateLastWins() {
    let h = CallHistory.parse("DL1ABC,Old,1\nDL1ABC,New\n")
    #expect(h.count == 1 && h.lookup("DL1ABC") == CallHistoryEntry(name: "New"))
}

@Test func callHistoryBaseCall() {
    let h = CallHistory.parse("DL1ABC,Hans\nOK1XOE/P,Tom\n")
    #expect(h.lookup("DL1ABC/P")?.name == "Hans")
    #expect(h.lookup("OE/DL1ABC")?.name == "Hans")
    #expect(h.lookup("OK1XOE")?.name == "Tom")
    #expect(h.lookup("ZZ9ZZZ") == nil)
}

@Test func callHistoryLoadsLargeFileInBackground() async throws {
    var t = "!!Order!!,Call,Name,CQZone\n"
    for i in 0..<30_000 { t += "K\(i)ABC,N\(i),\(i % 40 + 1)\n" }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ch-\(UUID()).txt")
    try t.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    let h = try await CallHistory.load(url: url)
    #expect(h.count == 30_000 && h.lookup("K29999ABC")?.cqZone == 40)
}

// MARK: Mapování podle formátu

private func contest(_ f: ContestFormat, exchange: String = "", enabled: Bool = true) -> ContestSettings {
    var c = ContestSettings(); c.enabled = enabled; c.format = f; c.exchange = exchange; return c
}
private let full = CallHistoryEntry(name: "Hans", loc: "JO62", exch: "ABC", cqZone: 5, ituZone: 8, state: "NY")

@Test func callHistoryMappingByFormat() {
    let h = CallHistory()
    #expect(h.fields(for: full, contest: contest(.zone), isNorthAmerica: false) == ["name": "Hans", "locator": "JO62", "exchangeRcvd": "5"])
    #expect(h.fields(for: full, contest: contest(.cqrj), isNorthAmerica: true)["exchangeRcvd"] == "5 NY")
    #expect(h.fields(for: full, contest: contest(.cqrj), isNorthAmerica: false)["exchangeRcvd"] == "5")
    #expect(h.fields(for: full, contest: contest(.serial, exchange: "OK"), isNorthAmerica: nil)["exchangeRcvd"] == "ABC")
    #expect(h.fields(for: full, contest: contest(.serial), isNorthAmerica: nil)["exchangeRcvd"] == nil)   // pořadová čísla
    #expect(h.fields(for: full, contest: contest(.bartg), isNorthAmerica: nil) == ["name": "Hans", "locator": "JO62"])
    #expect(h.fields(for: full, contest: contest(.zone, enabled: false), isNorthAmerica: nil) == ["name": "Hans", "locator": "JO62"])
}

// MARK: Chování AppController

private func historyApp(_ f: ContestFormat, contestOn: Bool = true, fillEmptyOnly: Bool = true, enabled: Bool = true,
                        exchange: String = "") async throws -> Harness {
    let h = try makeFormatApp(f, exchange: exchange)
    var s = await h.app.settings
    s.contest.enabled = contestOn
    s.callHistory.enabled = enabled; s.callHistory.fillEmptyOnly = fillEmptyOnly
    await h.app.updateSettingsForTesting(s)
    await h.app.setCallHistory(CallHistory.parse("""
    !!Order!!,Call,Name,Loc1,Exch1,CQZone,State
    DL1ABC,HANS,JO62,FIX,17,
    W1AW,HIRAM,FN31,,5,CT
    """))
    return h
}

// DXCC: DL = CQ 14, OK = CQ 15; v testovací historii má DL1ABC zónu 17, aby bylo znát, odkud hodnota je.

@Test func historyFillsNameLocatorAndZone() async throws {
    let h = try await historyApp(.zone)
    try await h.app.setQSOField("call", "DL1ABC")
    let q = await h.app.qso
    #expect(q.name == "HANS" && q.locator == "JO62")
    #expect(q.exchangeRcvd == "17")
    #expect(q.historyFilled == ["name": "HANS", "locator": "JO62", "exchangeRcvd": "17"])
}

@Test func historyBeatsDXCCZoneEvenAfterIntermediateCall() async throws {
    let h = try await historyApp(.zone)
    try await h.app.setQSOField("call", "DL1AB")                       // rozepsaná značka: zóna z DXCC
    #expect(await h.app.qso.exchangeRcvd == "14")
    try await h.app.setQSOField("call", "DL1ABC")
    #expect(await h.app.qso.exchangeRcvd == "17")
}

@Test func historyNoEntryKeepsDXCCZone() async throws {
    let h = try await historyApp(.zone)
    try await h.app.setQSOField("call", "OK2AAA")
    let q = await h.app.qso
    #expect(q.exchangeRcvd == "15" && q.name.isEmpty && q.historyFilled.isEmpty)
}

@Test func historyManualEntryAlwaysWins() async throws {
    let h = try await historyApp(.zone)
    try await h.app.setQSOField("name", "Johnny")
    try await h.app.setQSOField("exchangeRcvd", "99")
    try await h.app.setQSOField("call", "DL1ABC")
    let q = await h.app.qso
    #expect(q.name == "Johnny" && q.exchangeRcvd == "99" && q.locator == "JO62")
    #expect(q.historyFilled == ["locator": "JO62"])
}

@Test func historyFillEmptyOnlyOffOverwrites() async throws {
    let h = try await historyApp(.zone, fillEmptyOnly: false)
    try await h.app.setQSOField("name", "Johnny")
    try await h.app.setQSOField("call", "DL1ABC")
    #expect(await h.app.qso.name == "HANS")
}

@Test func historyCqrjAddsStateForNorthAmerica() async throws {
    let h = try await historyApp(.cqrj)
    try await h.app.setQSOField("call", "W1AW")
    #expect(await h.app.qso.exchangeRcvd == "5 CT")
}

@Test func historySerialFixedExchangeUsesExch1() async throws {
    let h = try await historyApp(.serial, exchange: "OK")
    try await h.app.setQSOField("call", "DL1ABC")
    #expect(await h.app.qso.exchangeRcvd == "FIX")
    let h2 = try await historyApp(.serial)                             // pořadová čísla: bez výměny
    try await h2.app.setQSOField("call", "DL1ABC")
    let q = await h2.app.qso
    #expect(q.exchangeRcvd.isEmpty && q.name == "HANS")
}

@Test func historyOutsideContestFillsNameAndLocatorOnly() async throws {
    let h = try await historyApp(.zone, contestOn: false)
    try await h.app.setQSOField("call", "DL1ABC")
    let q = await h.app.qso
    #expect(q.name == "HANS" && q.locator == "JO62" && q.exchangeRcvd.isEmpty)
}

@Test func historyDisabledDoesNothing() async throws {
    let h = try await historyApp(.zone, enabled: false)
    try await h.app.setQSOField("call", "DL1ABC")
    let q = await h.app.qso
    #expect(q.name.isEmpty && q.exchangeRcvd == "14")
}

@Test func historyBaseCallSlashP() async throws {
    let h = try await historyApp(.zone)
    try await h.app.setQSOField("call", "DL1ABC/P")
    #expect(await h.app.qso.name == "HANS")
}

@Test func historyChangedCallReplacesOldAutoFilledValues() async throws {
    let h = try await historyApp(.zone)
    try await h.app.setQSOField("call", "DL1ABC")
    try await h.app.setQSOField("call", "OK2AAA")                      // bez záznamu: staré údaje z historie zmizí
    let q = await h.app.qso
    #expect(q.name.isEmpty && q.locator.isEmpty && q.exchangeRcvd == "15" && q.historyFilled.isEmpty)
}

// (dříve historyMarkerSurvivesUnchangedCommitButNotEdit – kontrola plánu 17: ruční zadání i shodné hodnoty
// zruší označení, viz Plan17ReviewTests.historyMarkerClearedByAnyManualSet)

@Test func historyFilledNotSerialized() throws {
    var q = QSOFields(); q.call = "X"; q.historyFilled = ["name": "A"]
    let json = String(decoding: try JSONEncoder().encode(q), as: UTF8.self)
    #expect(!json.contains("historyFilled"))
    #expect(try JSONDecoder().decode(QSOFields.self, from: Data(json.utf8)).call == "X")
}

@Test func callHistorySettingsDefaultsAndTolerantDecode() throws {
    let d = CallHistorySettings()
    #expect(!d.enabled && d.path.isEmpty && d.fillEmptyOnly)
    let s = try JSONDecoder().decode(CallHistorySettings.self, from: Data(#"{"enabled":"junk","path":"/a.txt"}"#.utf8))
    #expect(!s.enabled && s.path == "/a.txt" && s.fillEmptyOnly)
}
