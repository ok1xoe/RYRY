import Foundation
import Testing
import AudioIO
import Keying
import ModemKit
import RTTYModem
import RTTYSignalKit
import TestSupport
@testable import Engine

/// A registry of the modems created for the auxiliary decoders (weak references – a leak test).
final class ModemTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var refs: [WeakModem] = []
    struct WeakModem { weak var m: RTTYModem? }
    func make() -> (any Modem)? {
        guard let m = try? RTTYModem() else { return nil }
        lock.withLock { refs.append(WeakModem(m: m)) }
        return m
    }
    var created: Int { lock.withLock { refs.count } }
    var alive: Int { lock.withLock { refs.filter { $0.m != nil }.count } }
}

func makeAuxEngine(_ tracker: ModemTracker, backlog: Int? = nil) throws -> Rig_ {
    let audio = FakeAudioBackend()
    let port = FakeSerialPort()
    let clock = ManualClock()
    var cfg = EngineConfig()
    cfg.ptt = .none
    cfg.txDelay = .milliseconds(100)
    let e = Engine(modem: try RTTYModem(), audio: audio, config: cfg, serialFactory: { _ in port }, clock: clock,
                   autoRun: false, auxModemFactory: { tracker.make() }, auxMaxBacklog: backlog)
    return Rig_(engine: e, audio: audio, port: port, clock: clock, events: e.events())
}

/// Sums the signals (equal length = the longer of them) and adds noise.
func mix(_ signals: [[Float]], noise rms: Float = 0.05, seed: UInt64 = 3) -> [Float] {
    var out = [Float](repeating: 0, count: signals.map(\.count).max() ?? 0)
    for s in signals { for i in s.indices { out[i] += s[i] } }
    var g = NoiseGenerator(seed: seed); g.addNoise(to: &out, rms: rms)
    return out
}

struct AuxCollected {
    var main = "", second = "", channels: [Int: String] = [:], lists: [[DecoderChannelInfo]] = []
}

func collectAux(_ events: AsyncStream<EngineEvent>) async -> AuxCollected {
    var r = AuxCollected()
    for await e in events {
        switch e {
        case .modem(.rxText(let c, false)): r.main.append(c)
        case .aux(.secondText(let c)): r.second.append(c)
        case .aux(.channelText(let id, let c)): r.channels[id, default: ""].append(c)
        case .aux(.channels(let l)): r.lists.append(l)
        default: break
        }
    }
    return r
}

// MARK: Signal detection

/// The heavy auxiliary decoder tests run one after another (in parallel they would load the CPU and slow timing tests elsewhere).
@Suite(.serialized) struct AuxDecoderTests {
    @Test func detectorFindsRTTYPairsInSyntheticSpectrum() {
        let binHz = 11025.0 / 2048
        var m = (0..<744).map { Float(40 + ($0 * 7919) % 11) }        // a noise floor of ≈ 45 with a little "noise"
        func peak(_ hz: Double, _ h: Float) {
            let c = Int((hz / binHz).rounded())
            for d in -2...2 { m[c + d] = max(m[c + d], 45 + h - Float(abs(d)) * 12) }
        }
        peak(1000, 60); peak(1170, 55)          // signal 1 (shift 170)
        peak(1600, 70); peak(1775, 66)          // signal 2 (shift 175 – within the ±15 % tolerance)
        peak(2500, 80)                          // a lone carrier tone – not RTTY
        peak(400, 60); peak(700, 60)            // a pair with the wrong spacing (300 Hz)
        let r = RTTYSignalDetector.detect(magnitudes: m, binHz: binHz, shift: 170)
        #expect(r.count == 2)
        #expect(r.contains { abs($0 - 1000) < 8 })
        #expect(r.contains { abs($0 - 1602) < 8 })
        #expect(abs(r[0] - 1602) < 8)           // the first one stronger
        // weak peaks below the threshold find nothing
        let flat = (0..<744).map { Float(40 + ($0 * 7919) % 11) }
        #expect(RTTYSignalDetector.detect(magnitudes: flat, binHz: binHz, shift: 170).isEmpty)
        #expect(RTTYSignalDetector.detect(magnitudes: m, binHz: binHz, shift: 170, maxCount: 1).count == 1)
    }

