// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import ModemKit
import SwiftUI

struct WaterfallView: View {
    @Bindable var model: AppModel

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
                    // stupnice po 500 Hz
                    var hz = (model.waterfallFromHz / 500).rounded(.up) * 500
                    while hz < model.waterfallToHz {
                        let xx = x(hz, size.width)
                        ctx.draw(Text("\(Int(hz))").font(.caption2).foregroundStyle(.white.opacity(0.7)),
                                 at: CGPoint(x: xx, y: 8))
                        hz += 500
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { loc in
                    let hz = model.waterfallFromHz + Double(loc.x / g.size.width) * (model.waterfallToHz - model.waterfallFromHz)
                    Task { await model.tune(toMarkHz: hz) }
                }
                .help("Klik = naladit mark · kolečko = úroveň squelche")
                .overlay(ScrollWheelCatcher { dy in Task { await model.adjustSquelch(steps: dy > 0 ? 1 : -1) } })
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
    final class V: NSView {
        var onScroll: ((CGFloat) -> Void)?
        override func scrollWheel(with e: NSEvent) {
            if abs(e.scrollingDeltaY) > 0.5 { onScroll?(e.scrollingDeltaY) }
        }
        override func hitTest(_ p: NSPoint) -> NSView? {
            // kliky nechat projít do SwiftUI, kolečko zachytit
            if let e = NSApp.currentEvent, e.type == .scrollWheel { return self }
            return nil
        }
    }
    func makeNSView(context: Context) -> V { let v = V(); v.onScroll = onScroll; return v }
    func updateNSView(_ v: V, context: Context) { v.onScroll = onScroll }
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
