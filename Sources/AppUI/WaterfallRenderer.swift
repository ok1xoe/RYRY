// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import CoreGraphics
import Foundation
import ModemKit

public struct Pixel: Equatable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8
    public var brightness: Int { Int(r) + Int(g) + Int(b) }
}

/// Posuvný obrázek vodopádu (nejnovější řádek nahoře). Čistá logika, kreslí se hotový CGImage.
public struct WaterfallRenderer: Sendable {
    public let width: Int, height: Int
    private var pixels: [UInt32]           // bajty v paměti R,G,B,A (UInt32 little-endian 0xAABBGGRR)
    private var peak: Float = 1
    public private(set) var lastRow: [Float] = []   // spektrum posledního řádku (0…1)
    /// Vyhlazené čárové spektrum (0…1): rychlý náběh, pomalejší doznívání – jako FFT okno MMTTY.
    public private(set) var spectrumLine: [Float] = []

    public init(width: Int, height: Int) {
        self.width = max(1, width); self.height = max(1, height)
        pixels = [UInt32](repeating: 0xFF00_0000, count: self.width * self.height)
    }

    static func color(_ v: Float) -> UInt32 {
        // černá → modrá → azurová → žlutá → bílá
        let t = max(0, min(1, v))
        let stops: [(Float, (Float, Float, Float))] = [(0, (0, 0, 0)), (0.3, (0, 0, 0.8)), (0.55, (0, 0.8, 0.9)),
                                                       (0.8, (1, 0.9, 0)), (1, (1, 1, 1))]
        var i = 0
        while i < stops.count - 2 && t > stops[i + 1].0 { i += 1 }
        let (t0, c0) = stops[i], (t1, c1) = stops[i + 1]
        let k = (t - t0) / max(0.0001, t1 - t0)
        let r = UInt32((c0.0 + (c1.0 - c0.0) * k) * 255), g = UInt32((c0.1 + (c1.1 - c0.1) * k) * 255)
        let b = UInt32((c0.2 + (c1.2 - c0.2) * k) * 255)
        return 0xFF00_0000 | (b << 16) | (g << 8) | r
    }

    public mutating func push(_ f: SpectrumFrame, fromHz: Double, toHz: Double) {
        guard f.binHz > 0, toHz > fromHz, !f.magnitudes.isEmpty else { return }
        // posun o řádek dolů
        pixels.withUnsafeMutableBufferPointer { p in
            let base = p.baseAddress!
            (base + width).update(from: base, count: width * (height - 1))
        }
        var row = [Float](repeating: 0, count: width)
        let hzPerPx = (toHz - fromHz) / Double(width)
        for x in 0..<width {
            let lo = Int((fromHz + Double(x) * hzPerPx) / f.binHz)
            let hi = max(lo + 1, Int((fromHz + Double(x + 1) * hzPerPx) / f.binHz))
            var m: Float = 0
            if lo < f.magnitudes.count {
                for i in lo..<min(hi, f.magnitudes.count) { m = max(m, f.magnitudes[i]) }
            }
            row[x] = m
        }
        let frameMax = row.max() ?? 0
        peak = max(frameMax, peak * 0.995, 1)      // pomalu klesající automatické zesílení
        for x in 0..<width { pixels[x] = Self.color(row[x] / peak) }
        lastRow = row.map { $0 / peak }
        if spectrumLine.count != width { spectrumLine = lastRow }
        else {
            for x in 0..<width {
                let v = lastRow[x], o = spectrumLine[x]
                spectrumLine[x] = v > o ? v : o * 0.6 + v * 0.4
            }
        }
    }

    public func row(_ y: Int) -> [Pixel] {
        (0..<width).map { x in
            let v = pixels[x + y * width]
            return Pixel(r: UInt8(v & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8((v >> 16) & 0xFF))
        }
    }

    public var image: CGImage? {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
