// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import CoreGraphics
import Foundation
import ModemKit
import Settings

public struct Pixel: Equatable, Sendable {
    public var r: UInt8, g: UInt8, b: UInt8
    public var brightness: Int { Int(r) + Int(g) + Int(b) }
}

/// Posuvný obrázek vodopádu (nejnovější řádek nahoře). Čistá logika, kreslí se hotový CGImage.
public struct WaterfallRenderer: Sendable {
    public let width: Int, height: Int
    private var pixels: [UInt32]           // bajty v paměti R,G,B,A (UInt32 little-endian 0xAABBGGRR)
    private var peak: Float = 1
    private var floor: Float?               // odhad šumového dna (20. percentil, vyhlazený)
    /// Minimální dynamika automatického zesílení (jednotky FFT jádra, ≈ 3,4/dB → ~18 dB):
    /// když špička po konci signálu klesne k šumu, šum se nesmí roztáhnout na plný jas.
    static let minRange: Float = 60
    public private(set) var lastRow: [Float] = []   // spektrum posledního řádku (0…1)
    /// Vyhlazené čárové spektrum (0…1): rychlý náběh, pomalejší doznívání – jako FFT okno MMTTY.
    public private(set) var spectrumLine: [Float] = []
    /// Zesílení zobrazení v dB (násobí normovanou úroveň).
    public var gainDB = 0.0
    /// true = automatické (pomalu klesající špička), false = pevná reference (FFT MMTTY 0…256).
    public var autoGain = true
    public static let fixedReference: Float = 256
    public var palette = WaterfallPalette.classic
    /// Doznívání čárového spektra (váha předchozí hodnoty) – odezva FFT.
    public var decay: Float = 0.6

    public init(width: Int, height: Int) {
        self.width = max(1, width); self.height = max(1, height)
        pixels = [UInt32](repeating: 0xFF00_0000, count: self.width * self.height)
    }

    static func stops(_ p: WaterfallPalette) -> [(Float, (Float, Float, Float))] {
        switch p {
        case .classic:  // černá → modrá → azurová → žlutá → bílá
            return [(0, (0, 0, 0)), (0.3, (0, 0, 0.8)), (0.55, (0, 0.8, 0.9)), (0.8, (1, 0.9, 0)), (1, (1, 1, 1))]
        case .gray: return [(0, (0, 0, 0)), (1, (1, 1, 1))]
        case .heat:     // černá → červená → oranžová → žlutá → bílá
            return [(0, (0, 0, 0)), (0.35, (0.7, 0, 0)), (0.6, (1, 0.5, 0)), (0.85, (1, 1, 0.2)), (1, (1, 1, 1))]
        case .green:    // „monitor“: černá → tmavě zelená → zelená → bílá
            return [(0, (0, 0, 0)), (0.4, (0, 0.45, 0.1)), (0.8, (0.2, 1, 0.3)), (1, (0.9, 1, 0.9))]
        case .blue:     // černá → tmavě modrá → modrá → světle modrá → bílá
            return [(0, (0, 0, 0)), (0.35, (0, 0.1, 0.5)), (0.7, (0.2, 0.5, 1)), (0.9, (0.7, 0.9, 1)), (1, (1, 1, 1))]
        }
    }

    static func color(_ v: Float, _ p: WaterfallPalette = .classic) -> UInt32 {
        let t = max(0, min(1, v))
        let stops = stops(p)
        var i = 0
        while i < stops.count - 2 && t > stops[i + 1].0 { i += 1 }
        let (t0, c0) = stops[i], (t1, c1) = stops[i + 1]
        let k = max(0, min(1, (t - t0) / max(0.0001, t1 - t0)))
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
        let sorted = row.sorted()
        let p20 = sorted[sorted.count / 5]
        floor = floor.map { $0 * 0.9 + p20 * 0.1 } ?? p20
        let fl = floor ?? 0
        peak = max(frameMax, fl + (peak - fl) * 0.995, 1)   // pomalu klesající automatické zesílení
        let g = Float(pow(10, gainDB / 20))
        if autoGain {
            let range = max(peak - fl, Self.minRange)
            lastRow = row.map { ($0 - fl) / range * g }
        } else {
            lastRow = row.map { $0 / Self.fixedReference * g }
        }
        for x in 0..<width { pixels[x] = Self.color(lastRow[x], palette) }
        if spectrumLine.count != width { spectrumLine = lastRow }
        else {
            for x in 0..<width {
                let v = lastRow[x], o = spectrumLine[x]
                spectrumLine[x] = v > o ? v : o * decay + v * (1 - decay)
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
