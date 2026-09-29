// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
import QSOLog
import Settings
import Engine
import RigControl
import RTTYModem
import TestSupport
@testable import AppCore

// Bod 2: bez rigu se zapíše ručně zadaná frekvence; zůstává pro další QSO; rig online má přednost
@Test func manualFrequencyIsLogged() async throws {
    let h = try makeApp(ptt: .none)
    try await h.app.setQSOField("freq", "14085.5")
    #expect(await h.app.qso.frequency == 14_085_500)
    try await h.app.setQSOField("call", "DL1ABC")
    let r = try await h.app.logQSO()
    #expect(r.frequency == 14_085_500 && r.band == "20m")
    await h.app.clearQSO()
    #expect(await h.app.qso.frequency == 14_085_500)          // pásmo zůstává
    await #expect(throws: AppError.self) { try await h.app.setQSOField("freq", "abc") }
    try await h.app.setQSOField("freq", "")                    // smazání
    #expect(await h.app.qso.frequency == nil)
    try await h.app.setQSOField("freq", "7040")
    await h.engine.pollRig()                                   // rig online (14,083 MHz)
    try await h.app.setQSOField("call", "OK2AA")
    #expect(try await h.app.logQSO().frequency == 14_083_000)
}

// Bod 1: duplicita v závodě = stejná základní značka, pásmo a mód od začátku závodu
@Test func dupeCheck() {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func rec(_ c: String, _ f: Double, _ m: String = "RTTY", _ dt: Double = 60) -> QSORecord {
        var r = QSORecord(call: c, timeOn: t0.addingTimeInterval(dt), mode: m); r.frequency = f; return r
    }
    let log = [rec("W1AW", 14_080_000), rec("DL1ABC/P", 7_040_000), rec("OK2AA", 14_080_000, "RTTY", -3600)]
    #expect(DupeCheck.isDupe(call: "W1AW", band: "20m", mode: "RTTY", records: log, since: t0))
    #expect(!DupeCheck.isDupe(call: "W1AW", band: "40m", mode: "RTTY", records: log, since: t0))
    #expect(DupeCheck.isDupe(call: "DL1ABC", band: "40m", mode: "RTTY", records: log, since: t0))    // /P = stejná stanice
    #expect(!DupeCheck.isDupe(call: "OK2AA", band: "20m", mode: "RTTY", records: log, since: t0))    // před začátkem
    #expect(!DupeCheck.isDupe(call: "W1AW", band: "20m", mode: "PSK", records: log, since: t0))
    #expect(DupeCheck.isDupe(call: "W1AW", band: nil, mode: "RTTY", records: log, since: t0))          // bez pásma = podle značky
}

@Test func dupeInController() async throws {
    let h = try makeApp(ptt: .none)
    var s = await h.app.settings
    s.contest = ContestSettings.preset(.cqwpxRTTY, year: 2026); s.contest.start = Date().addingTimeInterval(-3600)
    await h.app.updateSettingsForTesting(s)
    try await h.app.setQSOField("freq", "14080")
    try await h.app.setQSOField("call", "W1AW")
    #expect(await h.app.dupe() == false)
    _ = try await h.app.logQSO()
    try await h.app.setQSOField("call", "W1AW")
    #expect(await h.app.dupe() == true)
    try await h.app.setQSOField("freq", "7040")
    #expect(await h.app.dupe() == false)
}

// Bod 4: Super Check Partial – části značky a „blízké“ značky (oprava chybně přijaté)
@Test func superCheckPartial() {
    let scp = SuperCheck(calls: ["DL1ABC", "DL1ABD", "OK1XOE", "W1AW", "K1ABC", "dl1abc", "UA9ABC"])
    #expect(scp.count == 6)
    #expect(scp.partial("1AB") == ["DL1ABC", "DL1ABD", "K1ABC"])
    #expect(scp.partial("AB").isEmpty)                         // méně než 3 znaky
    #expect(scp.partial("DL1ABC") == ["DL1ABC"])
    #expect(scp.near("DL1ABX") == ["DL1ABC", "DL1ABD"])         // jedna záměna
    #expect(scp.near("W1AAW") == ["W1AW"])                       // jeden znak navíc
    #expect(scp.near("OK1XO") == ["OK1XOE"])                     // jeden chybí
    #expect(scp.near("DL1ABC").contains("DL1ABD") && !scp.near("DL1ABC").contains("DL1ABC"))
    #expect(scp.partial("1?B").contains("K1ABC"))                // ? = libovolný znak
    let parsed = SuperCheck.parse("# MASTER.SCP\n# comment\nDL1ABC\nOK1XOE\n\n")
    #expect(parsed == ["DL1ABC", "OK1XOE"])
}

// Review Important 3: s nastaveným rigem, který neodpovídá, se nezapíše stará uložená ruční frekvence
@Test func staleManualFrequencyNotUsedWithRigConfigured() async throws {
    var s = AppSettings(); s.station.call = "OK1XOE"; s.ptt.method = .none
    s.rig.type = .cat; s.log.manualFrequency = 14_080_000
    let engine = Engine(modem: try RTTYModem(), rig: NoRig(), audio: FakeAudioBackend(), config: s.engineConfig(),
                        serialFactory: { _ in FakeSerialPort() }, clock: ManualClock(), autoRun: false)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stale-\(UUID())")
    let app = AppController(settings: s, engine: engine, log: try QSOLogStore(directory: dir), profiles: nil)
    try await app.setQSOField("call", "DL1ABC")
    #expect(try await app.logQSO().frequency == nil)            // rig offline, stará frekvence se nepoužije
    try await app.setQSOField("freq", "7040")                    // zadaná teď → použije se
    try await app.setQSOField("call", "DL2ABC")
    #expect(try await app.logQSO().frequency == 7_040_000)
}
