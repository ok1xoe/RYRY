import Foundation
import Testing
@testable import DXCC

let fixture = """
Czech Republic:           15:  28:  EU:   50.00:   -16.00:    -1.0:  OK:
    OK,OL;
Fed. Rep. of Germany:     14:  28:  EU:   51.00:   -10.00:    -1.0:  DL:
    DA,DB,DC,DD,DE,DF,DG,DH,DI,DJ,DK,DL,DM,DN,DO,DP,DQ,DR,=DL0XX(15)[29];
United States:            05:  08:  NA:   37.53:    91.67:     5.0:  K:
    AA,AB,K,N,W,=W1AW(5)[8]{NA}<41.7/72.7>~5.0~,
    KH6ABC;
Hawaii:                   31:  61:  OC:   21.12:   157.48:    10.0:  KH6:
    AH6,KH6,KH7,NH6,WH6;
Asiatic Russia:           17:  30:  AS:   55.88:   -84.08:    -7.0:  UA9:
    UA9,UA0,R9(18)[31];
"""

@Test func parsesEntities() throws {
    let db = try CountryDB(text: fixture)
    #expect(db.count == 5)
    let ok = try #require(db.lookup("OK1XOE"))
    #expect(ok.name == "Czech Republic" && ok.continent == "EU" && ok.cqZone == 15 && ok.ituZone == 28)
    #expect(ok.utcOffsetHours == 1 && ok.primaryPrefix == "OK")
    #expect(ok.latitude == 50 && ok.longitude == 16)              // cty.dat: west positive → converted to east positive
}

@Test func exactCallsAndOverrides() throws {
    let db = try CountryDB(text: fixture)
    let x = try #require(db.lookup("DL0XX"))
    #expect(x.name == "Fed. Rep. of Germany" && x.cqZone == 15 && x.ituZone == 29)
    #expect(db.lookup("DL0XXA")?.cqZone == 14)                     // an exact call does not apply to longer ones
    let w = try #require(db.lookup("W1AW"))
    #expect(w.cqZone == 5 && w.ituZone == 8 && w.latitude == 41.7 && w.longitude == -72.7 && w.utcOffsetHours == -5)
    let r = try #require(db.lookup("R9ABC"))
    #expect(r.name == "Asiatic Russia" && r.cqZone == 18 && r.ituZone == 31)
}

@Test func longestPrefixWins() throws {
    let db = try CountryDB(text: fixture)
    #expect(db.lookup("KH6XYZ")?.name == "Hawaii")
    #expect(db.lookup("KH6ABC")?.name == "United States")          // a longer prefix from a different entity
    #expect(db.lookup("K1ABC")?.name == "United States")
    #expect(db.lookup("Q1ABC") == nil)
    #expect(db.lookup("") == nil)
}

@Test(arguments: [("OK/DL1ABC", "Czech Republic"), ("DL1ABC/P", "Fed. Rep. of Germany"),
                  ("OK1XOE/QRP", "Czech Republic"), ("OK/DL1ABC/P", "Czech Republic"),
                  ("KH6/OK1XOE", "Hawaii"), ("OK1XOE/KH6", "Hawaii"), ("W1ABC/4", "United States"),
                  ("dl1abc/m", "Fed. Rep. of Germany")])
func portableCalls(call: String, country: String) throws {
    let db = try CountryDB(text: fixture)
    #expect(db.lookup(call)?.name == country)
}

@Test func maritimeMobileHasNoCountry() throws {
    let db = try CountryDB(text: fixture)
    #expect(db.lookup("DL1ABC/MM") == nil)
    #expect(db.lookup("OK1XOE/AM") == nil)
}

@Test func rejectsGarbage() {
    #expect(throws: CountryDB.Error.self) { _ = try CountryDB(text: "nothing useful here") }
}

@Test func bundledCtyDatLoads() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/cty.dat")
    let db = try CountryDB(contentsOf: url)
    #expect(db.count > 300)
    #expect(db.lookup("OK1XOE")?.name == "Czech Republic")
    #expect(db.lookup("VK2ABC")?.continent == "OC")
    #expect(db.lookup("JA1XYZ")?.utcOffsetHours == 9)
}

// Review I-5: M, R, B are entity prefixes (England, Russia, China), modifiers only as a suffix;
// WAE-only entities (*IT9 …) are not DXCC entities.
@Test func realCtyPortablePrefixesAndWAE() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/cty.dat")
    let db = try CountryDB(contentsOf: url)
    #expect(db.lookup("M/DL1ABC")?.name == "England")
    #expect(db.lookup("R/OK1XOE")?.name == "European Russia")
    #expect(db.lookup("BY/OK1XOE")?.name == "China")
    #expect(db.lookup("DL1ABC/M")?.name == "Fed. Rep. of Germany")
    #expect(db.lookup("DL1ABC/R")?.name == "Fed. Rep. of Germany")
    #expect(db.lookup("IT9ABC")?.name == "Italy")
    #expect(db.lookup("OK1XOE/P")?.name == "Czech Republic")
}

// Multipliers: CQ WW and WAE also count the entities from the WAE list (*IT9, *GM/s, *TA1, *4U1V, *JW/b, *IG9).
@Test func waeListLookup() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/cty.dat")
    let db = try CountryDB(contentsOf: url)
    #expect(db.lookup("IT9ABC", wae: true)?.name == "Sicily")
    #expect(db.lookup("IT9ABC", wae: true)?.primaryPrefix == "IT9")
    #expect(db.lookup("IT9ABC", wae: false)?.name == "Italy")
    #expect(db.lookup("TA1ABC", wae: true)?.name == "European Turkey")
    #expect(db.lookup("IG9ABC", wae: true)?.name == "African Italy")
    #expect(db.lookup("4U1VIC", wae: true)?.name == "Vienna Intl Ctr")
    #expect(db.lookup("I1ABC", wae: true)?.name == "Italy")                 // outside the WAE list = DXCC
    #expect(db.lookup("OK1XOE", wae: true)?.name == "Czech Republic")
    #expect(db.lookup("IT9ABC/P", wae: true)?.name == "Sicily")
    #expect(db.count > 300 && db.count < 400)                               // count = DXCC entities only
}
