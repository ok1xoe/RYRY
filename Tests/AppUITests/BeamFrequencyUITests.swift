import Foundation
import Testing
import AppCore
import RigControl
import Settings
@testable import AppUI

private func near(_ a: Double, _ b: Double, _ tol: Double) -> Bool { abs(a - b) <= tol }

// MARK: Bearing and distance

@Test @MainActor func beamUsesLocatorsWhenBothKnown() async throws {
    let f = Fixture()
    f.configure = { $0.station.locator = "JO70FC" }
    await f.model.start()
    await f.model.setQSOField("call", "W2AB")
    await f.model.setQSOField("locator", "FN30")
    let b = try #require(f.model.beamToRemote)
    #expect(b.ownSource == .locator && b.remoteSource == .locator)
    #expect(b.shortKm > 6000 && b.shortKm < 7000)
    #expect(near(b.longKm, 40075 - b.shortKm, 1e-9))
    #expect(b.shortAzimuth > 285 && b.shortAzimuth < 310)
    await f.model.stop()
}

@Test @MainActor func beamFallsBackToCountryForRemote() async throws {
    let f = Fixture()
    f.configure = { $0.station.locator = "JO70FC" }
    await f.model.start()
    await f.model.setQSOField("call", "JA1ABC")
    let b = try #require(f.model.beamToRemote)
    #expect(b.ownSource == .locator && b.remoteSource == .country)
    #expect(b.shortAzimuth > 0 && b.shortAzimuth < 90)                   // Japan: north-east
    await f.model.stop()
}

@Test @MainActor func ownPositionFallsBackToOwnCountry() async throws {
    let f = Fixture()                                                    // OK1XOE, without a locator
    await f.model.start()
    let own = try #require(f.model.ownPosition)
    #expect(own.source == .country)
    #expect(own.coordinate.lon > 10 && own.coordinate.lon < 20)          // east longitude positive
    await f.model.setQSOField("call", "W2AB")
    let b = try #require(f.model.beamToRemote)
    #expect(b.ownSource == .country && b.remoteSource == .country)
    await f.model.stop()
}

@Test @MainActor func invalidOwnLocatorFallsBackToCountry() async throws {
    let f = Fixture()
    f.configure = { $0.station.locator = "bad!" }
    await f.model.start()
    #expect(f.model.ownPosition?.source == .country)
    await f.model.stop()
}

@Test @MainActor func noBeamWithoutCallOrLocator() async throws {
    let f = Fixture()
    await f.model.start()
    #expect(f.model.beamToRemote == nil)
    await f.model.setQSOField("locator", "FN30")                         // the locator alone, without a call, is enough
    #expect(f.model.beamToRemote?.remoteSource == .locator)
    await f.model.stop()
}

@Test @MainActor func spotBeamUsesCountry() async throws {
    let f = Fixture()
    await f.model.start()
    let b = try #require(f.model.beam(call: "W2AB", locator: ""))
    #expect(b.shortAzimuth > 270 && b.shortAzimuth < 330)                // the USA from central Europe
    #expect(f.model.beam(call: "", locator: "") == nil)
    await f.model.stop()
}

// MARK: Frequency

@Test @MainActor func bandButtonTunesRig() async throws {
    let rig = SpotFakeRig()
    let m = spotModel(rig: rig)
    await m.start()
    let r = await m.setFrequency(kHz: 14080)
    #expect(r == .rig)
    #expect(rig.freqs == [14_080_000])
    await m.stop()
}

@Test @MainActor func typedFrequencyWithCommaTunesRig() async throws {
    let rig = SpotFakeRig()
    let m = spotModel(rig: rig)
    await m.start()
    #expect(await m.setFrequency(text: "7040,5") == .rig)
    #expect(await m.setFrequency(text: "14.08 MHz") == .rig)
    #expect(rig.freqs == [7_040_500, 14_080_000])
    await m.stop()
}

@Test @MainActor func invalidFrequencyIsRejected() async throws {
    let rig = SpotFakeRig()
    let m = spotModel(rig: rig)
    await m.start()
    #expect(await m.setFrequency(text: "abc") == .invalid)
    #expect(await m.setFrequency(text: "50") == .invalid)
    #expect(await m.setFrequency(text: "600000") == .invalid)
    #expect(await m.setFrequency(kHz: .nan) == .invalid)
    #expect(rig.freqs.isEmpty)
    #expect(!m.messages.isEmpty)
    await m.stop()
}

@Test @MainActor func frequencyWithoutRigSetsManualQSOFrequency() async throws {
    let rig = SpotFakeRig()
    let m = spotModel(rig: rig) { $0.rig.type = .none }
    await m.start()
    #expect(await m.setFrequency(kHz: 3590) == .manual)
    #expect(rig.freqs.isEmpty)
    #expect(m.qso.frequency == 3_590_000)
    #expect(await m.setFrequency(text: "14080,5") == .manual)
    #expect(m.qso.frequency == 14_080_500)
    await m.stop()
}

@Test @MainActor func rigIsNotRetunedDuringTX() async throws {
    let rig = SpotFakeRig()
    let m = spotModel(rig: rig)
    await m.start()
    await m.toggleTx()
    for _ in 0..<50 where m.state == .rx { try? await Task.sleep(for: .milliseconds(10)) }
    try #require(m.state != .rx)
    #expect(await m.setFrequency(kHz: 14080) == .rejectedTX)
    #expect(rig.freqs.isEmpty)
    #expect(m.messages.contains { $0.contains("Během vysílání") })
    await m.stop()
}

@Test @MainActor func failingRigReportsFailure() async throws {
    let m = spotModel(rig: NoRig())                                      // a rig configured but disconnected
    await m.start()
    #expect(await m.setFrequency(kHz: 14080) == .failed)
    #expect(m.messages.contains { $0.contains("14080.0") })
    await m.stop()
}

@Test func enterFrequencyShortcutHasDefaultWithoutConflict() {
    let s = AppSettings()
    let b = s.binding(for: .enterFrequency)
    #expect(b == KeyBinding(key: "f", modifiers: [.option, .command]) && b.isValid)
    #expect(s.conflictingShortcuts().isEmpty)
    #expect(ShortcutCommand.allCases.contains(.enterFrequency))
}
