import Foundation
import Testing
import AppViews
import RigControl
import Settings
import Spots
@testable import AppUI

// Okna „Filtr pásem“ a „Filtr módů“ nabízejí celý pevný seznam pásem a skupin módů – nic se do nich nevejít nemůže
// (zaškrtávátko, které chybí, by trvale schovalo spoty) a popisky skupin jsou různé a neprázdné.
@Test @MainActor func filterWindowsShowWholeBandAndModeList() {
    #expect(SpotBandFilterWindow.rows.flatMap(\.self) == SpotFilter.allBands)
    #expect(SpotBandFilterWindow.rows.allSatisfy { !$0.isEmpty })
    // za pevným seznamem je ještě zaškrtávátko „ostatní“ (stejné slovo jako u módů) pro spoty bez vlastního pásma
    #expect(SpotBandFilterWindow.otherLabel == SpotFilterBar.modeLabel(.other))
    #expect(SpotModeFilterWindow.rows.flatMap(\.self) == SpotModeGroup.allCases)
    let labels = SpotModeGroup.allCases.map(SpotFilterBar.modeLabel)
    #expect(labels.allSatisfy { !$0.isEmpty } && Set(labels).count == labels.count)
    #expect(labels.contains("RTTY"))
}

// Zaškrtávátko „Jen RTTY“ a okno módů drží stejný stav v obou směrech – a jen přefiltrují zobrazení.
@Test @MainActor func rttyOnlyStaysInSyncWithModeWindow() async throws {
    let m = spotModel(rig: NoRig()) {
        $0.spots.clusterEnabled = true; $0.spots.clusterHost = "127.0.0.1"; $0.spots.clusterPort = 1
    }
    await m.start()
    let starts = m.spotFeed.starts
    #expect(m.settings.spots.rttyOnly)                                  // výchozí stav = zaškrtnuto
    m.setSpots { $0.setRTTYOnly(false) }
    #expect(m.settings.spots.filterModes == SpotFilter.allModes && m.spotFeed.filter.modes == SpotFilter.allModes)
    m.setSpots { $0.setFilterModes([.cw, .ssb]) }                       // volba v okně módů
    #expect(!m.settings.spots.rttyOnly)
    m.setSpots { $0.setRTTYOnly(true) }
    #expect(m.settings.spots.rttyOnly && m.spotFeed.filter.modes == [.rtty])
    m.setSpots { $0.setRTTYOnly(false) }
    #expect(m.settings.spots.filterModes == [.cw, .ssb])                // odškrtnutí vrátí volbu z okna
    m.setSpots { $0.setFilterModes([.rtty]) }                           // právě RTTY v okně = zaškrtnuto
    #expect(m.settings.spots.rttyOnly)
    m.setSpots { $0.setFilterModes([.rtty, .cw]) }                      // cokoli dalšího = odškrtnuto
    #expect(!m.settings.spots.rttyOnly)
    #expect(m.spotFeed.starts == starts)                                // pořád jen filtr zobrazení
    await m.stop()
}

// Dialog Nastavení nepřepíše filtr zobrazení změněný v oknech filtrů (stejně jako makra clusteru).
@Test @MainActor func applySettingsKeepsFilterEditedInFilterWindows() async throws {
    let m = spotModel(rig: NoRig())
    await m.start()
    let draft = m.settings                                              // dialog otevřen
    m.setSpots { $0.setFilterModes([.cw, .psk]); $0.setRTTYOnly(true); $0.filterBands = ["20m"] }
    var d = draft; d.spots.maxAgeMinutes = 45                           // v dialogu změněna jiná položka spotů
    await m.applySettings(d, baseline: draft)
    #expect(m.settings.spots.maxAgeMinutes == 45)
    #expect(m.settings.spots.rttyOnly && m.settings.spots.filterBands == ["20m"])
    #expect(m.settings.spots.previousFilterModes == [.cw, .psk])        // i pamatovaná volba zůstane
    await m.stop()
}
