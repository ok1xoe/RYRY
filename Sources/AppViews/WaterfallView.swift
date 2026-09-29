// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
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
                .help("Klik = naladit mark na kmitočet")
                Text(String(format: "M %.0f  S %.0f", model.mark, model.space))
                    .font(.caption.monospaced()).padding(4)
                    .background(.black.opacity(0.5)).foregroundStyle(.white)
                    .padding(4).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
