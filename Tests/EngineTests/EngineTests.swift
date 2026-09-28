import Foundation
import Testing
import AudioIO
import Keying
import ModemKit
import RigControl
import RTTYModem
import RTTYSignalKit
import TestSupport
@testable import Engine

final class FakeRig: Rig, @unchecked Sendable {
    var online = true
    var ptt: [Bool] = []
    var freq = 14_080_000.0
    var name: String { "fake" }
    func connect() async throws { if !online { throw RigError.offline } }
    func disconnect() async {}
    func frequency() async throws -> Double { if !online { throw RigError.offline }; return freq }
    func setFrequency(_ hz: Double) async throws { freq = hz }
    func mode() async throws -> String { "USB" }
    func setMode(_ mode: String) async throws {}
    func setPTT(_ on: Bool) async throws { if !online { throw RigError.offline }; ptt.append(on) }
}

struct Rig_ {
    let engine: Engine
    let audio: FakeAudioBackend
    let port: FakeSerialPort
    let clock: ManualClock
    let events: AsyncStream<EngineEvent>
}

func makeEngine(ptt: PTTMethod = .rts, rig: Rig = NoRig(), txOutput: TxOutput = .afsk,
                configure: (inout EngineConfig) -> Void = { _ in }) throws -> Rig_ {
    let audio = FakeAudioBackend()
    let port = FakeSerialPort()
    let clock = ManualClock()
    port.clock = clock
    var cfg = EngineConfig()
    cfg.ptt = ptt
    cfg.pttPort = "/dev/cu.fake"
    cfg.txOutput = txOutput
    cfg.txDelay = .milliseconds(100)
    cfg.pttTail = .milliseconds(200)
    configure(&cfg)
    let e = Engine(modem: try RTTYModem(), rig: rig, audio: audio, config: cfg,
                   serialFactory: { _ in port }, clock: clock, autoRun: false)
    return Rig_(engine: e, audio: audio, port: port, clock: clock, events: e.events())
}

/// Pumpuje engine s posunem hodin, dokud neplatí podmínka (max `steps` kroků).
func pump(_ r: Rig_, ms: Double = 50, steps: Int = 2000, until: () async -> Bool) async {
    for _ in 0..<steps {
        if await until() { return }
        r.clock.advance(ms: ms)
        await r.engine.pump()
    }
}

/// Poslední nastavená úroveň RTS (PTT).
func lastRTS(_ p: FakeSerialPort) -> Bool? {
    for e in p.events.reversed() { if case .rts(let v) = e { return v } }
    return nil
}

func collectText(_ events: AsyncStream<EngineEvent>, echo: Bool = false) async -> String {
    var s = ""
    for await e in events { if case .modem(.rxText(let c, let isEcho)) = e, isEcho == echo { s.append(c) } }
    return s
}

@Test func receivesTextFromAudio() async throws {
    let r = try makeEngine(ptt: .none)
    try await r.engine.start()
    r.audio.feedRx(RTTYSignalGenerator().generate(text: "CQ DE OK1XOE K"))
    await pump(r) { r.audio.rxRemaining == 0 }
    await r.engine.stop()
    #expect(await collectText(r.events).contains("CQ DE OK1XOE K"))
}

@Test func fullTxCycleWithSerialPTT() async throws {
    let r = try makeEngine()
    try await r.engine.start()
    await r.engine.send(text: "TEST DE OK1XOE ")
    try await r.engine.tx()
    #expect(await r.engine.state == .pttOn)
    #expect(r.port.events.contains(.rts(true)))
    let pttOnTime = r.clock.now()
    await r.engine.pump()
    #expect(r.audio.writeCalls == 0)                         // před txDelay nic
    await pump(r) { await r.engine.state == .tx }
    #expect(r.clock.now() - pttOnTime >= 100_000_000)
    await r.engine.rx()                                       // RX po dovysílání
    await pump(r) { await r.engine.state == .rx }
    #expect(lastRTS(r.port) == false)
    // PTT se vypnulo až po pttTail za koncem modulace
    let offEvent = r.port.timedEvents.last { $0.1 == .rts(false) }!
    #expect(offEvent.0 >= pttOnTime + 300_000_000)
    // odvysílaný zvuk dekóduje nezávislý modem
    let m = try RTTYModem()
    let ev = m.events
    (r.audio.tx + [Float](repeating: 0, count: 4000)).withUnsafeBufferPointer { m.processRx($0) }
    m.finishEvents()
    var text = ""
    for await e in ev { if case .rxText(let c, false) = e { text.append(c) } }
    #expect(text.contains("TEST DE OK1XOE"))
    await r.engine.stop()
}

@Test func rxNowAbortsImmediately() async throws {
    let r = try makeEngine()
    try await r.engine.start()
    await r.engine.send(text: String(repeating: "RYRY ", count: 50))
    try await r.engine.tx()
    await pump(r) { await r.engine.state == .tx }
    await r.engine.rxNow()
    #expect(await r.engine.state == .rx)
    #expect(lastRTS(r.port) == false)
    await r.engine.stop()
}