    /// The spectrum from the MMTTY core (held peaks) for two real signals in noise.
    @Test func detectorFindsSignalsInCoreSpectrum() throws {
        let text = "RYRYRYRY CQ TEST DE OK1XOE OK1XOE K RYRYRYRY"
        let a = RTTYSignalGenerator(markHz: 1000, amplitude: 0.3).generate(text: text)
        let b = RTTYSignalGenerator(markHz: 1600, amplitude: 0.3).generate(text: text)
        let modem = try RTTYModem()
        var det = RTTYSignalDetector()
        var found: [Double] = []
        var noiseOnly = true
        for (input, expectSignals) in [(mix([a, b]), true), (mix([[Float](repeating: 0, count: 60_000)], noise: 0.1, seed: 5), false)] {
            det.reset()
            var i = 0
            input.withUnsafeBufferPointer { p in
                while i + 1103 <= p.count {
                    modem.processRx(UnsafeBufferPointer(rebasing: p[i..<(i + 1103)])); i += 1103
                    if let f = modem.spectrum() { det.update(f) }
                }
            }
            let r = det.detect(shift: 170)
            if expectSignals { found = r } else { noiseOnly = r.isEmpty }
        }
        #expect(found.count == 2, "nalezeno \(found)")
        #expect(found.contains { abs($0 - 1000) < 15 })
        #expect(found.contains { abs($0 - 1600) < 15 })
        #expect(noiseOnly)
    }

    // MARK: The second decoder

    @Test func secondDecoderDecodesSameTextAsMain() async throws {
        let tracker = ModemTracker()
        let r = try makeAuxEngine(tracker)
        var c = AuxDecoderConfig(); c.secondEnabled = true
        await r.engine.setAuxDecoders(c)
        try await r.engine.start()
        let text = "CQ CQ DE OK1XOE OK1XOE PSE K"
        r.audio.feedRx(mix([RTTYSignalGenerator().generate(text: text)], noise: 0.05))
        await pump(r) { r.audio.rxRemaining == 0 }
        await r.engine.flushAuxDecoders()
        await r.engine.stop()
        let got = await collectAux(r.events)
        #expect(got.main.contains(text))
        #expect(got.second.contains(text))
        #expect(tracker.created == 1)
        #expect(tracker.alive == 0)
    }

    @Test func secondDecoderUsesOtherDemodAndFollowsMainTuning() async throws {
        let tracker = ModemTracker()
        let r = try makeAuxEngine(tracker)
        try await r.engine.start()
        try await r.engine.setModemParam("mark", .double(1500))
        var c = AuxDecoderConfig(); c.secondEnabled = true
        await r.engine.setAuxDecoders(c)
        let text = "RYRY DE OK1XOE TEST"
        r.audio.feedRx(RTTYSignalGenerator(markHz: 1500).generate(text: text))
        await pump(r) { r.audio.rxRemaining == 0 }
        #expect(c.resolvedSecondDemod(main: "iir") == "fft")
        #expect(c.resolvedSecondDemod(main: "fft") == "iir")
        var pll = c; pll.secondDemod = "pll"
        #expect(pll.resolvedSecondDemod(main: "iir") == "pll")
        await r.engine.flushAuxDecoders()
        await r.engine.stop()
        #expect(await collectAux(r.events).second.contains(text))
    }

