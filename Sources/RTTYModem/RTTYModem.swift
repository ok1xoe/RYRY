import MMTTYCore
import ModemKit

/// RTTY modem nad jádrem MMTTY (C API `rttycore_*`).
///
/// Není thread-safe: DSP metody (`processRx`, `generateTx`, `spectrum`) i řídicí metody musí volat
/// jeden sériový kontext (Engine). `events` lze číst odkudkoli.
public final class RTTYModem: Modem, @unchecked Sendable {
    public enum CodeSet: Sendable { case us, japanese }
    public struct Config: Sendable {
        public var codeSet: CodeSet = .us
        public var doubleShift = false
        public var txUOS = true
        public var txOffset = 0.0
        public init() {}
    }
    public enum Error: Swift.Error, Equatable {
        case unsupportedSampleRate(Double), parameter(ParameterError)
    }

    public static let id = "rtty"
    public let modes: [ModeDescriptor] = [
        .init(id: "RTTY-45", displayName: "RTTY 45.45 Bd", adifMode: "RTTY"),
        .init(id: "RTTY-50", displayName: "RTTY 50 Bd", adifMode: "RTTY"),
        .init(id: "RTTY-75", displayName: "RTTY 75 Bd", adifMode: "RTTY"),
        .init(id: "RTTY-100", displayName: "RTTY 100 Bd", adifMode: "RTTY"),
        .init(id: "RTTY-110", displayName: "RTTY 110 Bd", adifMode: "RTTY"),
    ]
    static let modeBaud: [String: Double] = ["RTTY-45": 45.45, "RTTY-50": 50, "RTTY-75": 75,
                                             "RTTY-100": 100, "RTTY-110": 110]
    public private(set) var currentMode: ModeDescriptor
    public let sampleRate: Double
    public let capabilities: ModemCapabilities = [.fskKeying, .afc, .textOutput]
    public var parameters: [ParameterDescriptor] { RTTYParameters.descriptors }
    public let events: AsyncStream<ModemEvent>

    private let core: OpaquePointer
    private let continuation: AsyncStream<ModemEvent>.Continuation
    private var samplesSinceTick = 0
    private let tickInterval: Int
    /// Fronta čekající na místo v jádře; text a surové kódy ve správném pořadí.
    private enum TxItem { case text([UInt8]), raw([UInt8]) }
    private var txItems: [TxItem] = []
    private var txWasActive = false
    private var lastFig = false
    private var lastTuning: TuningInfo
    private var charBuf = [RTTYCoreChar](repeating: RTTYCoreChar(), count: 256)

