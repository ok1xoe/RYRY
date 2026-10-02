import Foundation
import Testing
import Settings
@testable import AppUI

// Font sizes: the receive and transmit windows separately, ⌘+ / ⌘− / ⌘0 for both, the interface size step by step.

@Test func olderSettingsUseOneSizeForBothWindows() throws {
    let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"display":{"fontSize":20}}"#.utf8))
    #expect(s.display.fontSize == 20 && s.display.txFontSize == 20 && s.display.uiSize == .normal)
    let big = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"display":{"fontSize":99,"txFontSize":2}}"#.utf8))
    #expect(big.display.fontSize == 48 && big.display.txFontSize == 9)
}

@Test @MainActor func textAndInterfaceSizeCommands() async {
    let f = Fixture()
    await f.model.setDisplay { $0.fontSize = 14; $0.txFontSize = 20 }
    await f.model.changeTextSize(by: 1)
    #expect(f.model.settings.display.fontSize == 15 && f.model.settings.display.txFontSize == 21)
    await f.model.setDisplay { $0.txFontSize = 48 }
    await f.model.changeTextSize(by: 1)
    #expect(f.model.settings.display.txFontSize == 48)                    // the upper limit
    await f.model.changeTextSize(by: nil)
    #expect(f.model.settings.display.fontSize == 14 && f.model.settings.display.txFontSize == 14)
    await f.model.changeUISize(by: 1)
    #expect(f.model.settings.display.uiSize == .large)
    await f.model.changeUISize(by: 5)
    #expect(f.model.settings.display.uiSize == .xlarge)
    await f.model.changeUISize(by: -9)
    #expect(f.model.settings.display.uiSize == .small)
    #expect(SettingsStore(directory: f.dir).load().0.display.uiSize == .small)   // saved at once
}
