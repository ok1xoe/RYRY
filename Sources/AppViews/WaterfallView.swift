// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import ModemKit
import SwiftUI

/// Zářezy (notch) – červené čárkované čáry.
@MainActor func drawNotches(_ ctx: GraphicsContext, _ size: CGSize, _ model: AppModel) {
    for hz in model.notchMarkers {
        let xx = CGFloat((hz - model.waterfallFromHz) / (model.waterfallToHz - model.waterfallFromHz)) * size.width
        var p = Path()
        p.move(to: CGPoint(x: xx, y: 0)); p.addLine(to: CGPoint(x: xx, y: size.height))
        ctx.stroke(p, with: .color(.red.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
    }
}

struct WaterfallView: View {
    @Bindable var model: AppModel

    func notch(_ fraction: Double) {
        let hz = model.waterfallFromHz + fraction * (model.waterfallToHz - model.waterfallFromHz)
        Task { await model.notchClick(hz: hz) }
    }

    func x(_ hz: Double, _ w: CGFloat) -> CGFloat {
        CGFloat((hz - model.waterfallFromHz) / (model.waterfallToHz - model.waterfallFromHz)) * w
    }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    if let img = model.waterfall.image {
                        ctx.draw(Image(decorative: img, scale: 1), in: CGRect(origin: .zero, size: size))
                    } else {
                        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                    }
                    for (hz, color) in [(model.mark, Color.yellow), (model.space, Color.orange)] {
                        var p = Path()
                        let xx = x(hz, size.width)
                        p.move(to: CGPoint(x: xx, y: 0)); p.addLine(to: CGPoint(x: xx, y: size.height))
                        ctx.stroke(p, with: .color(color.opacity(0.85)), lineWidth: 1)
                    }
                    drawNotches(ctx, size, model)
                    // stupnice po 500 Hz
                    var hz = (model.waterfallFromHz / 500).rounded(.up) * 500
                    while hz < model.waterfallToHz {
                        let xx = x(hz, size.width)
                        ctx.draw(Text(verbatim: "\(Int(hz))").font(.caption2).foregroundStyle(.white.opacity(0.7)),
                                 at: CGPoint(x: xx, y: 8))
                        hz += 500
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { loc in
                    let hz = model.waterfallFromHz + Double(loc.x / g.size.width) * (model.waterfallToHz - model.waterfallFromHz)
                    Task { await model.tune(toMarkHz: hz) }
                }
                .help("Klik = naladit mark · pravé tlačítko = zářez (notch) · kolečko = úroveň squelche")
                .overlay(ScrollWheelCatcher(onScroll: { dy in Task { await model.adjustSquelch(steps: dy > 0 ? 1 : -1) } },
                                            onRightClick: { f in notch(f) }))
                if model.xyEnabled {
                    XYScopeView(points: model.xyPoints)
                        .frame(width: min(g.size.height, 160), height: min(g.size.height, 160))
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                Text(String(format: "M %.0f  S %.0f  SQ %.0f", model.mark, model.space,
                            { if case .double(let v)? = model.param("squelchLevel") { return v }; return 0 }()))
                    .font(.caption.monospaced()).padding(4)
                    .background(.black.opacity(0.5)).foregroundStyle(.white)
                    .padding(4).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

/// Zachytí kolečko myši (SwiftUI na macOS 14 nemá onScrollWheel); kliky propouští.
struct ScrollWheelCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    /// Pravé tlačítko: poměr x (0…1) v šířce pohledu.
    var onRightClick: ((Double) -> Void)? = nil
    final class V: NSView {
        var onScroll: ((CGFloat) -> Void)?
        var onRightClick: ((Double) -> Void)?
        override func rightMouseDown(with e: NSEvent) {
            let p = convert(e.locationInWindow, from: nil)
            if bounds.width > 0 { onRightClick?(Double(p.x / bounds.width)) }
        }
        private var acc: CGFloat = 0
        override func scrollWheel(with e: NSEvent) {
            if !e.momentumPhase.isEmpty { return }                 // setrvačnost trackpadu ignorovat
            if e.hasPreciseScrollingDeltas {                        // trackpad: krok po 12 bodech
                acc += e.scrollingDeltaY
                while abs(acc) >= 12 { onScroll?(acc > 0 ? 1 : -1); acc -= acc > 0 ? 12 : -12 }
            } else if abs(e.scrollingDeltaY) > 0.1 {               // kolečko myši: krok za událost
                onScroll?(e.scrollingDeltaY)
            }
        }
        override func hitTest(_ p: NSPoint) -> NSView? {
            // kliky nechat projít do SwiftUI, kolečko zachytit
            if let e = NSApp.currentEvent, e.type == .scrollWheel || (e.type == .rightMouseDown && onRightClick != nil) { return self }
            return nil
        }
    }
    func makeNSView(context: Context) -> V { let v = V(); v.onScroll = onScroll; v.onRightClick = onRightClick; return v }
    func updateNSView(_ v: V, context: Context) { v.onScroll = onScroll; v.onRightClick = onRightClick }
}

/// XY scope: mark na ose X, space na ose Y (správně naladěný signál = kříž).
struct XYScopeView: View {
    let points: [XYPoint]
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.85)))
            let m = max(0.0001, points.map { max(abs($0.x), abs($0.y)) }.max() ?? 1)
            var p = Path()
            for pt in points {
                let x = size.width / 2 + CGFloat(pt.x / m) * size.width * 0.45
                let y = size.height / 2 - CGFloat(pt.y / m) * size.height * 0.45
                p.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
            }
            ctx.fill(p, with: .color(.green))
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.6)))
    }
}

