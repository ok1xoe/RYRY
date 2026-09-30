import Foundation
import Testing
import AppViews
import RigControl
import Settings
import Spots
@testable import AppUI

// The "Band filter" and "Mode filter" windows offer the whole fixed list of bands and mode groups – nothing can be left out of them
// (a missing check box would hide spots for good) and the group labels are distinct and non-empty.
@Test @MainActor func filterWindowsShowWholeBandAndModeList() {
    #expect(SpotBandFilterWindow.rows.flatMap(\.self) == SpotFilter.allBands)
    #expect(SpotBandFilterWindow.rows.allSatisfy { !$0.isEmpty })
    // after the fixed list there is one more "other" check box (the same word as for the modes) for spots with no band of their own
    #expect(SpotBandFilterWindow.otherLabel == SpotFilterBar.modeLabel(.other))
    #expect(SpotModeFilterWindow.rows.flatMap(\.self) == SpotModeGroup.allCases)
    let labels = SpotModeGroup.allCases.map(SpotFilterBar.modeLabel)
    #expect(labels.allSatisfy { !$0.isEmpty } && Set(labels).count == labels.count)
    #expect(labels.contains("RTTY"))
}

// The "RTTY only" check box and the modes window hold the same state in both directions – and they only filter the display.
@Test @MainActor func rttyOnlyStaysInSyncWithModeWindow() async throws {
    let m = spotModel(rig: NoRig()) {
        $0.spots.clusterEnabled = true; $0.spots.clusterHost = "127.0.0.1"; $0.spots.clusterPort = 1
    }
    await m.start()
    let starts = m.spotFeed.starts
    #expect(m.settings.spots.rttyOnly)                                  // the default state = checked
    m.setSpots { $0.setRTTYOnly(false) }
    #expect(m.settings.spots.filterModes == SpotFilter.allModes && m.spotFeed.filter.modes == SpotFilter.allModes)
    m.setSpots { $0.setFilterModes([.cw, .ssb]) }                       // a choice made in the modes window
    #expect(!m.settings.spots.rttyOnly)
    m.setSpots { $0.setRTTYOnly(true) }
    #expect(m.settings.spots.rttyOnly && m.spotFeed.filter.modes == [.rtty])
    m.setSpots { $0.setRTTYOnly(false) }
    #expect(m.settings.spots.filterModes == [.cw, .ssb])                // unchecking restores the choice from the window
    m.setSpots { $0.setFilterModes([.rtty]) }                           // exactly RTTY in the window = checked
    #expect(m.settings.spots.rttyOnly)
    m.setSpots { $0.setFilterModes([.rtty, .cw]) }                      // anything else = unchecked
    #expect(!m.settings.spots.rttyOnly)
    #expect(m.spotFeed.starts == starts)                                // still only a display filter
    await m.stop()
}

// The Settings dialog does not overwrite the display filter changed in the filter windows (just like the cluster macros).
@Test @MainActor func applySettingsKeepsFilterEditedInFilterWindows() async throws {
    let m = spotModel(rig: NoRig())
    await m.start()
    let draft = m.settings                                              // the dialog is open
    m.setSpots { $0.setFilterModes([.cw, .psk]); $0.setRTTYOnly(true); $0.filterBands = ["20m"] }
    var d = draft; d.spots.maxAgeMinutes = 45                           // another spot item changed in the dialog
    await m.applySettings(d, baseline: draft)
    #expect(m.settings.spots.maxAgeMinutes == 45)
    #expect(m.settings.spots.rttyOnly && m.settings.spots.filterBands == ["20m"])
    #expect(m.settings.spots.previousFilterModes == [.cw, .psk])        // the remembered choice is kept too
    await m.stop()
}
