// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AudioIO
import Foundation
import Keying
import MacroEngine
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
    private var drainRequested = false     // rx() přišlo ještě během pttOn
    private var pendingMacros: [MacroResult] = []   // makra zadaná během doběhu – spustí se po návratu do RX
    private var rxBuf = [Float](repeating: 0, count: 4096)
    private var txBuf = [Float](repeating: 0, count: 512)
    private var loopTask: Task<Void, Never>?
    private var rigTask: Task<Void, Never>?
    private var modemTask: Task<Void, Never>?
    private var lastRig: RigStatus?
    /// Zvyšuje se při každém tx/rxNow/stop; po každém await se ověřuje, že příkaz stále platí.
    private var epoch = 0
    private var lastQueued = 0
    private var lastProgressAt: UInt64 = 0
    private var lastReportedPending = -1
    private var lastPendingReportAt: UInt64 = 0
    private static let stallNs: UInt64 = 2_000_000_000   // výstup bez pohybu 2 s = zaseknuté zařízení
    private var everStarted = false

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
        let secs = UInt64(min(max(0, c.seconds), 1_000_000))          // max. ~11 dní, bez přetečení
        return secs * 1_000_000_000 + UInt64(max(0, c.attoseconds / 1_000_000_000))
    }

    // MARK: Start/stop

    public func start() async throws {
        guard !everStarted else { throw EngineError.notRunning }   // Engine je jednorázový
        everStarted = true
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

    private var finished = false

    public func stop() async {
        guard everStarted, !finished else { return }
        if state == .stopped {
            // start selhal (např. zvuk) – jen ukončit proudy událostí, ať odběratelé nečekají věčně
            finished = true
            await ptt?.forceOff()
            modem.finishEvents()
            broadcaster.finish()
            return
        }
        finished = true
        epoch += 1
        let wasTx = state != .rx
        setState(.stopped)                      // hned: souběžné příkazy už nic nespustí
        loopTask?.cancel(); rigTask?.cancel()
        loopTask = nil; rigTask = nil
        if wasTx { modem.abortTx() }
        await stopKeyer()
        await ptt?.forceOff()
        audio.stop()
        for p in ports.values { p.close() }
        // doběhnutí událostí z modemu, pak konec streamů
        modem.finishEvents()
        await modemTask?.value
        modemTask = nil
        broadcaster.finish()
    }

    private func stopKeyer() async {
        guard let k = keyer else { return }
        keyer = nil
        k.stop()
    }

    // MARK: Příkazy

    public func tx() async throws { try await beginTx(tune: false) }
    public func tune() async throws { try await beginTx(tune: true) }

    private func beginTx(tune: Bool) async throws {
        guard state != .stopped else { throw EngineError.notRunning }
        guard state == .rx else { return }                           // idempotence
        if let f = audio.failure { throw EngineError.audio(f) }
        epoch += 1
        let my = epoch
        drainRequested = false
        setState(.keying)
        /// Platí příkaz ještě? (mezitím mohl přijít rxNow/stop/jiný tx)
        func valid() -> Bool { epoch == my && state == .keying }

        if !pttReady {
            let ok = await preparePTT(reportErrors: false)
            guard valid() else { return }
            if !ok {
                setState(.rx)
                throw EngineError.pttUnavailable("PTT \(config.ptt.rawValue) není dostupné")
            }
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
            await stopKeyer()
            setState(.rx)
            throw EngineError.keying("\(error)")
        }
        do {
            try await ptt?.set(true)
        } catch {
            if epoch == my { await stopKeyer() }
            await ptt?.forceOff()
            pttReady = false
            if epoch == my, state == .keying { setState(.rx) }
            throw EngineError.pttUnavailable("\(error)")
        }
        guard valid() else {
            // mezitím rxNow/stop: PTT, které jsme právě zapnuli, hned vypnout
            await ptt?.forceOff()
            return
        }
        tuneMode = tune
        lastQueued = 0
        lastProgressAt = clock.now()
        pttOnAt = clock.now()
        txAt = pttOnAt + nanos(config.txDelay)
        finishedAt = nil
        stopRequested = false
        setState(.pttOn)
    }

    /// RX po dovysílání textu ve frontě.
    public func rx() {
        switch state {
        case .keying, .pttOn: drainRequested = true   // po txDelay rovnou dovysílat a přejít na RX
        case .tx: setState(.drain)
        default: break
        }
    }

    public func rxNow() async {
        pendingMacros.removeAll()
        guard [.keying, .pttOn, .tx, .drain, .pttOff].contains(state) else { return }
        await abortToRx(error: nil)
    }

    private func abortToRx(error: EngineError?) async {
        epoch += 1
        let my = epoch
        modem.abortTx()
        await stopKeyer()
        audio.clearTx()
        finishedAt = nil
        setState(.pttOff)                       // během vypínání nový tx() nic nespustí
        if let error { broadcaster.send(.error(error)) }
        await ptt?.forceOff()
        if epoch == my, state == .pttOff { setState(.rx) }
    }

    public func send(text: String) { modem.queueTx(text: text) }

    public func sendRaw(_ codes: [UInt8]) { modem.queueTxRaw(codes) }

    /// Odešle rozvinuté makro (MMTTY OutputStr): TX, výstupy do fronty, `\` = RX po dovysílání.
    /// Makro do editoru (`#`/`\` na začátku) se neodesílá – to řeší klient; `\` jen zapne TX.
    public func sendMacro(_ m: MacroResult) async throws {
        if m.mode == .toEditor {
            if m.logQSO { broadcaster.send(.logRequested) }
            if m.startsTx { try await tx() }
            return
        }
        // doběh už běží (jádro nepřijímá text) → odložit na nový TX po návratu do RX
        if state == .pttOff || (state == .drain && stopRequested) {
            pendingMacros.append(m)
            return
        }
        if m.logQSO { broadcaster.send(.logRequested) }
        if state == .rx { try await tx() }
        // makro bez '\' ruší plánovaný návrat na RX (MMTTY ToTX)
        if m.end != .rxAfter {
            if state == .drain { setState(.tx) }
            drainRequested = false
        }
        for o in m.outputs {
            switch o {
            case .text(let t): modem.queueTx(text: t)
            case .raw(let r): modem.queueTxRaw(r)
            }
        }
        if m.end == .rxAfter { rx() }
    }

    private func runPendingMacro() async {
        guard state == .rx, !pendingMacros.isEmpty else { return }
        let m = pendingMacros.removeFirst()
        do { try await sendMacro(m) } catch {
            pendingMacros.removeAll()
            broadcaster.send(.error(.pttUnavailable("\(error)")))
        }
    }

    public func clearTx() {
        if state == .tx || state == .drain { modem.abortTx(); modem.beginTx(tune: false) }
    }

    public func withModem<T>(_ body: (any Modem) throws -> T) rethrows -> T { try body(modem) }

    // MARK: DSP krok

    // MARK: Přehrání WAV (MMTTY TSound::Execute: soubor nahrazuje vstup zvukovky)

    private var playback: [Float] = []
    private var playbackPos = 0
    private var playbackSpeed = 1.0

    /// Přehraje vzorky (na frekvenci modemu) místo vstupu zvukovky. Tempo dává vstup (`speed`× reálný čas),
    /// `speed` 0 = co nejrychleji. Během vysílání se přehrávání pozastaví.
    public func startPlayback(_ samples: [Float], speed: Double) {
        playback = samples; playbackPos = 0; playbackSpeed = max(0, speed)
    }
    public func stopPlayback() { playback = []; playbackPos = 0 }
    public var playbackRemaining: Int { playback.count - playbackPos }

    private func feedPlayback(_ k: Int) {
        let end = min(playback.count, playbackPos + max(0, k))
        while playbackPos < end {
            let n = min(1024, end - playbackPos)
            playback.withUnsafeBufferPointer { modem.processRx(UnsafeBufferPointer(rebasing: $0[playbackPos..<(playbackPos + n)])) }
            playbackPos += n
        }
        if playbackPos >= playback.count { stopPlayback() }
    }

    /// Jeden krok zpracování: RX, TX generování, časovače stavového automatu.
    public func pump() async {
        guard state != .stopped else { return }
        // RX (při přehrávání WAV se vstup jen odebere a zahodí; určuje tempo)
        while true {
            let n = audio.readRx(into: &rxBuf)
            if n == 0 { break }
            if playbackRemaining > 0 {
                if state == .rx, playbackSpeed > 0 { feedPlayback(Int((Double(n) * playbackSpeed).rounded())) }
            } else {
                rxBuf.withUnsafeBufferPointer { modem.processRx(UnsafeBufferPointer(rebasing: $0[0..<n])) }
            }
            if n < rxBuf.count { break }
        }
        if playbackRemaining > 0, playbackSpeed == 0, state == .rx { feedPlayback(Int(modem.sampleRate * 10)) }
        let now = clock.now()

        let keyed: Set<EngineState> = [.pttOn, .tx, .drain, .pttOff]
        if keyed.contains(state) {
            // PTT časovač
            if now - pttOnAt > nanos(config.pttTimeout) {
                broadcaster.send(.pttTimeout)
                await abortToRx(error: nil)
                return
            }
            // selhání zvukového zařízení
            if let f = audio.failure {
                await abortToRx(error: .audio(f))
                return
            }
            // zaseknutý výstup: fronta neklesá a nic se nepřidává
            let q = audio.txQueued
            if q == 0 || q < lastQueued { lastProgressAt = now }
            lastQueued = q
            if state != .pttOn, now - lastProgressAt > Self.stallNs {
                await abortToRx(error: .audio("zvukový výstup neodebírá data"))
                return
            }
        }

        switch state {
        case .pttOn:
            if now >= txAt {
                modem.beginTx(tune: tuneMode)
                setState(drainRequested ? .drain : .tx)
                await generate(now: now)
            }
        case .tx, .drain:
            let pend = modem.txPending
            if pend != lastReportedPending, now - lastPendingReportAt >= 200_000_000 || pend == 0 {
                lastReportedPending = pend; lastPendingReportAt = now
                broadcaster.send(.txProgress(pend))
            }
            if state == .drain, !stopRequested, modem.txPending == 0 {
                modem.stopTx(); stopRequested = true
            }
            await generate(now: now)
        case .pttOff:
            let tailDone = (finishedAt ?? 0) + nanos(config.pttTail)
            let hardCap = tailDone + Self.stallNs
            if now >= hardCap {
                await abortToRx(error: .audio("doběh vysílání nedokončen, PTT vypnuto"))
                return
            }
            if now >= tailDone, audio.txQueued == 0, (keyer?.pending ?? 0) == 0 {
                let my = epoch
                await keyer?.finish(timeout: .seconds(3))       // UART buffer dovysílat před PTT off
                guard epoch == my, state == .pttOff else { return }
                await stopKeyer()
                do { try await ptt?.set(false) } catch {
                    await ptt?.forceOff()
                    pttReady = false
                    broadcaster.send(.error(.pttUnavailable("\(error)")))
                }
                if epoch == my, state == .pttOff {
                    setState(.rx)
                    await runPendingMacro()
                }
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
            lastProgressAt = now
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
    public var rigName: String { rig.name }
    /// Probíhá ladění (tune) – pro main.get_trx_status.
    public var isTuning: Bool { tuneMode && [.keying, .pttOn, .tx, .drain].contains(state) }

    public func setRigFrequency(_ hz: Double) async throws {
        do { try await rig.setFrequency(hz) } catch { throw EngineError.rig("\(error)") }
        await pollRig()
    }

    public func setRigMode(_ mode: String) async throws {
        do { try await rig.setMode(mode) } catch { throw EngineError.rig("\(error)") }
        await pollRig()
    }

    // MARK: Modem (Sendable přístup pro AppController/API)

    public func modemParam(_ id: String) -> ParameterValue? { modem.get(parameter: id) }
    public func setModemParam(_ id: String, _ v: ParameterValue) throws { try modem.set(parameter: id, value: v) }
    public func modemParams() -> [String: ParameterValue] {
        var d: [String: ParameterValue] = [:]
        for p in modem.parameters { if let v = modem.get(parameter: p.id) { d[p.id] = v } }
        return d
    }
    public func parameterDescriptors() -> [ParameterDescriptor] { modem.parameters }
    public func modes() -> [ModeDescriptor] { modem.modes }
    public func currentMode() -> ModeDescriptor { modem.currentMode }
    public func selectMode(_ id: String) throws {
        guard let m = modem.modes.first(where: { $0.id == id }) else { throw ParameterError.unknown(id) }
        try modem.select(mode: m)
    }
    public func spectrum() -> SpectrumFrame? { modem.spectrum() }
    public func setXYScope(_ on: Bool) { modem.setXYScope(on) }
    public func xyScope() -> [XYPoint]? { modem.xyScope() }
    public func setDemodScope(_ on: Bool) { modem.setDemodScope(on) }
    public func demodScope(source: Int) -> DemodScope? { modem.demodScope(source: source) }
    public var txPending: Int { modem.txPending }
}
