import Foundation
import Testing
import Engine
import ModemKit
import Settings
@testable import AppUI

@Test @MainActor func hamSetsShift170() async throws {
    let f = Fixture()
    await f.model.start()
    await f.model.setParam("shift", .double(850))
    await f.model.hamShift()
    #expect(await f.engine.modemParam("shift") == .double(170))
    await f.model.stop()
}

@Test @MainActor func wheelAdjustsSquelchLevel() async throws {
    let f = Fixture()
    await f.model.start()
    let before = f.model.param("squelchLevel")
    await f.model.adjustSquelch(steps: 3)
    guard case .double(let a)? = before, case .double(let b)? = f.model.param("squelchLevel") else { Issue.record("sq"); return }
    #expect(b > a)
    await f.model.adjustSquelch(steps: -1000)
    #expect(f.model.param("squelchLevel") == .double(0))
    await f.model.stop()
}

@Test @MainActor func profilesListSaveLoad() async throws {
    let f = Fixture()
    await f.model.start()
    await f.model.setParam("baud", .double(75))
    await f.model.saveProfile(1, name: "Rychlé 75")
    await f.model.setParam("baud", .double(45.45))
    #expect(f.model.profileNames[1] == "Rychlé 75")
    await f.model.loadProfile(1)
    #expect(f.model.param("baud") == .double(75))
    await f.model.stop()
}

@Test @MainActor func xyScopeCollectsPoints() async throws {
    let f = Fixture()
    await f.model.start()
    await f.model.setXYScope(true)
    f.audio.feedRx(RTTYSignalGeneratorShim.signal())
    await f.pump(20)
    await f.model.pollXY()
    #expect(f.model.xyPoints.count == 512)
    await f.model.stop()
}

@Test @MainActor func draftCRLFIsNormalized() async throws {
    let f = Fixture()
    await f.model.start()
    f.model.txDraft = "LINE ONE\r\nLINE TWO\r\n"
    await f.model.sendDraft(mode: .line)
    #expect(f.model.txDraft.isEmpty)
    #expect(f.model.lastSentForTesting == "LINE ONE\r\nLINE TWO\r\n")
    await f.model.stop()
}

@Test @MainActor func micMessageClearedAfterStart() async throws {
    let f = Fixture()
    f.model.noteForTesting("Čekám na povolení přístupu k mikrofonu (systémový dialog)…")
    await f.model.start()
    #expect(!f.model.messages.contains { $0.contains("Čekám na povolení") })
    await f.model.stop()
}

/// Rychlé události kolečka se nesmí ztratit ani přeházet.
@Test @MainActor func rapidWheelStepsAccumulate() async throws {
    let f = Fixture()
    await f.model.start()
    await f.model.setParam("squelchLevel", .double(100))
    async let a: Void = f.model.adjustSquelch(steps: 1)
    async let b: Void = f.model.adjustSquelch(steps: 1)
    async let c: Void = f.model.adjustSquelch(steps: 1)
    _ = await (a, b, c)
    #expect(f.model.param("squelchLevel") == .double(148))
    await f.model.stop()
}