    @Test func auxDecodersPauseDuringTx() async throws {
        let tracker = ModemTracker()
        let r = try makeAuxEngine(tracker)
        var c = AuxDecoderConfig(); c.secondEnabled = true
        await r.engine.setAuxDecoders(c)
        try await r.engine.start()
        r.audio.feedRx([Float](repeating: 0, count: 2206))
        await pump(r, steps: 3) { false }                    // the hub is created with the first RX block
        try await r.engine.tx()
        r.audio.feedRx(RTTYSignalGenerator().generate(text: "CQ CQ DE OK1XOE K"))
        await pump(r, steps: 40) { false }
        await r.engine.auxFlush()
        await r.engine.flushAuxDecoders()
        await r.engine.stop()
        #expect(await collectAux(r.events).second.isEmpty)
    }

    // MARK: Multi-channel decoding

    @Test func multiChannelDecodesTwoSimultaneousSignals() async throws {
        let tracker = ModemTracker()
        let r = try makeAuxEngine(tracker)
        var c = AuxDecoderConfig(); c.channelsEnabled = true; c.maxChannels = 4
        await r.engine.setAuxDecoders(c)
        try await r.engine.start()
        let t1 = "CQ CQ DE OK1ABC OK1ABC PSE K", t2 = "TEST DE DL2XYZ DL2XYZ TEST"
        // a long preamble (mark) so that the channels are created before the text starts; the texts repeated
        let s1 = RTTYSignalGenerator(markHz: 1000, amplitude: 0.3).generate(text: "RYRYRY " + t1 + " " + t1 + " " + t1, leadIn: 2)
        let s2 = RTTYSignalGenerator(markHz: 1650, amplitude: 0.3).generate(text: "RYRYRY " + t2 + " " + t2 + " " + t2, leadIn: 2)
        r.audio.feedRx(mix([s1, s2]))
        await pump(r) { r.audio.rxRemaining == 0 }
        await r.engine.flushAuxDecoders()
        await r.engine.stop()
        let got = await collectAux(r.events)
        let marks = got.lists.last(where: { !$0.isEmpty }) ?? []
        #expect(marks.count == 2, "kanály \(got.lists.last ?? [])")
        #expect(marks.contains { abs($0.mark - 1000) < 15 })
        #expect(marks.contains { abs($0.mark - 1650) < 15 })
        let texts = Array(got.channels.values)
        #expect(texts.contains { $0.contains(t1) }, "\(got.channels)")
        #expect(texts.contains { $0.contains(t2) }, "\(got.channels)")
        #expect(tracker.alive == 0)
    }

    @Test func channelExpiresAfterTimeoutWithoutSignal() async throws {
        let tracker = ModemTracker()
        let r = try makeAuxEngine(tracker)
        var c = AuxDecoderConfig(); c.channelsEnabled = true; c.channelTimeout = 3
        await r.engine.setAuxDecoders(c)
        try await r.engine.start()
        let sig = RTTYSignalGenerator(markHz: 1200, amplitude: 0.3).generate(text: "RYRYRYRY CQ DE OK1XOE K")
        r.audio.feedRx(mix([sig]))
        await pump(r) { r.audio.rxRemaining == 0 }
        await r.engine.auxFlush()
        #expect(await r.engine.auxModemCount == 1)
        // 10 s of noise only → the channel disappears (a 3 s timeout + the decay of the held peaks)
        r.audio.feedRx(mix([[Float](repeating: 0, count: 110_250)], seed: 11))
        await pump(r) { r.audio.rxRemaining == 0 }
        await r.engine.auxFlush()
        #expect(await r.engine.auxModemCount == 0)
        await r.engine.flushAuxDecoders()
        await r.engine.stop()
        let got = await collectAux(r.events)
        #expect(got.lists.contains { $0.count == 1 })
        #expect(got.lists.last == [])
        #expect(tracker.created == 1, "\(got.lists)")
        #expect(tracker.alive == 0)
    }

