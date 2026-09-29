// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import ModemKit
import RTTYModem
import SwiftUI

/// Scope demodulátoru (MMTTY „Digital Scope“): průběhy mark/space ze zvoleného místa demodulátoru,
/// rozhodnutý bit a synchronizace (start/stop bity). Slouží k ladění parametrů demodulátoru.
public struct ScopeWindow: View {
    @Bindable var model: AppModel
    @State private var width = 2048.0          // zobrazených vzorků
    @State private var offset = 0.0
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 6) {
            HStack {
                Picker("Zdroj", selection: $model.scopeSource) {
                    ForEach(Array(RTTYModem.scopeSources.enumerated()), id: \.offset) { i, n in Text(n).tag(i) }
                }.pickerStyle(.segmented).fixedSize()
                Toggle("Zmrazit", isOn: $model.scopeFrozen).toggleStyle(.button)
                    .help("Podržet poslední záznam (jednorázové zachycení)")
                Spacer()
                Text("Šířka").font(.caption)
                Slider(value: $width, in: 256...8192).frame(width: 140)
                Text("Posun").font(.caption)
                Slider(value: $offset, in: 0...1).frame(width: 140)
            }
            if model.scopeSource == 3 && model.param("atc") != .bool(true) {
                Text("Zdroj ATC vyžaduje zapnuté ATC.").font(.caption).foregroundStyle(.secondary)
            } else if let d = model.demodScope, d.marks.indices.contains(model.scopeSource), d.marks[model.scopeSource].isEmpty {
                Text("Tento zdroj se u zvoleného demodulátoru neplní.").font(.caption).foregroundStyle(.secondary)
            }
            Canvas { ctx, size in draw(ctx, size) }
                .background(Color.black)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("mark", systemImage: "circle.fill").foregroundStyle(.yellow)
                        Label("space", systemImage: "circle.fill").foregroundStyle(.orange)
                        Label("bit", systemImage: "circle.fill").foregroundStyle(.green)
                        Label("sync (▼ start, ▽ stop)", systemImage: "circle.fill").foregroundStyle(.cyan)
                    }.font(.caption2).padding(6)
                }
            if model.demodScope == nil {
                Text("Čekám na data… (scope sbírá při příjmu dávky po 8192 vzorcích)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(minWidth: 700, minHeight: 380)
        .onAppear { Task { await model.setDemodScope(true) } }
        .onDisappear { Task { await model.setDemodScope(false) } }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        guard let d = model.demodScope, !d.bit.isEmpty, d.marks.indices.contains(model.scopeSource) else { return }
        let mk = d.marks[model.scopeSource], sp = d.spaces[model.scopeSource]
        guard !mk.isEmpty, mk.count == sp.count else { return }
        let n = min(d.bit.count, mk.count)
        let w = max(16, min(n, Int(width)))
        let start = Int(Double(n - w) * offset)
        let lane = size.height / 4
        func path(_ v: [Float], top: CGFloat, height: CGFloat, scale: Float) -> Path {
            var p = Path()
            for i in 0..<w {
                let x = CGFloat(i) / CGFloat(w - 1) * size.width
                let y = top + height - CGFloat(max(0, min(1, v[start + i] / scale))) * height
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            return p
        }
        // mark/space – společná automatická stupnice, horní dvě pásma
        let peak = max(1e-6, (mk[start..<(start + w)] + sp[start..<(start + w)]).map { abs($0) }.max() ?? 1)
        ctx.stroke(path(mk.map { abs($0) }, top: 4, height: lane * 2 - 8, scale: peak), with: .color(.yellow), lineWidth: 1)
        ctx.stroke(path(sp.map { abs($0) }, top: 4, height: lane * 2 - 8, scale: peak), with: .color(.orange), lineWidth: 1)
        // bit
        ctx.stroke(path(d.bit, top: lane * 2 + 6, height: lane - 12, scale: 1), with: .color(.green), lineWidth: 1.2)
        // sync: značky
        let top = lane * 3 + 4
        for i in 0..<w {
            let v = d.sync[start + i]
            guard v != 0 else { continue }
            let x = CGFloat(i) / CGFloat(w - 1) * size.width
            var p = Path()
            p.move(to: CGPoint(x: x, y: top + (v < -0.75 ? 0 : v < 0 ? lane * 0.3 : lane * 0.6)))
            p.addLine(to: CGPoint(x: x, y: top + lane - 8))
            ctx.stroke(p, with: .color(v < 0 ? .cyan : .cyan.opacity(0.35)), lineWidth: v < -0.75 ? 1.5 : 1)
        }
        for k in 1..<4 {
            var p = Path(); let y = lane * CGFloat(k)
            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(p, with: .color(.white.opacity(0.12)), lineWidth: 1)
        }
    }
}
