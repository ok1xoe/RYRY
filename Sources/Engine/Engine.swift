// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AudioIO
import Foundation
import Keying
import MacroEngine
import ModemKit
import RigControl

/// The brain of the app: the RX/TX state machine over the modem, audio, PTT, FSK and rig.
/// The actor serializes all access to the modem. The GUI and the API are equal clients.
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
    private var drainRequested = false     // rx() arrived while still in pttOn
    private var pendingMacros: [MacroResult] = []   // macros entered during the tail – run after the return to RX
    private var rxBuf = [Float](repeating: 0, count: 4096)
    private var txBuf = [Float](repeating: 0, count: 512)
    private var loopTask: Task<Void, Never>?
    private var rigTask: Task<Void, Never>?
    private var modemTask: Task<Void, Never>?
    private var lastRig: RigStatus?
    /// Incremented on every tx/rxNow/stop; after each await it is checked that the command is still valid.
    private var epoch = 0
    private var lastQueued = 0
    private var lastProgressAt: UInt64 = 0
    private var lastReportedPending = -1
    private var lastPendingReportAt: UInt64 = 0
    private static let stallNs: UInt64 = 2_000_000_000   // no movement on the output for 2 s = a stuck device
    private var everStarted = false
    /// Auxiliary decoders (the second decoder, the channels) – their own queue, receive only.
    private let auxFactory: (@Sendable () -> (any Modem)?)?
    private var aux: AuxDecoderHub?
    private var auxConfig = AuxDecoderConfig()
    private var auxSpectrumSamples = 0
    private let auxMaxBacklog: Int?

    /// `auxModemFactory`: creates the modems for the second decoder and the channels (nil = feature unavailable).
    public init(modem: sending any Modem, rig: Rig = NoRig(), audio: AudioBackend, config: EngineConfig,
                serialFactory: @escaping @Sendable (String) -> SerialPort = { POSIXSerialPort(path: $0) },
                clock: Clock = HostClock(), autoRun: Bool = true,
                auxModemFactory: (@Sendable () -> (any Modem)?)? = nil, auxMaxBacklog: Int? = nil) {
        self.modem = modem; self.rig = rig; self.audio = audio; self.config = config
        self.serialFactory = serialFactory; self.clock = clock; self.autoRun = autoRun
        self.auxFactory = auxModemFactory; self.auxMaxBacklog = auxMaxBacklog
    }

    /// A new event subscriber (broadcast).
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
        let secs = UInt64(min(max(0, c.seconds), 1_000_000))          // max. ~11 days, without overflow
        return secs * 1_000_000_000 + UInt64(max(0, c.attoseconds / 1_000_000_000))
    }

    // MARK: Start/stop

    public func start() async throws {
        guard !everStarted else { throw EngineError.notRunning }   // the Engine is single-use
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
        syncAux()
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
            // the start failed (e.g. audio) – just finish the event streams so subscribers do not wait forever
            finished = true
            await ptt?.forceOff()
            await rig.disconnect()
            modem.finishEvents()
            broadcaster.finish()
            return
        }
        finished = true
        epoch += 1
        let wasTx = state != .rx
        setState(.stopped)                      // right away: concurrent commands start nothing more
        loopTask?.cancel(); rigTask?.cancel()
        loopTask = nil; rigTask = nil
        if wasTx { modem.abortTx() }
        await stopKeyer()
        await ptt?.forceOff()
        audio.stop()
        for p in ports.values { p.close() }
        await rig.disconnect()                   // release the CAT port / stop the started rigctld (only after PTT off)
        // let the modem events drain, then finish the streams
        modem.finishEvents()
        await modemTask?.value
        modemTask = nil
        await stopAux()
        broadcaster.finish()
    }

    private func stopKeyer() async {
        guard let k = keyer else { return }
        keyer = nil
        k.stop()
    }

    // MARK: Commands

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
        /// Is the command still valid? (an rxNow/stop/another tx may have arrived meanwhile)
        func valid() -> Bool { epoch == my && state == .keying }

        if !pttReady {
            let ok = await preparePTT(reportErrors: false)
            guard valid() else { return }
            if !ok {
                setState(.rx)
                throw EngineError.pttUnavailable("PTT \(config.ptt.rawValue) není dostupné")
            }
        }
        // the FSK line to mark even before PTT
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
            // rxNow/stop in the meantime: switch off the PTT we have just switched on
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

    /// RX once the text in the queue has been transmitted.
    public func rx() {
        switch state {
        case .keying, .pttOn: drainRequested = true   // after txDelay transmit the rest and go to RX
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
        setState(.pttOff)                       // while switching off, a new tx() starts nothing
        if let error { broadcaster.send(.error(error)) }
        await ptt?.forceOff()
        if epoch == my, state == .pttOff { setState(.rx) }
    }

    public func send(text: String) { modem.queueTx(text: text) }

    public func sendRaw(_ codes: [UInt8]) { modem.queueTxRaw(codes) }

    /// Sends an expanded macro (MMTTY OutputStr): TX, the outputs into the queue, `\` = RX once transmitted.
    /// A macro for the editor (`#`/`\` at the start) is not sent – the client handles that; `\` only switches on TX.
    public func sendMacro(_ m: MacroResult) async throws {
        if m.mode == .toEditor {
            if m.logQSO { broadcaster.send(.logRequested) }
            if m.startsTx { try await tx() }
            return
        }
        // a macro without text (empty, only %l) does not key – TX would hang forever; `#` at the end = TX on purpose
        if state == .rx, m.end != .keepTx, m.outputs.allSatisfy(\.isEmpty) {
            if m.logQSO { broadcaster.send(.logRequested) }
            return
        }
        // the tail is already running (the core takes no text) → defer to a new TX after the return to RX
        if state == .pttOff || (state == .drain && stopRequested) {
            pendingMacros.append(m)
            return
        }
        if m.logQSO { broadcaster.send(.logRequested) }
        if state == .rx { try await tx() }
        // a macro without '\' cancels the planned return to RX (MMTTY ToTX)
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

    // MARK: DSP step

    // MARK: WAV playback (MMTTY TSound::Execute: the file replaces the sound card input)

    private var playback: [Float] = []
    private var playbackPos = 0
    private var playbackSpeed = 1.0

    /// Plays samples (at the modem rate) instead of the sound card input. The input sets the pace (`speed`× real time),
    /// `speed` 0 = as fast as possible. Playback is paused while transmitting.
    public func startPlayback(_ samples: [Float], speed: Double) {
        playback = samples; playbackPos = 0; playbackSpeed = max(0, speed)
    }
    public func stopPlayback() { playback = []; playbackPos = 0; playbackPaused = false }
    public var playbackRemaining: Int { playback.count - playbackPos }
    public var playbackPosition: Int { playbackPos }
    public var playbackTotal: Int { playback.count }
    /// Playback pause (the sound card input keeps being discarded, like MMTTY "Pause").
    public private(set) var playbackPaused = false
    public func setPlaybackPaused(_ p: Bool) { playbackPaused = p && !playback.isEmpty }
    /// Seek to a fraction of the file 0…1 (0 = rewind to the start).
    public func seekPlayback(toFraction f: Double) {
        guard !playback.isEmpty else { return }
        playbackPos = min(playback.count - 1, max(0, Int((Double(playback.count) * f).rounded(.down))))
    }

    // MARK: Input recording (MMTTY "Record WAVE") – the app consumes the samples at the modem rate

    private var recording: [Float]?
    public var isRecording: Bool { recording != nil }
    public func setRecording(_ on: Bool) { recording = on ? (recording ?? []) : nil }
    /// Takes the samples recorded so far.
    public func drainRecording() -> [Float] {
        guard let r = recording else { return [] }
        recording = []
        return r
    }

    private func feedPlayback(_ k: Int) {
        let end = min(playback.count, playbackPos + max(0, k))
        while playbackPos < end {
            let n = min(1024, end - playbackPos)
            playback.withUnsafeBufferPointer {
                let b = UnsafeBufferPointer(rebasing: $0[playbackPos..<(playbackPos + n)])
                modem.processRx(b)
                feedAux(b)
            }
            playbackPos += n
        }
        if playbackPos >= playback.count { stopPlayback() }
    }

    /// One processing step: RX, TX generation, the state machine timers.
    public func pump() async {
        guard state != .stopped else { return }
        // RX (during WAV playback the input is only consumed and discarded; it sets the pace)
        while true {
            let n = audio.readRx(into: &rxBuf)
            if n == 0 { break }
            if playbackRemaining > 0 {
                if state == .rx, playbackSpeed > 0, !playbackPaused { feedPlayback(Int((Double(n) * playbackSpeed).rounded())) }
            } else {
                if recording != nil { recording!.append(contentsOf: rxBuf[0..<n]) }
                rxBuf.withUnsafeBufferPointer {
                    let b = UnsafeBufferPointer(rebasing: $0[0..<n])
                    modem.processRx(b)
                    feedAux(b)
                }
            }
            if n < rxBuf.count { break }
        }
        if playbackRemaining > 0, playbackSpeed == 0, state == .rx, !playbackPaused { feedPlayback(Int(modem.sampleRate * 10)) }
        let now = clock.now()

        let keyed: Set<EngineState> = [.pttOn, .tx, .drain, .pttOff]
        if keyed.contains(state) {
            // PTT timer
            if now - pttOnAt > nanos(config.pttTimeout) {
                broadcaster.send(.pttTimeout)
                await abortToRx(error: nil)
                return
            }
            // audio device failure
            if let f = audio.failure {
                await abortToRx(error: .audio(f))
                return
            }
            // stuck output: the queue does not drop and nothing is added
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
                await keyer?.finish(timeout: .seconds(3))       // let the UART buffer finish before PTT off
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

    // MARK: Auxiliary decoders

    /// Switches the second decoder and the channels on/off (at run time, without a restart).
    public func setAuxDecoders(_ c: AuxDecoderConfig) {
        auxConfig = c
        syncAux()
    }
    public var auxDecoders: AuxDecoderConfig { auxConfig }

    /// Waits until the auxiliary decoders have processed all audio received so far (stop() drops the rest).
    public func flushAuxDecoders() async { await aux?.flush() }

    private func syncAux() {
        guard state != .stopped, !finished, let f = auxFactory else { return }
        if aux == nil, auxConfig.isActive {
            let b = broadcaster
            aux = AuxDecoderHub(sampleRate: modem.sampleRate, maxBacklog: auxMaxBacklog, factory: f) { b.send(.aux($0)) }
        }
        aux?.configure(auxConfig)
    }

    private func stopAux() async {
        guard let a = aux else { return }
        aux = nil
        await a.stop()
    }

    /// A copy of the block for the auxiliary decoders – only during RX (paused during TX like the main one).
    private func feedAux(_ b: UnsafeBufferPointer<Float>) {
        guard let aux, auxConfig.isActive, state == .rx, b.count > 0 else { return }
        var spec: SpectrumFrame?
        if auxConfig.channelsEnabled {
            auxSpectrumSamples += b.count
            if auxSpectrumSamples >= Int(modem.sampleRate / 10) { auxSpectrumSamples = 0; spec = modem.spectrum() }
        }
        aux.feed(Array(b), tuning: auxTuning(), spectrum: spec)
    }

    private func auxTuning() -> AuxTuning {
        var t = AuxTuning()
        if case .double(let v)? = modem.get(parameter: "mark") { t.mark = v }
        if case .double(let v)? = modem.get(parameter: "shift") { t.shift = v }
        if case .double(let v)? = modem.get(parameter: "baud") { t.baud = v }
        if case .bool(let v)? = modem.get(parameter: "reverse") { t.reverse = v }
        if case .string(let v)? = modem.get(parameter: "demodType") { t.demodType = v }
        return t
    }

    /// For tests: wait for the sent blocks to be processed; the queue state.
    func auxFlush() async { await aux?.flush() }
    var auxModemCount: Int { aux?.modemCount ?? 0 }
    var auxDropped: Int { aux?.dropped ?? 0 }

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
    /// Tuning (tune) is in progress – for main.get_trx_status.
    public var isTuning: Bool { tuneMode && [.keying, .pttOn, .tx, .drain].contains(state) }

    public func setRigFrequency(_ hz: Double) async throws {
        do { try await rig.setFrequency(hz) } catch { throw EngineError.rig("\(error)") }
        await pollRig()
    }

    public func setRigMode(_ mode: String) async throws {
        do { try await rig.setMode(mode) } catch { throw EngineError.rig("\(error)") }
        await pollRig()
    }

    // MARK: Modem (Sendable access for AppController/API)

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
    public func demodScope() -> DemodScope? { modem.demodScope() }
    public var txPending: Int { modem.txPending }
}
