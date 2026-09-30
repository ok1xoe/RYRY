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
