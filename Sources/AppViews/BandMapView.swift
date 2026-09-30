// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppUI
import Localization
import Spots
import SwiftUI

extension BandMapMarker.Status {
    var color: Color {
        switch self { case .new: .green; case .worked: .orange; case .dupe: .red }
    }
    var legend: String {
        switch self { case .new: L("nová stanice"); case .worked: L("už v logu"); case .dupe: L("duplicita v závodě") }
    }
}

/// Spot labels (band map) above the waterfall/spectrum plus vertical dotted lines; clicking a label sets the mark to the spot's position and puts the call into the QSO panel.
struct BandMapOverlay: View {
    @Bindable var model: AppModel
    /// Inset of the first row from the top edge (room for the scale/menu).
    var topInset: CGFloat = 16
    static let rowHeight: CGFloat = 15

    /// Label width in points (monospace caption2 ≈ 6 points per character plus margins).
    static func width(of m: BandMapMarker) -> CGFloat { CGFloat(m.spot.call.count) * 6.2 + 10 }

    var body: some View {
        let markers = model.bandMapMarkers
        GeometryReader { g in
            let span = model.waterfallToHz - model.waterfallFromHz
            if !markers.isEmpty, span > 0 {
                let xs = markers.map { CGFloat(($0.audioHz - model.waterfallFromHz) / span) * g.size.width }
                let ws = markers.map(Self.width(of:))
                let rows = BandMap.layoutRows(centers: xs.map(Double.init), widths: ws.map(Double.init), totalWidth: Double(g.size.width))
                Canvas { ctx, size in
                    for (i, m) in markers.enumerated() {
                        guard let r = rows[i] else { continue }
                        var p = Path()
                        p.move(to: CGPoint(x: xs[i], y: topInset + CGFloat(r + 1) * Self.rowHeight - 2))
                        p.addLine(to: CGPoint(x: xs[i], y: size.height))
                        ctx.stroke(p, with: .color(m.status.color.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                    }
                }
                .allowsHitTesting(false)
                ForEach(Array(markers.enumerated()), id: \.element.id) { i, m in
                    if let r = rows[i] {
                        let left = min(max(xs[i] - ws[i] / 2, 0), max(0, g.size.width - ws[i]))
                        Button { Task { await model.bandMapClick(m) } } label: {
                            Text(verbatim: m.spot.call).font(.caption2.monospaced().bold())
                                .foregroundStyle(.black).frame(width: ws[i], height: Self.rowHeight - 1)
                                .background(m.status.color.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                        .offset(x: left, y: topInset + CGFloat(r) * Self.rowHeight)
                        .hint(String(format: "%@ · %.1f kHz · %@ · %@", m.spot.call, m.spot.frequencyKHz, m.status.legend,
                                     L("klik = naladit mark a vložit značku")))
                        .accessibilityLabel(L("Spot %@, %.1f kHz, %@", m.spot.call, m.spot.frequencyKHz, m.status.legend))
                    }
                }
            }
        }
    }
}
