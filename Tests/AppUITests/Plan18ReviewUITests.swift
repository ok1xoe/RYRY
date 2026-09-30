import Foundation
import Testing
import AppCore
import QSOLog
import RigControl
import Settings
import Spots
@testable import AppUI

// Review plan18: the Settings dialog does not overwrite the cluster macros edited in the Spots window.
@Test @MainActor func applySettingsKeepsClusterMacrosEditedInSpotsWindow() async throws {
    let f = Fixture()
    await f.model.start()
    let draft = f.model.settings                                  // the dialog is open
    f.model.saveClusterMacros([Macro(name: "X", text: "sh/dx 5")]) // the Spots window
    var d = draft; d.spots.maxAgeMinutes = 45                     // another spot item changed in the dialog
    await f.model.applySettings(d, baseline: draft)
    #expect(f.model.settings.spots.maxAgeMinutes == 45)
    #expect(f.model.settings.spots.clusterMacros[0] == Macro(name: "X", text: "sh/dx 5"))
    await f.model.stop()
}

// A spot (dx %k %c) without a call is not sent; the message says why (not "not connected") and nothing is sent, not even partially.
@Test @MainActor func clusterSpotMacroWithoutCallIsRejected() async throws {
    let m = spotModel(rig: NoRig())
    m.saveClusterMacros(SpotSettings.defaultClusterMacros)
    #expect(m.qso.call.isEmpty)
    #expect(await m.runClusterMacro(9) == false)
    #expect(m.clusterMessage == AppModel.clusterErrorText(ClusterCommandError.incompleteSpot))
    m.saveClusterMacros([Macro(name: "2", text: "sh/wwv\ndx %k %c RTTY")])
    #expect(await m.runClusterMacro(0) == false)
    #expect(m.clusterMessage == AppModel.clusterErrorText(ClusterCommandError.incompleteSpot))
}

// The log index (highlighting, band map) uses the same dupe key as DupeCheck – for a preset without a mode.
@Test func logIndexDupeFollowsPresetRule() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var r = QSORecord(call: "W1AW", timeOn: t0.addingTimeInterval(60), mode: "RTTY"); r.frequency = 14_080_000
    let preset = LogIndex(records: [r], contestSince: t0, dupePerMode: false, country: { _ in nil })
    #expect(preset.isDupe(call: "W1AW/P", band: "20m", mode: "PSK") && !preset.isDupe(call: "W1AW", band: "40m", mode: "RTTY"))
    let custom = LogIndex(records: [r], contestSince: t0, country: { _ in nil })
    #expect(!custom.isDupe(call: "W1AW", band: "20m", mode: "PSK") && custom.isDupe(call: "W1AW", band: nil, mode: "RTTY"))
    for (call, band, mode) in [("W1AW", "20m", "PSK"), ("W1AW", nil, "PSK"), ("W1AW", "40m", "RTTY")] as [(String, String?, String)] {
        #expect(preset.isDupe(call: call, band: band, mode: mode)
                == DupeCheck.isDupe(call: call, band: band, mode: mode, records: [r], since: t0, perMode: false))
    }
}

// A contest with no start: the score window is fixed during the full computation, the increment gives the same result.
@Test @MainActor func scoreWithoutStartUsesFrozenWindow() async throws {
    let f = Fixture()
    f.configure = { s in s.contest = ContestSettings.preset(.cqwwRTTY, year: 2026); s.contest.start = nil }
    await f.model.start()
    let since = try #require(f.model.score?.since)
    #expect(f.model.score?.until == nil)
    await f.model.setQSOField("call", "DL1ABC")
    await f.model.setQSOField("freq", "14085")
    await f.model.setQSOField("exchangeRcvd", "14")
    await f.model.logQSO()
    for _ in 0..<100 where f.model.logRecords.isEmpty { await f.settle() }
    let s = try #require(f.model.score)
    #expect(s.since == since && s.qsos == 1)
    await f.model.stop()
}
