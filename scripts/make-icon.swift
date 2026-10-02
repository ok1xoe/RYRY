// Vygeneruje ikonu RYRY (varianta A): tmavé pozadí, vodopád se dvěma střídavými stopami mark/space
// a čárové spektrum se dvěma špičkami v azurové barvě značky OK1XOE.dev (#34E2E8).
//
//   swift scripts/make-icon.swift [výstupní složka]   (výchozí build/icon)
//
// Výstupy:
//   AppIcon.iconset/    klasická ikona (zaoblený čtverec 824/1024) → iconutil → Resources/AppIcon.icns
//   icon-1024.png       totéž v 1024 px (web, App Store Connect)
//   AppIcon.icon/       formát macOS 26 (Icon Composer): jedna vrstva přes celou plochu, tvar a sklo dodá systém
import AppKit
import CoreGraphics

let cs = CGColorSpaceCreateDeviceRGB()
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
let cyan = rgb(0.204, 0.886, 0.910)                                  // #34E2E8

/// Obsah ikony do obdélníku `rect` (bez tvaru – ořez řeší volající). `s` = strana celé ikony.
func drawArt(_ ctx: CGContext, _ rect: CGRect, _ s: CGFloat) {
    let bg = CGGradient(colorsSpace: cs, colors: [rgb(0.02, 0.04, 0.10), rgb(0.03, 0.12, 0.26)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
    // vodopád (spodních 56 %): hrubé buňky, aby byl čitelný i v 32 px
    var seed: UInt64 = 11
    func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
    let wfTop = rect.minY + rect.height * 0.56
    let rows = 9, cols = 14, markC = 5, spaceC = 8
    let cw = rect.width / CGFloat(cols), rh = (wfTop - rect.minY) / CGFloat(rows)
    for row in 0..<rows {
        let markOn = row % 2 == 0                                         // bity: mark a space se střídají
        for col in 0..<cols {
            let c: CGColor
            if col == markC { c = markOn ? rgb(1.0, 0.86, 0.25) : rgb(0.10, 0.30, 0.45) }
            else if col == spaceC { c = markOn ? rgb(0.10, 0.30, 0.45) : rgb(1.0, 0.62, 0.20) }
            else { let v = rnd() * 0.22; c = rgb(0.02, 0.10 + v, 0.28 + v) }
            ctx.setFillColor(c)
            ctx.fill(CGRect(x: rect.minX + CGFloat(col) * cw, y: rect.minY + CGFloat(row) * rh, width: cw + 0.5, height: rh + 0.5))
        }
    }
    // spektrum: dvě špičky nad stopami
    let base = wfTop + rect.height * 0.05, amp = rect.height * 0.30
    let fm = (CGFloat(markC) + 0.5) / CGFloat(cols), fs = (CGFloat(spaceC) + 0.5) / CGFloat(cols)
    let line = CGMutablePath()
    for i in 0...160 {
        let f = CGFloat(i) / 160
        let y = 0.06 + 0.03 * rnd() + 0.92 * exp(-pow((f - fm) * 30, 2)) + 0.85 * exp(-pow((f - fs) * 30, 2))
        let p = CGPoint(x: rect.minX + rect.width * f, y: base + y * amp)
        if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
    }
    let fill = line.mutableCopy()!
    fill.addLine(to: CGPoint(x: rect.maxX, y: wfTop)); fill.addLine(to: CGPoint(x: rect.minX, y: wfTop)); fill.closeSubpath()
    ctx.addPath(fill); ctx.setFillColor(rgb(0.204, 0.886, 0.910, 0.20)); ctx.fillPath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.03, color: rgb(0.204, 0.886, 0.910, 0.8))  // záře jako na webu
    ctx.addPath(line); ctx.setStrokeColor(cyan); ctx.setLineWidth(max(1.2, s * 0.022))
    ctx.setLineJoin(.round); ctx.setLineCap(.round); ctx.strokePath()
    ctx.restoreGState()
}

/// `fullBleed` = celá plocha bez tvaru (vrstva pro .icon); jinak klasická ikona: zaoblený čtverec 824/1024.
func draw(_ px: Int, fullBleed: Bool) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if fullBleed {
        drawArt(ctx, CGRect(x: 0, y: 0, width: s, height: s), s)
    } else {
        let inset = s * 100 / 1024, r = s * 185 / 1024
        let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)); ctx.clip()
        drawArt(ctx, rect, s)
        ctx.restoreGState()
    }
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon")
let fm = FileManager.default
try? fm.removeItem(at: out)
let iconset = out.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try draw(px, fullBleed: false).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try draw(1024, fullBleed: false).write(to: out.appendingPathComponent("icon-1024.png"))
let icon = out.appendingPathComponent("AppIcon.icon")
try fm.createDirectory(at: icon.appendingPathComponent("Assets"), withIntermediateDirectories: true)
try draw(1024, fullBleed: true).write(to: icon.appendingPathComponent("Assets/art.png"))
try """
{
  "fill" : { "solid" : "srgb:0.02000,0.04000,0.10000,1.00000" },
  "groups" : [
    {
      "layers" : [ { "image-name" : "art.png", "name" : "art" } ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : false, "value" : 0.5 }
    }
  ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
""".write(to: icon.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("hotovo: \(out.path)")