    public init(sampleRate: Double = 11025, config: Config = .init()) throws(Error) {
        var cfg = rttycore_default_config()
        cfg.sampleRate = sampleRate
        cfg.codeSet = config.codeSet == .us ? 0 : 1
        cfg.doubleShift = config.doubleShift ? 1 : 0
        cfg.txUOS = config.txUOS ? 1 : 0
        cfg.txOffset = config.txOffset
        guard let c = rttycore_create(&cfg) else { throw .unsupportedSampleRate(sampleRate) }
        core = c
        self.sampleRate = sampleRate
        tickInterval = max(1, Int(sampleRate / 10))
        currentMode = modes[0]
        lastTuning = TuningInfo(mark: rttycore_get_param(c, RC_MARK), space: rttycore_get_param(c, RC_SPACE))
        // Neomezený buffer: pomalý odběratel nesmí přijít o přijatý text (Engine events vždy odebírá).
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    deinit {
        continuation.finish()
        rttycore_destroy(core)
    }

    /// Ukončí proud událostí (např. na konci dekódování souboru).
    public func finishEvents() { continuation.finish() }

    public func select(mode: ModeDescriptor) throws {
        guard let baud = Self.modeBaud[mode.id] else { throw Error.parameter(.unknown(mode.id)) }
        try set(parameter: "baud", value: .double(baud))
        currentMode = mode
    }

    public func set(parameter id: String, value: ParameterValue) throws {
        guard let (d, _) = RTTYParameters.entry(id) else { throw Error.parameter(.unknown(id)) }
        do {
            let v = try d.validate(value)
            try RTTYParameters.apply(id: id, value: v, core: core)
        } catch { throw Error.parameter(error) }
        if id == "baud", case .double(let b)? = get(parameter: "baud"),
           let m = modes.first(where: { abs((Self.modeBaud[$0.id] ?? 0) - b) < 0.01 }) { currentMode = m }
        publishTuningIfChanged()
    }

    public func get(parameter id: String) -> ParameterValue? {
        RTTYParameters.read(id: id, core: core)
    }

    public func processRx(_ samples: UnsafeBufferPointer<Float>) {
        guard let base = samples.baseAddress else { return }
        var offset = 0
        while offset < samples.count {
            let n = min(samples.count - offset, tickInterval - samplesSinceTick)
            rttycore_process_rx(core, base + offset, n)
            offset += n
            samplesSinceTick += n
            if samplesSinceTick >= tickInterval {
                samplesSinceTick = 0
                _ = rttycore_tick(core)
                publishStatus()
            }
            drainChars()
        }
    }

    private func drainChars() {
        while true {
            let got = charBuf.withUnsafeMutableBufferPointer {
                rttycore_read_chars(core, $0.baseAddress!, $0.count)
            }
            if got == 0 { break }
            for k in 0..<got {
                let ch = Character(UnicodeScalar(UInt8(bitPattern: charBuf[k].ch)))
                continuation.yield(.rxText(ch, echo: charBuf[k].echo != 0))
            }
        }
    }

    private func publishTuningIfChanged() {
        let t = TuningInfo(mark: rttycore_get_param(core, RC_MARK), space: rttycore_get_param(core, RC_SPACE))
        if t != lastTuning { lastTuning = t; continuation.yield(.tuning(t)) }
    }

    private func publishStatus() {
        let s = rttycore_signal(core)
        continuation.yield(.signal(level: s.level, squelchOpen: s.squelchOpen != 0))
        if s.overflow != 0 { continuation.yield(.overflow) }
        publishTuningIfChanged()
        let fig = s.fig != 0
        if fig != lastFig { lastFig = fig; continuation.yield(.shift(fig: fig)) }
    }

    public func beginTx(tune: Bool) {
        // Text zadaný před beginTx (makro, pak TX) se neztrácí.
        rttycore_tx_begin(core, tune ? 1 : 0)
        txWasActive = true
    }

    public func queueTx(text: String) {
        let bytes = text.utf8.filter { $0 != 0 }   // NUL by v C řetězci zablokoval frontu
        if !bytes.isEmpty { txItems.append(.text(bytes)) }
        feedCore()
    }

    public func queueTxRaw(_ codes: [UInt8]) {
        // LTRS/FIGS jdou textovou cestou (jádro si zapamatuje registr, jako MMTTY %L/%F)
        var run: [UInt8] = []
        for c in codes {
            if c == 0x1B || c == 0x1F {
                if !run.isEmpty { txItems.append(.raw(run)); run = [] }
                txItems.append(.text([c]))
            } else { run.append(c) }
        }
        if !run.isEmpty { txItems.append(.raw(run)) }
        feedCore()
    }

    private func feedCore() {
        while let first = txItems.first {
            switch first {
            case .text(let bytes):
                var chunk = bytes.prefix(256).map { CChar(bitPattern: $0) } + [0]
                let used = rttycore_queue_tx(core, &chunk)
                if used == 0 { return }
                let rest = Array(bytes.dropFirst(used))
                if rest.isEmpty { txItems.removeFirst() } else { txItems[0] = .text(rest) }
            case .raw(let codes):
                let used = codes.withUnsafeBufferPointer { rttycore_queue_tx_raw(core, $0.baseAddress, $0.count) }
                if used == 0 { return }
                let rest = Array(codes.dropFirst(used))
                if rest.isEmpty { txItems.removeFirst() } else { txItems[0] = .raw(rest) }
            }
        }
    }

    public func generateTx(into buffer: UnsafeMutableBufferPointer<Float>) -> TxStatus {
        guard let base = buffer.baseAddress else { return rttycore_is_tx(core) != 0 ? .active : .finished }
        feedCore()
        let n = rttycore_generate_tx(core, base, buffer.count)
        drainChars()                                   // echo odvysílaného textu
        if n < buffer.count {
            if txWasActive { txWasActive = false; continuation.yield(.txFinished) }
            return .finished
        }
        return .active
    }

    public func stopTx() { txItems.removeAll(); rttycore_tx_stop(core) }

    public func abortTx() {
        txItems.removeAll()
        rttycore_tx_abort(core)
        if txWasActive { txWasActive = false; continuation.yield(.txFinished) }
    }

    public var txPending: Int {
        txItems.reduce(0) { n, i in if case .text(let b) = i { return n + b.count }; if case .raw(let r) = i { return n + r.count }; return n }
            + rttycore_tx_pending(core)
    }

    public func takeFskCodes() -> [UInt8] {
        var out: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 64)
        while true {
            let n = rttycore_read_fsk_codes(core, &buf, buf.count)
            if n == 0 { break }
            out += buf[0..<n]
        }
        return out
    }

    /// XY scope (mark/space) – zapnout sběr.
    public func setXYScope(_ on: Bool) { rttycore_set_xy(core, on ? 1 : 0) }

    /// Poslední plná dávka bodů XY scope (x = mark, y = space), nebo nil.
    public func xyScope() -> [XYPoint]? {
        var x = [Float](repeating: 0, count: 512), y = x
        let n = rttycore_read_xy(core, &x, &y, 512)
        guard n > 0 else { return nil }
        return (0..<n).map { XYPoint(x: x[$0], y: y[$0]) }
    }

    public func spectrum() -> SpectrumFrame? {
        var mags = [Float](repeating: 0, count: 2048)
        var binHz = 0.0
        let n = rttycore_spectrum(core, &mags, mags.count, &binHz)
        guard n > 0 else { return nil }
        return SpectrumFrame(binHz: binHz, magnitudes: Array(mags[0..<n]))
    }
}