/// Čárové spektrum (FFT) nad vodopádem s kurzory mark/space; klik = naladit, kolečko = squelch.
struct SpectrumView: View {
    @Bindable var model: AppModel

    func x(_ hz: Double, _ w: CGFloat) -> CGFloat {
        CGFloat((hz - model.waterfallFromHz) / (model.waterfallToHz - model.waterfallFromHz)) * w
    }

    var body: some View {
        GeometryReader { g in
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.08)))
                // mřížka po 500 Hz
                var hz = (model.waterfallFromHz / 500).rounded(.up) * 500
                while hz < model.waterfallToHz {
                    var p = Path(); let xx = x(hz, size.width)
                    p.move(to: CGPoint(x: xx, y: 0)); p.addLine(to: CGPoint(x: xx, y: size.height))
                    ctx.stroke(p, with: .color(.white.opacity(0.12)), lineWidth: 1)
                    hz += 500
                }
                let line = model.waterfall.spectrumLine
                if line.count > 1 {
                    var p = Path()
                    let dx = size.width / CGFloat(line.count - 1)
                    for (i, v) in line.enumerated() {
                        let pt = CGPoint(x: CGFloat(i) * dx, y: size.height - 2 - CGFloat(max(0, min(1, v))) * (size.height - 6))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    var fill = p
                    fill.addLine(to: CGPoint(x: size.width, y: size.height)); fill.addLine(to: CGPoint(x: 0, y: size.height)); fill.closeSubpath()
                    ctx.fill(fill, with: .linearGradient(Gradient(colors: [.green.opacity(0.45), .green.opacity(0.05)]),
                                                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    ctx.stroke(p, with: .color(.green), lineWidth: 1.2)
                }
                for (hz, color) in [(model.mark, Color.yellow), (model.space, Color.orange)] {
                    var p = Path(); let xx = x(hz, size.width)
                    p.move(to: CGPoint(x: xx, y: 0)); p.addLine(to: CGPoint(x: xx, y: size.height))
                    ctx.stroke(p, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                drawNotches(ctx, size, model)
            }
            .contentShape(Rectangle())
            .onTapGesture { loc in
                let hz = model.waterfallFromHz + Double(loc.x / g.size.width) * (model.waterfallToHz - model.waterfallFromHz)
                Task { await model.tune(toMarkHz: hz) }
            }
            .overlay(ScrollWheelCatcher(onScroll: { dy in Task { await model.adjustSquelch(steps: dy > 0 ? 1 : -1) } },
                                        onRightClick: { f in
                let hz = model.waterfallFromHz + f * (model.waterfallToHz - model.waterfallFromHz)
                Task { await model.notchClick(hz: hz) }
            }))
            .help("Spektrum · klik = naladit mark · pravé tlačítko = zářez (notch) · kolečko = squelch")
            .overlay(alignment: .topLeading) { SpectrumMenu(model: model).padding(4) }
        }
    }
}

/// Rychlá volba rozsahu a zesílení spektra/vodopádu (jako tlačítka šířky FFT v MMTTY).
struct SpectrumMenu: View {
    @Bindable var model: AppModel
    var body: some View {
        Menu {
            Section("Rozsah") {
                ForEach(DisplayTab.ranges, id: \.0) { r in
                    Button((model.waterfallFromHz == r.1 && model.waterfallToHz == r.2 ? "✓ " : "") + r.0) {
                        Task { await model.setDisplay { $0.fromHz = r.1; $0.toHz = r.2 } }
                    }
                }
            }
            Section("Zesílení (\(Int(model.settings.display.gainDB)) dB)") {
                Button("+3 dB") { Task { await model.setDisplay { $0.gainDB += 3 } } }
                Button("−3 dB") { Task { await model.setDisplay { $0.gainDB -= 3 } } }
                Button("0 dB") { Task { await model.setDisplay { $0.gainDB = 0 } } }
                Button((model.settings.display.autoGain ? "✓ " : "") + "Automatické zesílení") {
                    Task { await model.setDisplay { $0.autoGain.toggle() } }
                }
            }
        } label: {
            Text(verbatim: "\(Int(model.waterfallFromHz))–\(Int(model.waterfallToHz)) Hz · "
                 + (model.settings.display.autoGain ? "AGC" : "\(Int(model.settings.display.gainDB)) dB") + " ▾")
                .font(.caption2.monospaced()).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Rozsah a zesílení spektra a vodopádu")
    }
}
