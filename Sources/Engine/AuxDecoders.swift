// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import ModemKit

/// Doplňkové dekodéry: druhý dekodér (jiný demodulátor na stejném naladění jako hlavní)
/// a vícekanálové dekódování (samostatné dekodéry na signálech nalezených ve spektru).
public struct AuxDecoderConfig: Sendable, Equatable {
    public static let demodTypes = ["iir", "fir", "pll", "fft"]
    public static let maxChannelLimit = 8

    public var secondEnabled = false
    /// Demodulátor druhého dekodéru; nil = automaticky jiný než hlavní (hlavní IIR → FFT, jinak IIR).
    public var secondDemod: String?
    public var channelsEnabled = false
    public var maxChannels = 4
    /// Kanál zaniká po tolika sekundách bez signálu.
    public var channelTimeout: Double = 15
    /// Rozsah hledání signálů (Hz).
    public var fromHz = 200.0, toHz = 3000.0
    public init() {}

    public var isActive: Bool { secondEnabled || channelsEnabled }
    var clampedChannels: Int { min(Self.maxChannelLimit, max(1, maxChannels)) }
    var clampedTimeout: Double { channelTimeout.isFinite ? min(600, max(1, channelTimeout)) : 15 }

    /// Demodulátor druhého dekodéru pro daný typ hlavního.
    public func resolvedSecondDemod(main: String) -> String {
        if let d = secondDemod, Self.demodTypes.contains(d) { return d }
        return main == "iir" ? "fft" : "iir"
    }
}

/// Naladění hlavního dekodéru, které doplňkové dekodéry sledují.
public struct AuxTuning: Sendable, Equatable {
    public var mark: Double, shift: Double, baud: Double, reverse: Bool, demodType: String
    public init(mark: Double = 2125, shift: Double = 170, baud: Double = 45.45, reverse: Bool = false, demodType: String = "iir") {
        self.mark = mark; self.shift = shift; self.baud = baud; self.reverse = reverse; self.demodType = demodType
    }
}

/// Kanál vícekanálového dekodéru (id je stálé po dobu života kanálu).
public struct DecoderChannelInfo: Sendable, Equatable, Identifiable {
    public let id: Int
    public var mark: Double
    public init(id: Int, mark: Double) { self.id = id; self.mark = mark }
}

public enum AuxEvent: Sendable, Equatable {
    /// Znak z druhého dekodéru.
    case secondText(Character)
    /// Znak z kanálu `id`.
    case channelText(id: Int, Character)
    /// Aktuální seznam kanálů (při vzniku/zániku kanálu nebo posunu AFC ≥ 1 Hz).
    case channels([DecoderChannelInfo])
}

/// Doplňkové modemy běží na vlastní sériové frontě mimo actor Engine – hlavní příjem nebrzdí.
/// Engine sem posílá kopie přijatých bloků; když fronta nestíhá (víc než `maxBacklog` vzorků), bloky se zahazují.
/// Modemy jen přijímají (nikdy nevysílají).
final class AuxDecoderHub: @unchecked Sendable {
    typealias Factory = @Sendable () -> (any Modem)?

    private let queue = DispatchQueue(label: "cz.ok1xoe.mmtty4mac.aux-decoders", qos: .userInitiated)
    private let factory: Factory
    private let emit: @Sendable (AuxEvent) -> Void
    private let sampleRate: Double
    private let maxBacklog: Int

    // chráněno zámkem
    private let lock = NSLock()
    private var backlog = 0
    private var droppedSamples = 0
    private var stopped = false
    private var consumers: [UUID: Task<Void, Never>] = [:]
    private var liveModems = 0

    // jen na frontě
    private final class Decoder {
        let modem: any Modem
        var applied: AuxTuning?
        init(_ m: any Modem) { modem = m }
    }
    private struct Channel {
        let id: Int
        let dec: Decoder
        var mark: Double
        var lastSeen: Double
    }
    private var config = AuxDecoderConfig()
    private var second: (dec: Decoder, demod: String)?
    private var channels: [Channel] = []
    private var detector = RTTYSignalDetector()
    private var samples = 0
    private var nextId = 1
    private var reported: [DecoderChannelInfo] = []

    init(sampleRate: Double, maxBacklog: Int? = nil, factory: @escaping Factory, emit: @escaping @Sendable (AuxEvent) -> Void) {
        self.sampleRate = sampleRate
        self.maxBacklog = maxBacklog ?? Int(sampleRate * 20)
        self.factory = factory; self.emit = emit
    }

    /// Počet vzorků zahozených kvůli přetížení.
    var dropped: Int { lock.withLock { droppedSamples } }
    /// Počet existujících doplňkových modemů (pro testy úniku).
    var modemCount: Int { lock.withLock { liveModems } }
    var consumerCount: Int { lock.withLock { consumers.count } }

    func configure(_ c: AuxDecoderConfig) {
        guard lock.withLock({ !stopped }) else { return }
        queue.async { self.apply(c) }
    }

