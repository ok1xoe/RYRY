import Testing
import RigControl
import TestSupport
@testable import Keying

final class RecordingRig: Rig, @unchecked Sendable {
    var ptt: [Bool] = []
    var offline = false
    var name: String { "rec" }
    func connect() async throws { if offline { throw RigError.offline } }
    func disconnect() async {}
    func frequency() async throws -> Double { if offline { throw RigError.offline }; return 14e6 }
    func setFrequency(_ hz: Double) async throws {}
    func mode() async throws -> String { "USB" }
    func setMode(_ mode: String) async throws {}
    func setPTT(_ on: Bool) async throws { if offline { throw RigError.offline }; ptt.append(on) }
}

@Test(arguments: [(PTTMethod.rts, false), (.dtr, false), (.rtsDtr, false), (.rts, true)])
func serialPTT(method: PTTMethod, invert: Bool) async throws {
    let port = FakeSerialPort()
    let ptt = PTTController(method: method, port: port, rig: nil, invert: invert)
    try await ptt.prepare()
    try await ptt.set(true)
    try await ptt.set(false)
    let on = !invert, off = invert
    var want: [FakeSerialPort.Event] = [.open]
    switch method {
    case .rts: want += [.rts(off), .rts(on), .rts(off)]
    case .dtr: want += [.dtr(off), .dtr(on), .dtr(off)]
    case .rtsDtr: want += [.rts(off), .dtr(off), .rts(on), .dtr(on), .rts(off), .dtr(off)]
    default: break
    }
    #expect(port.events == want)
}

@Test func catPTTUsesRig() async throws {
    let rig = RecordingRig()
    let ptt = PTTController(method: .cat, port: nil, rig: rig)
    try await ptt.prepare()
    try await ptt.set(true); try await ptt.set(false)
    #expect(rig.ptt == [true, false])
}

@Test func catPTTWithOfflineRigFailsPrepare() async throws {
    let rig = RecordingRig(); rig.offline = true
    let ptt = PTTController(method: .cat, port: nil, rig: rig)
    await #expect(throws: PTTError.self) { try await ptt.prepare() }
}

@Test func serialPTTWithoutPortFailsPrepare() async throws {
    let port = FakeSerialPort(); port.failOpen = true
    let ptt = PTTController(method: .rts, port: port, rig: nil)
    await #expect(throws: PTTError.self) { try await ptt.prepare() }
}

@Test func forceOffNeverThrows() async throws {
    let port = FakeSerialPort()
    let rig = RecordingRig()
    let ptt = PTTController(method: .rtsDtr, port: port, rig: rig)
    try await ptt.prepare()
    port.failLines = true
    rig.offline = true
    await ptt.forceOff()           // nesmí hodit ani viset
}

@Test func reverse5() {
    #expect(UARTFSKKeyer.reverse5(0x01) == 0x10)
    #expect(UARTFSKKeyer.reverse5(0x0A) == 0x0A)
    #expect(UARTFSKKeyer.reverse5(0x1F) == 0x1F)
    #expect(UARTFSKKeyer.reverse5(0x03) == 0x18)
}

@Test func uartKeyerConfiguresAndWritesReversedCodes() throws {
    let port = FakeSerialPort()
    try port.open()
    let k = UARTFSKKeyer(port: port)
    try k.start()
    k.send(codes: [0x1F, 0x01, 0x03])
    #expect(port.events.contains(.configure(baud: 45.45, dataBits: 5, stopBits: 2)))
    #expect(port.written == [0x1F, 0x10, 0x18])
}

// Review Focus 5
@Test func uartUnsupportedBaudMentionsSoftFSK() throws {
    let port = FakeSerialPort(); port.failBaud = true
    try port.open()
    let k = UARTFSKKeyer(port: port)
    do { try k.start(); Issue.record("mělo selhat") }
    catch { #expect("\(error)".contains("fsk-soft")) }
}
