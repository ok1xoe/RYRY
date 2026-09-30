import Foundation
import Testing
import DXCC
@testable import AppCore

private func near(_ a: Double, _ b: Double, _ tol: Double) -> Bool { abs(a - b) <= tol }

@Test func maidenheadFourCharsIsSquareCenter() throws {
    let c = try #require(Geo.maidenhead("JO70"))
    #expect(near(c.lat, 50.5, 1e-9) && near(c.lon, 15.0, 1e-9))
    let fn = try #require(Geo.maidenhead("FN31"))                    // Connecticut
    #expect(near(fn.lat, 41.5, 1e-9) && near(fn.lon, -73.0, 1e-9))
    let aa = try #require(Geo.maidenhead("AA00"))
    #expect(near(aa.lat, -89.5, 1e-9) && near(aa.lon, -179.0, 1e-9))
    let rr = try #require(Geo.maidenhead("RR99"))
    #expect(near(rr.lat, 89.5, 1e-9) && near(rr.lon, 179.0, 1e-9))
}

@Test func maidenheadSixAndEightChars() throws {
    let c6 = try #require(Geo.maidenhead("jo70fc"))                  // lower case and Prague
    #expect(near(c6.lat, 50.1042, 1e-3) && near(c6.lon, 14.4583, 1e-3))
    let c8 = try #require(Geo.maidenhead("JO70FC55"))
    #expect(near(c8.lat, 50.0 + 2 * 2.5 / 60 + 5.5 * 0.25 / 60, 1e-6))
    #expect(near(c8.lon, 14 + 5 * 5.0 / 60 + 5.5 * 0.5 / 60, 1e-6))
    #expect(Geo.distanceKm(c6, c8) < 1)                              // the eight-character form only refines the position
}

@Test func maidenheadInvalid() {
    for bad in ["", "J", "JO", "JO7", "JO70F", "JO70FCX", "JO70FC5", "JO70FC555", "SO70", "JS70", "J070", "JOAA",
                "JO70YA", "JO70FC5A", "JO 70", "ÁO70", "JO70fc55x"] {
        #expect(Geo.maidenhead(bad) == nil, "\(bad)")
    }
    #expect(Geo.maidenhead("  jo70  ") != nil)                       // surrounding spaces are ignored
}

@Test func distanceAndBearingPragueNewYork() throws {
    let prague = try #require(Geo.maidenhead("JO70FC"))
    let ny = Geo.Coordinate(lat: 40.7128, lon: -74.006)
    #expect(near(Geo.distanceKm(prague, ny), 6572, 15))
    #expect(near(Geo.bearing(from: prague, to: ny), 298, 0.5))
    #expect(near(Geo.distanceKm(ny, prague), Geo.distanceKm(prague, ny), 1e-6))
}

@Test func bearingCardinalDirections() {
    let o = Geo.Coordinate(lat: 0, lon: 0)
    #expect(near(Geo.bearing(from: o, to: .init(lat: 10, lon: 0)), 0, 1e-9))
    #expect(near(Geo.bearing(from: o, to: .init(lat: 0, lon: 10)), 90, 1e-9))
    #expect(near(Geo.bearing(from: o, to: .init(lat: -10, lon: 0)), 180, 1e-9))
    #expect(near(Geo.bearing(from: o, to: .init(lat: 0, lon: -10)), 270, 1e-9))
    #expect(near(Geo.distanceKm(o, .init(lat: 0, lon: 90)), 10007.5, 0.1))
}

@Test func samePointAndAntipodes() {
    let p = Geo.Coordinate(lat: 50, lon: 14)
    #expect(Geo.distanceKm(p, p) == 0)
    let b = Geo.beam(from: p, to: p)
    #expect(b.shortKm == 0 && b.shortAzimuth == 0)
    let anti = Geo.Coordinate(lat: -50, lon: -166)
    #expect(near(Geo.distanceKm(p, anti), Double.pi * 6371, 1))
    let ba = Geo.beam(from: p, to: anti)
    #expect(near(ba.shortKm, 20015, 2) && near(ba.longKm, 40075 - 20015, 2))
    #expect((0..<360).contains(ba.shortAzimuth))
}