    /// Kopie přijatého bloku + naladění hlavního dekodéru (+ spektrum pro detekci kanálů).
    func feed(_ block: [Float], tuning: AuxTuning, spectrum: SpectrumFrame?) {
        let n = block.count
        let ok = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            if backlog + n > maxBacklog { droppedSamples += n; return false }
            backlog += n
            return true
        }
        guard ok else { return }
        queue.async {
            // po stop() zbylé bloky jen zahodit (jinak by zastavení čekalo na zpracování až 20 s audia)
            if !self.lock.withLock({ self.stopped }) { self.process(block, tuning: tuning, spectrum: spectrum) }
            self.lock.withLock { self.backlog -= n }
        }
    }

    /// Počká na zpracování všech dosud zaslaných bloků.
    func flush() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in queue.async { c.resume() } }
    }

    /// Zpracuje frontu, ukončí všechny modemy a počká na doručení jejich textu.
    func stop() async {
        lock.withLock { stopped = true }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async {
                self.removeSecond()
                for ch in self.channels { self.retire(ch.dec) }
                self.channels.removeAll()
                c.resume()
            }
        }
        while true {
            let pending = lock.withLock { Array(consumers.values) }
            if pending.isEmpty { break }
            for t in pending { await t.value }
        }
    }

    // MARK: Fronta

    private func apply(_ c: AuxDecoderConfig) {
        config = c
        if !c.secondEnabled { removeSecond() }
        if !c.channelsEnabled {
            for ch in channels { retire(ch.dec) }
            channels.removeAll(); detector.reset()
        } else {
            while channels.count > c.clampedChannels { retire(channels.removeLast().dec) }
        }
        report()
    }

    private func makeDecoder(_ onChar: @escaping @Sendable (Character) -> AuxEvent) -> Decoder? {
        guard let m = factory() else { return nil }
        let stream = m.events
        let key = UUID()
        let emit = self.emit
        lock.withLock {
            liveModems += 1
            consumers[key] = Task.detached { [weak self] in
                for await e in stream { if case .rxText(let ch, false) = e { emit(onChar(ch)) } }
                self?.lock.withLock { _ = self?.consumers.removeValue(forKey: key) }
            }
        }
        return Decoder(m)
    }

    private func retire(_ d: Decoder) {
        d.modem.finishEvents()
        lock.withLock { liveModems -= 1 }
    }

    private func removeSecond() {
        if let s = second { retire(s.dec); second = nil }
    }

    /// Nastaví parametry, které se od minula změnily (mark jen když `withMark`).
    private func sync(_ d: Decoder, _ t: AuxTuning, withMark: Bool) {
        let a = d.applied
        let m = d.modem
        if a?.baud != t.baud { try? m.set(parameter: "baud", value: .double(t.baud)) }
        if a?.shift != t.shift { try? m.set(parameter: "shift", value: .double(t.shift)) }
        if a?.reverse != t.reverse { try? m.set(parameter: "reverse", value: .bool(t.reverse)) }
        if withMark, a?.mark != t.mark { try? m.set(parameter: "mark", value: .double(t.mark)) }
        d.applied = t
    }

    private func process(_ block: [Float], tuning t: AuxTuning, spectrum: SpectrumFrame?) {
        samples += block.count
        if config.secondEnabled {
            let demod = config.resolvedSecondDemod(main: t.demodType)
            if second?.demod != demod { removeSecond() }
            if second == nil, let d = makeDecoder({ .secondText($0) }) {
                try? d.modem.set(parameter: "afc", value: .bool(false))     // sleduje ladění hlavního
                try? d.modem.set(parameter: "demodType", value: .string(demod))
                second = (d, demod)
            }
            if let d = second?.dec {
                sync(d, t, withMark: true)
                block.withUnsafeBufferPointer { d.modem.processRx($0) }
            }
        }
        guard config.channelsEnabled else { return }
        if let spectrum {
            detector.update(spectrum)
            updateChannels(t)
        }
        for i in channels.indices {
            let d = channels[i].dec
            var tt = t; tt.mark = channels[i].mark
            sync(d, tt, withMark: false)
            block.withUnsafeBufferPointer { d.modem.processRx($0) }
            if case .double(let mk)? = d.modem.get(parameter: "mark") { channels[i].mark = mk }
            d.applied?.mark = channels[i].mark
        }
    }

    private func updateChannels(_ t: AuxTuning) {
        let now = Double(samples) / sampleRate
        let near = t.shift * 0.4
        let marks = detector.detect(shift: t.shift, fromHz: config.fromHz, toHz: config.toHz,
                                    maxCount: AuxDecoderConfig.maxChannelLimit)
        for m in marks {
            if let k = channels.firstIndex(where: { abs($0.mark - m) < near }) {
                channels[k].lastSeen = now
            } else if channels.count < config.clampedChannels, m >= 100, m + t.shift <= 3000,
                      !channels.contains(where: { abs($0.mark - m) < t.shift }),   // překryv s existujícím kanálem
                      let d = makeDecoder({ [id = nextId] in .channelText(id: id, $0) }) {
                try? d.modem.set(parameter: "afc", value: .bool(true))
                try? d.modem.set(parameter: "mark", value: .double((m * 10).rounded() / 10))
                channels.append(Channel(id: nextId, dec: d, mark: (m * 10).rounded() / 10, lastSeen: now))
                nextId += 1
            }
        }
        // zánik: bez signálu déle než timeout; dva kanály, které AFC stáhlo na stejný signál → starší zůstává
        var keep: [Channel] = []
        for ch in channels {
            if now - ch.lastSeen > config.clampedTimeout || keep.contains(where: { abs($0.mark - ch.mark) < near }) {
                retire(ch.dec)
            } else { keep.append(ch) }
        }
        channels = keep
        report()
    }

    private func report() {
        let list = channels.map { DecoderChannelInfo(id: $0.id, mark: $0.mark.rounded()) }
        if list != reported { reported = list; emit(.channels(list)) }
    }
}
