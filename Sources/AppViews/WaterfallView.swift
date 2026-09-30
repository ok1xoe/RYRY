// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import ModemKit
import SwiftUI
import Localization

/// Notches - red dashed lines.
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
                    drawChannelMarks(ctx, size, model)
                    // scale every 500 Hz
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
                .hint(L("Klik = naladit mark · pravé tlačítko = zářez (notch) · kolečko = úroveň squelche"))
                .overlay(ScrollWheelCatcher(onScroll: { dy in Task { await model.adjustSquelch(steps: dy > 0 ? 1 : -1) } },
                                            onRightClick: { f in notch(f) }))
                BandMapOverlay(model: model, topInset: 16)
                if model.xyEnabled {
                    let side = min(g.size.height, model.settings.display.xySize.points)
                    XYScopeView(points: model.settings.display.xyQuality == .low ? Self.decimate(model.xyPoints) : model.xyPoints,
                                dot: model.settings.display.xyQuality == .low ? 1.2 : 1.6)
                        .frame(width: side, height: side)
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

/// Captures the mouse wheel (SwiftUI on macOS 14 has no onScrollWheel); clicks are passed through.
struct ScrollWheelCatcher: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    /// Right button: the x ratio (0…1) across the view's width.
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
            if !e.momentumPhase.isEmpty { return }                 // ignore trackpad momentum
            if e.hasPreciseScrollingDeltas {                        // trackpad: one step per 12 points
                acc += e.scrollingDeltaY
                while abs(acc) >= 12 { onScroll?(acc > 0 ? 1 : -1); acc -= acc > 0 ? 12 : -12 }
            } else if abs(e.scrollingDeltaY) > 0.1 {               // mouse wheel: one step per event
                onScroll?(e.scrollingDeltaY)
            }
        }
        override func hitTest(_ p: NSPoint) -> NSView? {
            // let clicks through to SwiftUI, capture the wheel
            if let e = NSApp.currentEvent, e.type == .scrollWheel || (e.type == .rightMouseDown && onRightClick != nil) { return self }
            return nil
        }
    }
    func makeNSView(context: Context) -> V { let v = V(); v.onScroll = onScroll; v.onRightClick = onRightClick; return v }
    func updateNSView(_ v: V, context: Context) { v.onScroll = onScroll; v.onRightClick = onRightClick }
}

/// XY scope: mark on the X axis, space on the Y axis (a correctly tuned signal = a cross).
struct XYScopeView: View {
    let points: [XYPoint]
    var dot: CGFloat = 1.6
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.85)))
            let m = max(0.0001, points.map { max(abs($0.x), abs($0.y)) }.max() ?? 1)
            var p = Path()
            for pt in points {
                let x = size.width / 2 + CGFloat(pt.x / m) * size.width * 0.45
                let y = size.height / 2 - CGFloat(pt.y / m) * size.height * 0.45
                p.addEllipse(in: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
            }
            ctx.fill(p, with: .color(.green))
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray.opacity(0.6)))
    }
}

/// Line spectrum (FFT) above the waterfall with mark/space cursors; click = tune, wheel = squelch.
struct SpectrumView: View {
    @Bindable var model: AppModel

    func x(_ hz: Double, _ w: CGFloat) -> CGFloat {
        CGFloat((hz - model.waterfallFromHz) / (model.waterfallToHz - model.waterfallFromHz)) * w
    }

    var body: some View {
        GeometryReader { g in
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.08)))
                // grid every 500 Hz
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
            .hint(L("Spektrum · klik = naladit mark · pravé tlačítko = zářez (notch) · kolečko = squelch"))
            .overlay { BandMapOverlay(model: model, topInset: 24) }
            .overlay(alignment: .topLeading) { SpectrumMenu(model: model).padding(4) }
        }
    }
}

/// Quick choice of the spectrum/waterfall range and gain (like the FFT width buttons in MMTTY).
struct SpectrumMenu: View {
    @Bindable var model: AppModel
    var body: some View {
        Menu {
            Section(L("Rozsah")) {
                ForEach(DisplayTab.ranges, id: \.0) { r in
                    Button((model.waterfallFromHz == r.1 && model.waterfallToHz == r.2 ? "✓ " : "") + r.0) {
                        Task { await model.setDisplay { $0.fromHz = r.1; $0.toHz = r.2 } }
                    }
                }
            }
            Section(L("Spoty")) {
                Button((model.settings.spots.showInWaterfall ? "✓ " : "") + L("Spoty ve vodopádu")) {
                    model.setSpots { $0.showInWaterfall.toggle() }
                }
            }
            Section(L("Zesílení (%ld dB)", Int(model.settings.display.gainDB))) {
                Button("+3 dB") { Task { await model.setDisplay { $0.gainDB += 3 } } }
                Button("−3 dB") { Task { await model.setDisplay { $0.gainDB -= 3 } } }
                Button("0 dB") { Task { await model.setDisplay { $0.gainDB = 0 } } }
                Button((model.settings.display.autoGain ? "✓ " : "") + L("Automatické zesílení")) {
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
        .hint(L("Rozsah a zesílení spektra a vodopádu"))
    }
}

extension WaterfallView {
    /// Low XY scope quality: every other point (MMTTY "XYScope Quality").
    static func decimate(_ p: [XYPoint]) -> [XYPoint] { p.enumerated().compactMap { $0.offset % 2 == 0 ? $0.element : nil } }
}
