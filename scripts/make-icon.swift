// Vygeneruje Resources/AppIcon.icns: tmavý zaoblený čtverec, vodopád se dvěma stopami (mark/space)
// a čárové spektrum. Spuštění: swift scripts/make-icon.swift
import AppKit
import CoreGraphics

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let inset = s * 0.09, r = s * 0.2
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    // stín
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(path); ctx.setFillColor(CGColor(red: 0.04, green: 0.06, blue: 0.14, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    // pozadí: tmavě modrý gradient
    let bg = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.02, green: 0.05, blue: 0.20, alpha: 1),
                                                   CGColor(red: 0.00, green: 0.18, blue: 0.40, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    // vodopád (spodní 58 %): šum + dvě jasné stopy mark/space s „bity“
    var seed: UInt64 = 7
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
    let wfTop = rect.minY + rect.height * 0.58
    let rows = 26, cols = 40
    let cw = rect.width / CGFloat(cols), rh = (wfTop - rect.minY) / CGFloat(rows)
    let markC = Int(Double(cols) * 0.40), spaceC = Int(Double(cols) * 0.60)
    for row in 0..<rows {
        let bit = (row / 3 + row % 2) % 2 == 0
        for col in 0..<cols {
            var v = rnd() * 0.25
            let d1 = abs(col - markC), d2 = abs(col - spaceC)
            if bit, d1 <= 1 { v = 1 - CGFloat(d1) * 0.35 }
            if !bit, d2 <= 1 { v = 1 - CGFloat(d2) * 0.35 }
            let c: CGColor = v > 0.8 ? CGColor(red: 1, green: 0.92, blue: 0.3, alpha: 1)
                : v > 0.5 ? CGColor(red: 0.1, green: 0.85, blue: 0.95, alpha: 1)
                : CGColor(red: 0.0, green: 0.15 + v, blue: 0.45 + v, alpha: 1)
            ctx.setFillColor(c)
            ctx.fill(CGRect(x: rect.minX + CGFloat(col) * cw, y: rect.minY + CGFloat(row) * rh, width: cw + 0.5, height: rh + 0.5))
        }
    }
    // čárové spektrum nahoře
    let base = wfTop + rect.height * 0.04, amp = rect.height * 0.30
    let line = CGMutablePath()
    for i in 0...120 {
        let x = rect.minX + rect.width * CGFloat(i) / 120
        let f = CGFloat(i) / 120
        var y = 0.08 + 0.05 * rnd()
        y += 0.9 * exp(-pow((f - 0.40) * 38, 2)) + 0.8 * exp(-pow((f - 0.60) * 38, 2))
        let p = CGPoint(x: x, y: base + y * amp)
        if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
    }
    let fill = line.mutableCopy()!
    fill.addLine(to: CGPoint(x: rect.maxX, y: wfTop)); fill.addLine(to: CGPoint(x: rect.minX, y: wfTop)); fill.closeSubpath()
    ctx.addPath(fill); ctx.setFillColor(CGColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 0.25)); ctx.fillPath()
    ctx.addPath(line); ctx.setStrokeColor(CGColor(red: 0.3, green: 1, blue: 0.5, alpha: 1))
    ctx.setLineWidth(max(1, s * 0.012)); ctx.setLineJoin(.round); ctx.strokePath()
    // kurzory mark/space
    for (f, c) in [(0.40, CGColor(red: 1, green: 0.85, blue: 0.1, alpha: 0.9)), (0.60, CGColor(red: 1, green: 0.55, blue: 0.1, alpha: 0.9))] {
        let x = rect.minX + rect.width * CGFloat(f)
        ctx.setStrokeColor(c); ctx.setLineWidth(max(1, s * 0.008)); ctx.setLineDash(phase: 0, lengths: [s * 0.02, s * 0.015])
        ctx.move(to: CGPoint(x: x, y: rect.minY)); ctx.addLine(to: CGPoint(x: x, y: rect.maxY)); ctx.strokePath()
    }
    ctx.restoreGState()
    let img = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: dir)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try draw(px).write(to: dir.appendingPathComponent("icon_\(name).png"))
}
print("iconset: \(dir.path)")