@Test func pttTimeoutStopsTransmission() async throws {
    let r = try makeEngine { $0.pttTimeout = .seconds(2) }
    try await r.engine.start()
    try await r.engine.tune()
    await pump(r, ms: 100) { await r.engine.state == .rx }
    #expect(lastRTS(r.port) == false)
    await r.engine.stop()
    var sawTimeout = false
    for await e in r.events { if case .pttTimeout = e { sawTimeout = true } }
    #expect(sawTimeout)
}

// Review Focus 2
@Test func catPTTWithoutRigIsRejected() async throws {
    let r = try makeEngine(ptt: .cat)
    try await r.engine.start()
    await #expect(throws: EngineError.self) { try await r.engine.tx() }
    #expect(await r.engine.state == .rx)
    await r.engine.pump()
    #expect(r.audio.writeCalls == 0)
    await r.engine.stop()
}

@Test func failingPTTPortIsRejected() async throws {
    let r = try makeEngine()
    r.port.failOpen = true
    try await r.engine.start()                                  // RX běží i bez PTT
    await #expect(throws: EngineError.self) { try await r.engine.tx() }
    #expect(await r.engine.state == .rx)
    await r.engine.stop()
}

// Review Focus 1
@Test func portFailureMidTxReturnsToRx() async throws {
    let r = try makeEngine()
    try await r.engine.start()
    await r.engine.send(text: "RYRYRYRYRYRYRYRYRY")
    try await r.engine.tx()
    await pump(r) { await r.engine.state == .tx }
    r.port.failLines = true
    await r.engine.rx()
    await pump(r) { await r.engine.state == .rx }
    #expect(await r.engine.state == .rx)
    await r.engine.stop()
    var sawError = false
    for await e in r.events { if case .error = e { sawError = true } }
    #expect(sawError)
}

@Test func catRigGoingOfflineMidTxReturnsToRx() async throws {
    let rig = FakeRig()
    let r = try makeEngine(ptt: .cat, rig: rig)
    try await r.engine.start()
    await r.engine.send(text: "RYRYRYRYRYRY")
    try await r.engine.tx()
    #expect(rig.ptt == [true])
    await pump(r) { await r.engine.state == .tx }
    rig.online = false
    await r.engine.rx()
    await pump(r) { await r.engine.state == .rx }
    #expect(await r.engine.state == .rx)
    await r.engine.stop()
}

// Review Focus 3
@Test func repeatedCommandsAreIdempotent() async throws {
    let r = try makeEngine()
    try await r.engine.start()
    try await r.engine.tx()
    try await r.engine.tx()
    #expect(r.port.events.filter { $0 == .rts(true) }.count == 1)
    await pump(r) { await r.engine.state == .tx }
    await r.engine.rx(); await r.engine.rx()
    await r.engine.rxNow(); await r.engine.rxNow()
    #expect(await r.engine.state == .rx)
    try await r.engine.tx()
    await r.engine.stop()                                      // stop během TX
    #expect(await r.engine.state == .stopped)
    #expect(lastRTS(r.port) == false)
}

@Test func fskUartWritesReversedCodesAndSilentAudio() async throws {
    let r = try makeEngine(txOutput: .fskUART(path: "/dev/cu.fake")) { $0.audioDuringFSK = false }
    try await r.engine.start()
    try await r.engine.withModem { try $0.set(parameter: "diddle", value: .string("off")) }
    await r.engine.send(text: "RY")
    try await r.engine.tx()
    await pump(r) { await r.engine.state == .tx }
    await r.engine.rx()
    await pump(r) { await r.engine.state == .rx }
    #expect(r.port.written == [0x1F, 0x0A, 0x15].map(UARTFSKKeyer.reverse5))
    #expect(r.audio.tx.allSatisfy { $0 == 0 })
    await r.engine.stop()
}

@Test func rigStatusIsPolled() async throws {
    let rig = FakeRig()
    let r = try makeEngine(ptt: .none, rig: rig)
    try await r.engine.start()
    await r.engine.pollRig()
    rig.online = false
    await r.engine.pollRig()
    await r.engine.stop()
    var statuses: [RigStatus] = []
    for await e in r.events { if case .rig(let s) = e { statuses.append(s) } }
    #expect(statuses.first == RigStatus(online: true, frequency: 14_080_000, mode: "USB"))
    #expect(statuses.last?.online == false)
}

/// tx() a hned rx() (typicky: odeslat řádek) musí text odvysílat celý, ne ho zahodit.
@Test func rxRequestedDuringPttOnStillTransmitsQueuedText() async throws {
    let r = try makeEngine()
    try await r.engine.start()
    await r.engine.send(text: "CQ DE OK1XOE K ")
    try await r.engine.tx()
    await r.engine.rx()
    await pump(r) { await r.engine.state == .rx }
    let m = try RTTYModem()
    let ev = m.events
    (r.audio.tx + [Float](repeating: 0, count: 4000)).withUnsafeBufferPointer { m.processRx($0) }
    m.finishEvents()
    var text = ""
    for await e in ev { if case .rxText(let c, false) = e { text.append(c) } }
    #expect(text.contains("CQ DE OK1XOE K"))
    await r.engine.stop()
}