@Test func longPathIsOppositeDirectionAndComplementDistance() {
    let prague = Geo.Coordinate(lat: 50.1042, lon: 14.4583)
    let ny = Geo.Coordinate(lat: 40.7128, lon: -74.006)
    let b = Geo.beam(from: prague, to: ny)
    #expect(near(b.shortAzimuth, 298, 0.5))
    #expect(near(b.longAzimuth, 118, 0.5))
    #expect(near(b.longKm, 40075 - b.shortKm, 1e-9))
    let w = Geo.beam(from: prague, to: .init(lat: 60, lon: -10))
    #expect((0..<360).contains(w.longAzimuth) && (0..<360).contains(w.shortAzimuth))
}

@Test func positionChoosesLocatorBeforeCountry() throws {
    let cty = "Czech Republic: 15: 28: EU: 50.00: -15.00: -1.0: OK: OK,OL;\nUnited States: 05: 08: NA: 37.53: 91.67: 5.0: K: K,W;\n"
    let db = try CountryDB(text: cty)
    let ok = db.lookup("OK1XOE")
    let us = try #require(db.lookup("W1AW"))
    let loc = try #require(Geo.position(locator: "JO70FC", country: ok))
    #expect(loc.source == .locator && near(loc.coordinate.lon, 14.4583, 1e-3))
    let cnt = try #require(Geo.position(locator: "", country: ok))
    #expect(cnt.source == .country && cnt.coordinate == Geo.Coordinate(lat: 50, lon: 15))
    let bad = try #require(Geo.position(locator: "ZZ99", country: ok))          // an invalid locator → the entity
    #expect(bad.source == .country)
    #expect(Geo.position(locator: "", country: nil) == nil)
    // cty.dat: west longitude is positive → the USA must be to the west (negative)
    let usp = try #require(Geo.position(locator: "", country: us))
    #expect(usp.coordinate.lon < 0 && near(usp.coordinate.lon, -91.67, 1e-9))
}

@Test func beamFromPositionsCarriesSources() {
    let a = Geo.Position(coordinate: .init(lat: 50, lon: 15), source: .locator)
    let b = Geo.Position(coordinate: .init(lat: 40.7, lon: -74), source: .country)
    let r = Geo.beam(own: a, remote: b)
    #expect(r.ownSource == .locator && r.remoteSource == .country)
    #expect(near(r.shortAzimuth, 298, 1.5))
}

@Test func kmFormattingUsesThousandsSeparator() {
    #expect(Geo.formatKm(1234) == "1\u{00A0}234")
    #expect(Geo.formatKm(950.4) == "950")
    #expect(Geo.formatKm(40075) == "40\u{00A0}075")
}

@Test func realCtyDatLongitudeSign() throws {
    let db = try #require(CountryDB.shared)
    let us = try #require(db.lookup("W2AB"))
    #expect(us.longitude < -60 && us.longitude > -125)              // the USA is in the western hemisphere
    let jp = try #require(db.lookup("JA1ABC"))
    #expect(jp.longitude > 120 && jp.longitude < 150)
    let ok = try #require(db.lookup("OK1XOE"))
    #expect(ok.longitude > 10 && ok.longitude < 20)
}

@Test func frequencyParsing() {
    #expect(FrequencyInput.parseKHz("14080") == 14080)
    #expect(FrequencyInput.parseKHz(" 14080,5 ") == 14080.5)
    #expect(FrequencyInput.parseKHz("14080.25") == 14080.25)
    #expect(FrequencyInput.parseKHz("7040 kHz") == 7040)
    #expect(FrequencyInput.parseKHz("7040khz") == 7040)
    #expect(FrequencyInput.parseKHz("14.08 MHz") == 14080)
    #expect(FrequencyInput.parseKHz("100") == 100)                 // lower bound
    #expect(FrequencyInput.parseKHz("500000") == 500_000)          // upper bound
    for bad in ["", "abc", "99.9", "500001", "-14080", "0", "1e3", "nan", "inf", "14,080,5", "14 080", "kHz", "1.2.3"] {
        #expect(FrequencyInput.parseKHz(bad) == nil, "\(bad)")
    }
}
