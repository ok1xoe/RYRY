// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AudioToolbox
import AVFoundation
import Foundation

/// Backend nad dvěma AVAudioEngine (vstup a výstup mohou být různá zařízení).
/// Render callback výstupu jen čte z lock-free ring bufferu.
public final class CoreAudioBackend: AudioBackend, @unchecked Sendable {
    private var inEngine: AVAudioEngine?
    private var outEngine: AVAudioEngine?
    private var txConv: SampleRateConverter?
    private let rxRing = RingBuffer(capacity: 11025 * 4)
    private let txRing = RingBuffer(capacity: 48000 * 4)
    private var deviceOutRate = 48000.0
    private var modemRate = 11025.0
    private let lock = NSLock()
    public private(set) var isRunning = false

    public init() {}

    private static func setDevice(_ node: AVAudioIONode, uid: String?) throws {
        guard let uid else { return }
        guard let dev = AudioDevices.find(uid: uid), let unit = node.audioUnit else {
            throw AudioError.device("zařízení \(uid) nenalezeno")
        }
        var id = AudioDeviceID(dev.id)
        let st = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                      &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        if st != noErr { throw AudioError.device("nelze vybrat \(dev.name) (\(st))") }
    }

    public func start(modemRate: Double, config: AudioConfig) throws {
        stop()
        self.modemRate = modemRate

        // Vstup. Po přepnutí zařízení hlásí inputNode zastaralý formát, proto tap bez formátu
        // (dostane nativní formát zařízení) a převodník se vytvoří podle prvního bufferu.
        let ie = AVAudioEngine()
        try Self.setDevice(ie.inputNode, uid: config.inputUID)
        let hwFmt = ie.inputNode.inputFormat(forBus: 0)
        guard hwFmt.sampleRate > 0 else { throw AudioError.device("vstup nemá formát (oprávnění k mikrofonu?)") }
        let ch = config.inputChannel
        let ring = rxRing
        let mr = modemRate
        nonisolated(unsafe) var conv: SampleRateConverter?
        nonisolated(unsafe) var convRate = 0.0
        ie.inputNode.installTap(onBus: 0, bufferSize: 1024, format: hwFmt) { buf, _ in
            guard let d = buf.floatChannelData else { return }
            let rate = buf.format.sampleRate
            if conv == nil || convRate != rate {
                conv = try? SampleRateConverter(from: rate, to: mr); convRate = rate
            }
            guard let c = conv else { return }
            let n = Int(buf.frameLength), chans = Int(buf.format.channelCount)
            var mono = [Float](repeating: 0, count: n)
            for i in 0..<n {
                switch ch {
                case .left: mono[i] = d[0][i]
                case .right: mono[i] = d[min(1, chans - 1)][i]
                case .mono: mono[i] = chans > 1 ? (d[0][i] + d[1][i]) * 0.5 : d[0][i]
                }
            }
            ring.write(c.process(mono))
        }

        // Výstup
        let oe = AVAudioEngine()
        try Self.setDevice(oe.outputNode, uid: config.outputUID)
        let outHW = oe.outputNode.outputFormat(forBus: 0)
        deviceOutRate = outHW.sampleRate > 0 ? outHW.sampleRate : 48000
        txConv = try SampleRateConverter(from: modemRate, to: deviceOutRate)
        let tx = txRing
        let gain = config.outputGain
        let outCh = config.outputChannel
        guard let srcFmt = AVAudioFormat(standardFormatWithSampleRate: deviceOutRate, channels: 2) else {
            throw AudioError.engine("formát výstupu")
        }
        let source = AVAudioSourceNode(format: srcFmt) { _, _, frames, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            let n = Int(frames)
            guard let l = list[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let got = tx.read(l, count: n)
            for i in got..<n { l[i] = 0 }
            for i in 0..<n { l[i] *= gain }
            if list.count > 1, let r = list[1].mData?.assumingMemoryBound(to: Float.self) {
                for i in 0..<n { r[i] = outCh == .left ? 0 : l[i] }
                if outCh == .right { for i in 0..<n { l[i] = 0 } }
            }
            return noErr
        }
        oe.attach(source)
        oe.connect(source, to: oe.mainMixerNode, format: srcFmt)

        do {
            try ie.start()
            try oe.start()
        } catch {
            ie.stop(); oe.stop()
            throw AudioError.engine("\(error)")
        }
        inEngine = ie; outEngine = oe
        isRunning = true
    }

    public func stop() {
        inEngine?.inputNode.removeTap(onBus: 0)
        inEngine?.stop(); outEngine?.stop()
        inEngine = nil; outEngine = nil
        rxRing.clear(); txRing.clear()
        isRunning = false
    }

    public func readRx(into a: inout [Float]) -> Int { rxRing.read(into: &a, count: a.count) }

    public func writeTx(_ samples: [Float]) -> Int {
        guard let c = txConv else { return 0 }
        let dev = c.process(samples)
        txRing.write(dev)
        return samples.count
    }

    public func clearTx() { txRing.clear() }

    public var txQueued: Int { Int(Double(txRing.available) * modemRate / deviceOutRate) }
}