    @Test func maxChannelsLimitsDecoders() async throws {
        let tracker = ModemTracker()
        let r = try makeAuxEngine(tracker)
        var c = AuxDecoderConfig(); c.channelsEnabled = true; c.maxChannels = 1
        await r.engine.setAuxDecoders(c)
        try await r.engine.start()
        let s1 = RTTYSignalGenerator(markHz: 900, amplitude: 0.3).generate(text: "RYRYRYRY CQ K")
        let s2 = RTTYSignalGenerator(markHz: 1700, amplitude: 0.3).generate(text: "RYRYRYRY CQ K")
        r.audio.feedRx(mix([s1, s2]))
        await pump(r) { r.audio.rxRemaining == 0 }
        await r.engine.auxFlush()
        #expect(await r.engine.auxModemCount == 1)
        // turning it off at run time closes the channels
        await r.engine.setAuxDecoders(AuxDecoderConfig())
        await r.engine.auxFlush()
        #expect(await r.engine.auxModemCount == 0)
        await r.engine.flushAuxDecoders()
        await r.engine.stop()
        let got = await collectAux(r.events)
        #expect(got.lists.allSatisfy { $0.count <= 1 })
        #expect(got.lists.last == [])
    }

    // MARK: Stopping and performance

    @Test func stopReleasesAllAuxModemsAndTasks() async throws {
        let tracker = ModemTracker()
        let r = try makeAuxEngine(tracker)
        var c = AuxDecoderConfig(); c.secondEnabled = true; c.channelsEnabled = true
        await r.engine.setAuxDecoders(c)
        try await r.engine.start()
        r.audio.feedRx(mix([RTTYSignalGenerator(markHz: 1000, amplitude: 0.3).generate(text: "RYRYRYRY CQ K"),
                            RTTYSignalGenerator(markHz: 1500, amplitude: 0.3).generate(text: "RYRYRYRY CQ K")]))
        await pump(r) { r.audio.rxRemaining == 0 }
        await r.engine.auxFlush()
        #expect(tracker.alive >= 2)
        await r.engine.flushAuxDecoders()
        await r.engine.stop()
        _ = await collectAux(r.events)                    // the event stream has ended (both the hub and the subscribers finished)
        #expect(await r.engine.auxModemCount == 0)
        #expect(tracker.alive == 0)
        // nothing new is created after stopping
        await r.engine.setAuxDecoders(c)
        #expect(tracker.alive == 0)
    }

    @Test func overloadedHubDropsBlocksInsteadOfBlocking() async throws {
        let hub = AuxDecoderHub(sampleRate: 11025, maxBacklog: 2000, factory: { try? RTTYModem() }, emit: { _ in })
        var c = AuxDecoderConfig(); c.secondEnabled = true
        hub.configure(c)
        for _ in 0..<20 { hub.feed([Float](repeating: 0, count: 1000), tuning: AuxTuning(), spectrum: nil) }
        #expect(hub.dropped > 0)
        await hub.stop()
        #expect(hub.modemCount == 0 && hub.consumerCount == 0)
    }

    /// A load estimate: how many times faster than real time one modem processes the input (for every demodulator type).
    /// Performance measurement on request only: MMTTY_PERF=1 swift test --filter auxModemCPUEstimate
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MMTTY_PERF"] != nil)) func auxModemCPUEstimate() throws {
        let input = mix([RTTYSignalGenerator(markHz: 1000).generate(text: String(repeating: "RYRY CQ TEST ", count: 8))], seed: 2)
        let seconds = Double(input.count) / 11025
        var report: [String] = []
        for d in AuxDecoderConfig.demodTypes {
            let m = try RTTYModem()
            try m.set(parameter: "demodType", value: .string(d))
            let t0 = DispatchTime.now().uptimeNanoseconds
            input.withUnsafeBufferPointer { p in
                var i = 0
                while i < p.count { let n = min(1103, p.count - i); m.processRx(UnsafeBufferPointer(rebasing: p[i..<(i + n)])); i += n }
            }
            let dt = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
            report.append("\(d): \(String(format: "%.1f", seconds / dt))× reálný čas")
            #expect(dt < seconds, "\(d) nestíhá reálný čas")
        }
        print("CPU doplňkových modemů (\(String(format: "%.0f", seconds)) s audia): " + report.joined(separator: ", "))
    }
}
