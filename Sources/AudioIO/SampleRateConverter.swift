// Copyright 2026 OK1XOE (RYRY), LGPL v3
@preconcurrency import AVFoundation

public enum AudioError: Error, Equatable, Sendable {
    case converter(String), device(String), engine(String)
}

/// Stateful sample rate converter (mono float32) on top of AVAudioConverter.
public final class SampleRateConverter {
    private let conv: AVAudioConverter
    private let inFmt: AVAudioFormat
    private let outFmt: AVAudioFormat
    public let ratio: Double

    public init(from: Double, to: Double) throws {
        guard let i = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: from, channels: 1, interleaved: false),
              let o = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: to, channels: 1, interleaved: false),
              let c = AVAudioConverter(from: i, to: o) else {
            throw AudioError.converter("\(from) → \(to)")
        }
        c.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        inFmt = i; outFmt = o; conv = c; ratio = to / from
    }

    public func process(_ input: [Float]) -> [Float] {
        guard !input.isEmpty,
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(input.count)) else { return [] }
        inBuf.frameLength = AVAudioFrameCount(input.count)
        input.withUnsafeBufferPointer { src in
            inBuf.floatChannelData![0].update(from: src.baseAddress!, count: input.count)
        }
        let cap = AVAudioFrameCount(Double(input.count) * ratio + 64)
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap) else { return [] }
        // AVAudioConverter calls the input block synchronously inside convert() – sharing is safe.
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let src = inBuf
        var err: NSError?
        _ = conv.convert(to: outBuf, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return src
        }
        let n = Int(outBuf.frameLength)
        return Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: n))
    }
}
