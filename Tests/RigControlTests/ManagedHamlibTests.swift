// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
@testable import RigControl

private let listing = """
 Rig #  Mfg                    Model                   Version         Status      Macro
     1  Hamlib                 Dummy                   20240709.0      Stable      RIG_MODEL_DUMMY
  3073  Icom                   IC-7300                 20250517.14     Stable      RIG_MODEL_IC7300
  2037  Kenwood                TS-590SG                20250515.12     Stable      RIG_MODEL_TS590SG
  1035  Yaesu                  FT-991                  20241118.18     Stable      RIG_MODEL_FT991
"""

@Test func hamlibModelList() {
    let m = ManagedHamlibRig.parseModels(listing)
    #expect(m.count == 4)
    #expect(m[1] == HamlibModel(id: 3073, manufacturer: "Icom", model: "IC-7300"))
    #expect(m[2].title == "Kenwood TS-590SG")
    #expect(ManagedHamlibRig.parseModels("garbage").isEmpty)
}

@Test func hamlibArguments() {
    let a = ManagedHamlibRig.arguments(model: 3073, serialPort: "/dev/cu.usbserial-1", baud: 19200, tcpPort: 4533)
    #expect(a == ["-m", "3073", "-r", "/dev/cu.usbserial-1", "-s", "19200", "-T", "127.0.0.1", "-t", "4533"])
    #expect(ManagedHamlibRig.arguments(model: 1, serialPort: "", baud: 0, tcpPort: 4533) == ["-m", "1", "-T", "127.0.0.1", "-t", "4533"])
}

// Skutečný rigctld (model Dummy): aplikace ho spustí, ovládá a při odpojení ukončí
@Test func managedRigctldDummy() async throws {
    guard let bin = ManagedHamlibRig.findRigctld() else { return }          // bez hamlib test přeskočit
    let port = UInt16(46_000 + Int.random(in: 0..<1000))
    let rig = ManagedHamlibRig(binary: bin, model: 1, serialPort: "", baud: 0, tcpPort: port)
    try await rig.connect()
    try await rig.setFrequency(14_085_000)
    #expect(try await rig.frequency() == 14_085_000)
    #expect(rig.isRunning)
    await rig.disconnect()
    #expect(!rig.isRunning)
}

@Test func managedRigctldReportsStartFailure() async throws {
    guard let bin = ManagedHamlibRig.findRigctld() else { return }
    let rig = ManagedHamlibRig(binary: bin, model: 3073, serialPort: "/dev/cu.neexistuje", baud: 19200,
                               tcpPort: UInt16(47_000 + Int.random(in: 0..<1000)), startTimeout: .seconds(3))
    await #expect(throws: RigError.self) { try await rig.connect() }
    #expect(!rig.isRunning)
}

// Engine volá rovnou frequency() bez connect(): rigctld se spustí sám; po chybě se hned znovu nespouští
@Test func managedRigctldStartsLazily() async throws {
    guard let bin = ManagedHamlibRig.findRigctld() else { return }
    let rig = ManagedHamlibRig(binary: bin, model: 1, serialPort: "", baud: 0, tcpPort: UInt16(48_000 + Int.random(in: 0..<1000)))
    #expect(try await rig.frequency() > 0)
    await rig.disconnect()
    let bad = ManagedHamlibRig(binary: bin, model: 3073, serialPort: "/dev/cu.neexistuje", baud: 19200,
                               tcpPort: UInt16(49_000 + Int.random(in: 0..<1000)), startTimeout: .seconds(3))
    await #expect(throws: RigError.self) { try await bad.frequency() }
    let t0 = ContinuousClock.now
    await #expect(throws: RigError.offline) { try await bad.frequency() }   // v době odkladu hned offline
    #expect(ContinuousClock.now - t0 < .milliseconds(200))
}

// Review 5: souběžné dotazy spustí jediný rigctld; obsazený TCP port = srozumitelná chyba
@Test func managedRigctldSingleStartAndBusyPort() async throws {
    guard let bin = ManagedHamlibRig.findRigctld() else { return }
    let port = UInt16(45_000 + Int.random(in: 0..<900))
    let a = ManagedHamlibRig(binary: bin, model: 1, serialPort: "", baud: 0, tcpPort: port)
    async let f1 = a.frequency()
    async let f2 = a.frequency()
    async let f3 = a.frequency()
    _ = try await (f1, f2, f3)
    #expect(a.startCount == 1)
    let b = ManagedHamlibRig(binary: bin, model: 1, serialPort: "", baud: 0, tcpPort: port)   // port drží `a`
    await #expect(throws: RigError.self) { try await b.connect() }
    #expect(!b.isRunning)
    await a.disconnect()
}

@Test func managedRigctldStaysStoppedAfterDisconnect() async throws {
    guard let bin = ManagedHamlibRig.findRigctld() else { return }
    let rig = ManagedHamlibRig(binary: bin, model: 1, serialPort: "", baud: 0, tcpPort: UInt16(44_000 + Int.random(in: 0..<900)))
    #expect(try await rig.frequency() > 0)
    await rig.disconnect()
    await #expect(throws: RigError.offline) { try await rig.setPTT(false) }
    #expect(!rig.isRunning && rig.startCount == 1)
}
