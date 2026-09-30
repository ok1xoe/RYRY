import Foundation
import Testing
import RigControl
import Settings
import Spots
@testable import AppUI

@Test @MainActor func clusterMacroWithoutConnectionReportsError() async throws {
    let m = spotModel(rig: NoRig())
    #expect(await m.runClusterMacro(0) == false)
    #expect(m.clusterMessage != nil)
    #expect(await m.sendClusterLine("sh/dx 30") == false)
    #expect(m.clusterHistory.isEmpty)                      // neodeslané se do historie nedává
}

@Test @MainActor func saveClusterMacrosPadsToTenAndDoesNotReconnect() async throws {
    let m = spotModel(rig: NoRig())
    m.saveClusterMacros([Macro(name: "A", text: "sh/dx 5")])
    #expect(m.settings.spots.clusterMacros.count == 10)
    #expect(m.settings.spots.clusterMacros[0].name == "A" && m.settings.spots.clusterMacros[1].isBlank)
    m.setSpots { $0.clusterMacros[1] = Macro(name: "B", text: "sh/wwv") }
    #expect(m.settings.spots.clusterMacros[1].name == "B")
    #expect(!m.spotFeed.isRunning)                         // změna maker nespouští síť
}

// Zaškrtávátka pásem a módů v okně Spoty jen přepínají filtr zobrazení – spojení se nerestartuje.
@Test @MainActor func togglingSpotFiltersDoesNotRestartFeed() async throws {
    let m = spotModel(rig: NoRig()) {
        $0.spots.clusterEnabled = true; $0.spots.clusterHost = "127.0.0.1"; $0.spots.clusterPort = 1
    }
    await m.start()
    #expect(m.spotFeed.isRunning && m.spotFeed.filter == SpotFilter())
    let starts = m.spotFeed.starts
    m.setSpots { $0.filterModes = SpotFilter.allModes }
    #expect(m.spotFeed.filter.modes == SpotFilter.allModes && m.spotFeed.starts == starts)
    m.setSpots { $0.filterModes = [.rtty] }
    #expect(m.spotFeed.filter.modes == [.rtty] && m.spotFeed.starts == starts)
    m.setSpots { $0.filterBands = [] }                                     // „Nic“ u pásem
    #expect(m.spotFeed.filter.bands.isEmpty && m.spotFeed.starts == starts)
    m.setSpots { $0.filterBands = SpotFilter.allBandsSet }                 // „Vše“ u pásem
    #expect(m.spotFeed.filter.bands == SpotFilter.allBandsSet && m.spotFeed.starts == starts)
    m.setSpots { $0.clusterPort = 2 }                                      // změna serveru = nové spojení
    #expect(m.spotFeed.starts == starts + 1)
    await m.stop()
}
