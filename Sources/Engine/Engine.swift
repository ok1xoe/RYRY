// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AudioIO
import Foundation
import Keying
import ModemKit
import RigControl

/// Mozek aplikace: RX/TX stavový automat nad modemem, zvukem, PTT, FSK a rigem.
/// Actor serializuje veškerý přístup k modemu. GUI i API jsou rovnocenní klienti.
public actor Engine {
    private let modem: any Modem
    private let rig: Rig
    private let audio: AudioBackend
    private let config: EngineConfig
    private let serialFactory: @Sendable (String) -> SerialPort
    private let clock: Clock
    private let autoRun: Bool
    private let broadcaster = EventBroadcaster()

    public private(set) var state: EngineState = .stopped
    private var ports: [String: SerialPort] = [:]
    private var ptt: PTTController?
    private var pttReady = false
    private var keyer: FSKKeyer?
    private var tuneMode = false
    private var pttOnAt: UInt64 = 0
    private var txAt: UInt64 = 0
    private var finishedAt: UInt64?
    private var stopRequested = false
    private var rxBuf = [Float](repeating: 0, count: 4096)
    private var txBuf = [Float](repeating: 0, count: 512)
    private var loopTask: Task<Void, Never>?
    private var rigTask: Task<Void, Never>?
    private var modemTask: Task<Void, Never>?
    private var lastRig: RigStatus?

    public init(modem: sending any Modem, rig: Rig = NoRig(), audio: AudioBackend, config: EngineConfig,
                serialFactory: @escaping @Sendable (String) -> SerialPort = { POSIXSerialPort(path: $0) },
                clock: Clock = HostClock(), autoRun: Bool = true) {
        self.modem = modem; self.rig = rig; self.audio = audio; self.config = config
        self.serialFactory = serialFactory; self.clock = clock; self.autoRun = autoRun
    }

    /// Nový odběratel událostí (broadcast).
    public nonisolated func events() -> AsyncStream<EngineEvent> { broadcaster.subscribe() }

    private func setState(_ s: EngineState) {
        guard s != state else { return }
        state = s
        broadcaster.send(.state(s))
    }

    private func port(_ path: String) -> SerialPort {
        if let p = ports[path] { return p }
        let p = serialFactory(path); ports[path] = p; return p
    }

    private func nanos(_ d: Duration) -> UInt64 {
        let c = d.components
        return UInt64(max(0, c.seconds)) * 1_000_000_000 + UInt64(max(0, c.attoseconds / 1_000_000_000))
    }

    // MARK: Start/stop

    public func start() async throws {
        guard state == .stopped else { return }
        do { try audio.start(modemRate: modem.sampleRate, config: config.audio) }
        catch { throw EngineError.audio("\(error)") }
        let portForPTT: SerialPort? = config.pttPort.map { port($0) }
        ptt = PTTController(method: config.ptt, port: portForPTT, rig: rig, invert: config.pttInvert)
        await preparePTT(reportErrors: true)
        let stream = modem.events
        let b = broadcaster
        modemTask = Task.detached { for await e in stream { b.send(.modem(e)) } }
        setState(.rx)
        if autoRun {
            loopTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.pump()
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            let interval = config.rigPollInterval
            rigTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.pollRig()
                    try? await Task.sleep(for: interval)
                }
            }
        }
    }

    @discardableResult
    private func preparePTT(reportErrors: Bool) async -> Bool {
        guard let ptt else { return false }
        do {
            try await ptt.prepare()
            pttReady = true
        } catch {
            pttReady = false
            if reportErrors { broadcaster.send(.error(.pttUnavailable("\(error)"))) }
        }
        return pttReady
    }

    public func stop() async {
        guard state != .stopped else { return }
        loopTask?.cancel(); rigTask?.cancel()
        loopTask = nil; rigTask = nil
        if state != .rx { modem.abortTx() }
        keyer?.stop(); keyer = nil
        await ptt?.forceOff()
        audio.stop()
        for p in ports.values { p.close() }
        setState(.stopped)
        // doběhnutí událostí z modemu, pak konec streamů
        modem.finishEvents()
        await modemTask?.value
        modemTask = nil
        broadcaster.finish()
    }

    // MARK: Příkazy

    public func tx() async throws { try await beginTx(tune: false) }
    public func tune() async throws { try await beginTx(tune: true) }

    private func beginTx(tune: Bool) async throws {
        guard state != .stopped else { throw EngineError.notRunning }
        guard state == .rx else { return }                           // idempotence
        if !pttReady, !(await preparePTT(reportErrors: false)) {
            throw EngineError.pttUnavailable("PTT \(config.ptt.rawValue) není dostupné")
        }
        // FSK linka na mark ještě před PTT
        do {
            switch config.txOutput {
            case .afsk: keyer = nil
            case .fskUART(let path):
                keyer = UARTFSKKeyer(port: port(path), invert: config.fskInvert)
            case .fskSoft(let path, let line):
                keyer = SoftFSKKeyer(port: port(path), line: line, invert: config.fskInvert, clock: clock)
            }
            try keyer?.start()
        } catch {
            keyer?.stop(); keyer = nil
            throw EngineError.keying("\(error)")
        }
        do {
            try await ptt?.set(true)
        } catch {
            keyer?.stop(); keyer = nil
            await ptt?.forceOff()
            pttReady = false
            throw EngineError.pttUnavailable("\(error)")
        }
        tuneMode = tune
        pttOnAt = clock.now()
        txAt = pttOnAt + nanos(config.txDelay)
        finishedAt = nil
        stopRequested = false
        setState(.pttOn)
    }

    /// RX po dovysílání textu ve frontě.
    public func rx() {
        switch state {
        case .pttOn: rxNowSync(reason: nil)
        case .tx: setState(.drain)
        default: break
        }
    }

    public func rxNow() async {
        guard [.pttOn, .tx, .drain, .pttOff].contains(state) else { return }
        await abortToRx(error: nil)
    }

    private func rxNowSync(reason: EngineError?) {
        // pro volání ze synchronního kontextu: PTT se vypne v dalším kroku pump()
        modem.abortTx()
        keyer?.stop()
        audio.clearTx()
        finishedAt = 0
        setState(.pttOff)
        if let reason { broadcaster.send(.error(reason)) }
    }

    private func abortToRx(error: EngineError?) async {
        modem.abortTx()
        keyer?.stop(); keyer = nil
        audio.clearTx()
        await ptt?.forceOff()
        finishedAt = nil
        setState(.rx)
        if let error { broadcaster.send(.error(error)) }
    }

    public func send(text: String) { modem.queueTx(text: text) }

    public func clearTx() {
        if state == .tx || state == .drain { modem.abortTx(); modem.beginTx(tune: false) }
    }

    public func withModem<T>(_ body: (any Modem) throws -> T) rethrows -> T { try body(modem) }

    // MARK: DSP krok

    /// Jeden krok zpracování: RX, TX generování, časovače stavového automatu.
    public func pump() async {
        guard state != .stopped else { return }
        // RX
        while true {
            let n = audio.readRx(into: &rxBuf)
            if n == 0 { break }
            rxBuf.withUnsafeBufferPointer { modem.processRx(UnsafeBufferPointer(rebasing: $0[0..<n])) }
            if n < rxBuf.count { break }
        }
        let now = clock.now()

        // PTT časovač
        if [.pttOn, .tx, .drain].contains(state), now - pttOnAt > nanos(config.pttTimeout) {
            broadcaster.send(.pttTimeout)
            await abortToRx(error: nil)
            return
        }

        switch state {
        case .pttOn:
            if now >= txAt {
                modem.beginTx(tune: tuneMode)
                setState(.tx)
                await generate(now: now)
            }
        case .tx, .drain:
            if state == .drain, !stopRequested, modem.txPending == 0 {
                modem.stopTx(); stopRequested = true
            }
            await generate(now: now)
        case .pttOff:
            let tailDone = (finishedAt ?? 0) + nanos(config.pttTail)
            if now >= tailDone, audio.txQueued == 0, (keyer?.pending ?? 0) == 0 {
                keyer?.stop(); keyer = nil
                do { try await ptt?.set(false) } catch {
                    await ptt?.forceOff()
                    pttReady = false
                    broadcaster.send(.error(.pttUnavailable("\(error)")))
                }
                setState(.rx)
            }
        default: break
        }
    }

    private func generate(now: UInt64) async {
        let fsk = keyer != nil
        let target = Int(modem.sampleRate * 0.15)
        var blocks = 0
        while audio.txQueued < target && blocks < 8 {
            let st = txBuf.withUnsafeMutableBufferPointer { modem.generateTx(into: $0) }
            if fsk {
                let codes = modem.takeFskCodes()
                keyer?.send(codes: codes)
                if let e = (keyer as? UARTFSKKeyer)?.lastError ?? (keyer as? SoftFSKKeyer)?.lastError {
                    await abortToRx(error: .keying("\(e)"))
                    return
                }
                if !config.audioDuringFSK { for i in txBuf.indices { txBuf[i] = 0 } }
            }
            _ = audio.writeTx(txBuf)
            blocks += 1
            if st == .finished {
                finishedAt = now
                setState(.pttOff)
                return
            }
        }
    }

    // MARK: Rig

    public func pollRig() async {
        var s = RigStatus(online: false)
        do {
            let f = try await rig.frequency()
            let m = try? await rig.mode()
            s = RigStatus(online: true, frequency: f, mode: m)
        } catch {
            s = RigStatus(online: false)
        }
        if s != lastRig { lastRig = s; broadcaster.send(.rig(s)) }
    }

    public var rigStatus: RigStatus? { lastRig }
}
