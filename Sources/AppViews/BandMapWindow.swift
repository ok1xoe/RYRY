// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppKit
import AppUI
import Localization
import QSOLog
import Spots
import SwiftUI

/// The "Band map" window: a vertical scale of the RTTY part of the band (like the Bandmap in N1MM Logger+) with spots from the DX cluster / RBN,
/// worked stations from the log and a marker for the rig's frequency. Clicking a spot does the same as a double-click in Spots.
public struct BandMapWindow: View {
    @Bindable var model: AppModel
    /// Manual band choice (nil = automatic, from the rig / the manual QSO frequency).
    @State private var bandChoice: String?
    @State private var scales: [String: BandScale] = [:]
    @State private var showLogged = true
    @State private var loggedMinutes = 60
    /// The band picked from the spots. It is remembered so that the map does not jump whenever the per-band spot counts change.
    @State private var latchedBand: String?
    /// The bottom edge of the scale when the drag started; `@GestureState` resets itself even when the gesture is cancelled.
    @GestureState private var panStartLow: Double?
    /// A fixed start for the redraw timer; `.now` in the schedule would create a new schedule on every render.
    @State private var timelineStart = Date()
    public init(model: AppModel) { self.model = model }

    static let rowHeight: CGFloat = 16
    static let rulerWidth: CGFloat = 64
    static let labelWidth: CGFloat = 118

    /// Step of the scale labels in kHz, based on the visible range.
    static func tickStep(span: Double) -> Double {
        for s in [0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500] where span / s <= 14 { return s }
        return 500
    }

    struct Entry: Identifiable {
        let id: String
        let kHz: Double
        let text: String
        let color: Color
        let spot: Spot?
        let tip: String
    }

    var rigKHz: Double? {
        guard let r = model.rig, r.online, let f = r.frequency, f > 0 else { return nil }
        return f / 1000
    }

    /// Bands with spots, the busiest first - a fallback when neither the rig nor the QSO window determines the band.
    /// On a tie the band plan order decides, not the alphabet.
    var spotBands: [String] {
        var n: [String: Int] = [:]
        for s in model.spotFeed.book.byID.values where model.spotFeed.filter.matchesMode(s) {
            if let b = s.band { n[b, default: 0] += 1 }
        }
        func order(_ b: String) -> Int { RTTYBandPlan.bands.firstIndex(of: b) ?? RTTYBandPlan.bands.count }
        return n.sorted { $0.value != $1.value ? $0.value > $1.value : order($0.key) < order($1.key) }.map(\.key)
    }

    /// The band from the manual choice, the rig or the frequency in the QSO window; nil = none of those determines a band.
    var chosenBand: String? {
        // read the manual QSO frequency only when neither the manual choice nor the rig gives a band (otherwise every change in the QSO window would redraw the map)
        RTTYBandPlan.selectBand(choice: bandChoice, rigHz: rigKHz.map { $0 * 1000 }, manualHz: nil)
            ?? RTTYBandPlan.selectBand(choice: nil, rigHz: nil, manualHz: model.qso.frequency)
    }

    /// Never nil: with no rig and no frequency in the QSO window the remembered band with spots is shown, otherwise the default band.
    var band: String { chosenBand ?? latchedBand ?? RTTYBandPlan.defaultBand }

    /// Remembers the band with spots as long as neither the rig nor the QSO window determines a band. It is not overwritten with every new spot,
    /// so that the map does not jump under the user's hand (and so that a drag does not end on a different band than it started on).
    func latchBandIfNeeded() {
        guard chosenBand == nil, latchedBand == nil, let b = spotBands.first else { return }
        latchedBand = b
    }

    func scale(for band: String) -> BandScale {
        scales[band] ?? BandScale(segment: RTTYBandPlan.segment(for: band)!)
    }

    func zoom(_ factor: Double, band: String, around f: Double? = nil) {
        var s = scale(for: band); s.zoom(by: factor, around: f ?? rigKHz.flatMap { scale(for: band).contains(kHz: $0) ? $0 : nil })
        scales[band] = s
    }

    func entries(band: String, scale: BandScale, now: Date) -> [Entry] {
        let feed = model.spotFeed
        let spots = BandMapFilter.spots(feed.book.byID.values.map { $0 }, band: band, filter: feed.filter,
                                        maxAgeMinutes: max(1, feed.config.maxAgeMinutes), now: now)
        var out: [Entry] = []
        for s in spots where scale.contains(kHz: s.frequencyKHz) {
            let st = model.spotStatus(s)                         // the log index in AppModel: O(1) per spot
            let age = BandMapFilter.ageMinutes(of: s, now: now)
            out.append(Entry(id: "s|" + s.id, kHz: s.frequencyKHz, text: "\(s.call)  \(L("%ld min", age))", color: st.color, spot: s,
                             tip: String(format: "%@ · %.1f kHz · %@ · %@", s.call, s.frequencyKHz, st.legend,
                                         L("klik = naladit rig a vložit značku"))))
        }
        if showLogged {
            for r in BandMapFilter.logged(model.logRecords, band: band, minutes: loggedMinutes, now: now) {
                guard let f = r.frequency, scale.contains(kHz: f / 1000) else { continue }
                out.append(Entry(id: "l|" + r.id.uuidString, kHz: f / 1000, text: r.call + " ✓", color: .gray, spot: nil,
                                 tip: String(format: "%@ · %.1f kHz · %@", r.call, f / 1000, L("odpracováno"))))
            }
        }
        return out
    }

    public var body: some View {
        VStack(spacing: 6) {
            controls
            TimelineView(.periodic(from: timelineStart, by: 30)) { ctx in
                mapView(band: band, now: ctx.date)
            }
        }
        .padding(8)
        .frame(minWidth: 280, minHeight: 360)
        .onAppear { latchBandIfNeeded() }
        .onChange(of: model.spotFeed.book.count) { latchBandIfNeeded() }
    }

    /// Band selection; "auto" = from the rig, the frequency in the QSO window or the spots.
    var bandPicker: some View {
        Picker(L("Pásmo"), selection: $bandChoice) {
            Text(L("auto (%@)", band)).tag(String?.none)
            ForEach(RTTYBandPlan.bands, id: \.self) { Text($0).tag(String?.some($0)) }
        }
        .labelsHidden().fixedSize()
        .hint(L("Pásmo mapy; auto = podle rigu, frekvence v QSO okně nebo spotů"))
    }

    var zoomButtons: some View {
        HStack(spacing: 8) {
            Button { zoom(0.6, band: band) } label: { Image(systemName: "plus.magnifyingglass") }
                .hint(L("Přiblížit stupnici (Shift + kolečko myši)"))
            Button { zoom(1 / 0.6, band: band) } label: { Image(systemName: "minus.magnifyingglass") }
                .hint(L("Oddálit stupnici (Shift + kolečko myši)"))
            Button { var s = scale(for: band); s.reset(); scales[band] = s } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .hint(L("Celý RTTY úsek pásma"))
            Button {
                if let f = rigKHz { var s = scale(for: band); s.center(on: f); scales[band] = s }
            } label: { Image(systemName: "scope") }
                .hint(L("Střed na rig")).disabled(rigKHz == nil)
        }
    }

    var logControls: some View {
        HStack(spacing: 8) {
            Toggle(L("Můj log"), isOn: $showLogged).toggleStyle(.checkbox)
            if showLogged {
                Stepper(value: $loggedMinutes, in: 5...1440, step: 15) { Text(L("%ld min", loggedMinutes)).monospacedDigit() }
                    .fixedSize()
            }
        }
    }

    /// In a narrow window the controls wrap onto two rows (otherwise the labels would be clipped).
    var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { bandPicker; zoomButtons; Spacer(minLength: 8); logControls }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) { bandPicker; Spacer(minLength: 4); zoomButtons }
                logControls
            }
        }
    }

    func mapView(band: String, now: Date) -> some View {
        let sc = scale(for: band)
        let list = entries(band: band, scale: sc, now: now)
        let empty = !model.settings.spots.clusterEnabled && !model.settings.spots.rbnEnabled && rigKHz == nil
        return GeometryReader { g in
            let h = g.size.height
            let ys = list.map { sc.y(forKHz: $0.kHz, height: h) }
            let adj = BandMapLayout.spread(ys, minGap: Self.rowHeight, height: h - Self.rowHeight)
            let labelX = max(Self.rulerWidth + 16, g.size.width - Self.labelWidth - 4)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let step = Self.tickStep(span: sc.span)
                    var f = (sc.visibleLow / step).rounded(.up) * step
                    while f <= sc.visibleHigh + 1e-9 {
                        let y = sc.y(forKHz: f, height: size.height)
                        var p = Path(); p.move(to: CGPoint(x: Self.rulerWidth - 8, y: y)); p.addLine(to: CGPoint(x: Self.rulerWidth, y: y))
                        ctx.stroke(p, with: .color(.secondary), lineWidth: 1)
                        ctx.draw(Text(String(format: step < 1 ? "%.1f" : "%.0f", f)).font(.caption2.monospacedDigit()).foregroundColor(.secondary),
                                 at: CGPoint(x: Self.rulerWidth - 12, y: y), anchor: .trailing)
                        f += step
                    }
                    var axis = Path(); axis.move(to: CGPoint(x: Self.rulerWidth, y: 0)); axis.addLine(to: CGPoint(x: Self.rulerWidth, y: size.height))
                    ctx.stroke(axis, with: .color(.secondary), lineWidth: 1)
                    for (i, e) in list.enumerated() {
                        var l = Path()
                        l.move(to: CGPoint(x: Self.rulerWidth, y: ys[i]))
                        l.addLine(to: CGPoint(x: labelX, y: adj[i] + Self.rowHeight / 2))
                        ctx.stroke(l, with: .color(e.color.opacity(0.6)), lineWidth: 1)
                    }
                    if let r = rigKHz, sc.contains(kHz: r) {
                        let y = sc.y(forKHz: r, height: size.height)
                        var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(line, with: .color(.red.opacity(0.7)), lineWidth: 1)
                        var tri = Path()
                        tri.move(to: CGPoint(x: Self.rulerWidth + 2, y: y)); tri.addLine(to: CGPoint(x: Self.rulerWidth + 10, y: y - 5))
                        tri.addLine(to: CGPoint(x: Self.rulerWidth + 10, y: y + 5)); tri.closeSubpath()
                        ctx.fill(tri, with: .color(.red))
                        ctx.draw(Text(String(format: "%.1f", r)).font(.caption2.monospacedDigit().bold()).foregroundColor(.red),
                                 at: CGPoint(x: 2, y: y - 7), anchor: .bottomLeading)
                    }
                }
                .allowsHitTesting(false)
                ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                    let label = Text(verbatim: e.text).font(.caption2.monospaced().bold()).lineLimit(1)
                        .foregroundStyle(e.spot == nil ? Color.white : Color.black)
                        .frame(width: Self.labelWidth, height: Self.rowHeight - 1, alignment: .leading).padding(.leading, 4)
                        .background(e.color.opacity(e.spot == nil ? 0.55 : 0.9), in: RoundedRectangle(cornerRadius: 3))
                    Group {
                        if let spot = e.spot {
                            Button { Task { await model.useSpot(spot) } } label: { label }.buttonStyle(.plain)
                        } else { label }
                    }
                    .offset(x: labelX, y: adj[i])
                    .hint(e.tip)
                }
                if empty {
                    Text(L("Zapněte DX cluster nebo RBN (Nastavení → Spoty)."))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 8)
                        .offset(x: 0, y: 0)
                }
                ScrollWheelHandler { points in                      // plain wheel = pan
                    guard h > 0 else { return }
                    var s = scale(for: band)
                    s.pan(by: points / h * s.span)
                    scales[band] = s
                } onZoom: { steps, fromTop in                        // Shift + wheel = zoom
                    let f = sc.kHz(forY: fromTop * h, height: h)
                    zoom(pow(0.85, Double(steps)), band: band, around: f)
                }
                .allowsHitTesting(false)
            }
            // mouse drag = pan the scale (only when it is zoomed in); the spot labels stay clickable
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .updating($panStartLow) { _, start, _ in if start == nil { start = sc.visibleLow } }
                    .onChanged { g in
                        guard h > 0 else { return }
                        var s = scale(for: band)
                        // pan relative to the position at the start of the gesture (not incrementally), so a cancelled gesture leaves nothing behind
                        s.moveLow(to: (panStartLow ?? sc.visibleLow) + g.translation.height / h * s.span)
                        scales[band] = s
                    }
            )
            .frame(width: g.size.width, height: h, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// The mouse wheel over the area: a local event monitor (SwiftUI on macOS has no view for scrollWheel).
/// Plain wheel = pan (`onPan` gets the shift in points, positive = towards higher frequencies);
/// Shift + wheel = zoom (`onZoom` gets the number of steps, > 0 = zoom in, and the cursor position from the top, 0…1).
private struct ScrollWheelHandler: NSViewRepresentable {
    var onPan: (Double) -> Void
    var onZoom: (Int, Double) -> Void

    final class Coordinator {
        var monitor: Any?
        var accumulator = ScrollZoomAccumulator()
        var onPan: (Double) -> Void = { _ in }
        var onZoom: (Int, Double) -> Void = { _, _ in }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// One wheel notch is not in points; move the scale by a readable step.
    static let pointsPerLine = 16.0

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let c = context.coordinator
        c.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak v] e in
            guard let v, let w = v.window, e.window === w else { return e }
            let p = v.convert(e.locationInWindow, from: nil)
            guard v.bounds.contains(p), v.bounds.height > 0 else { return e }
            // with Shift held macOS reports a vertical wheel as horizontal scrolling
            let shift = e.modifierFlags.contains(.shift)
            let raw = Double(e.scrollingDeltaY != 0 ? e.scrollingDeltaY : e.scrollingDeltaX)
            guard raw.isFinite, raw != 0 else { return nil }
            if e.phase.contains(.began) { c.accumulator.reset() }
            if shift {
                let steps = c.accumulator.feed(deltaY: raw, precise: e.hasPreciseScrollingDeltas,
                                               momentum: !e.momentumPhase.isEmpty)
                if steps != 0 { c.onZoom(steps, Double(1 - p.y / v.bounds.height)) }
            } else {
                c.onPan(e.hasPreciseScrollingDeltas ? raw : raw * Self.pointsPerLine)
            }
            return nil
        }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        context.coordinator.onPan = onPan
        context.coordinator.onZoom = onZoom
    }
    static func dismantleNSView(_ v: NSView, coordinator: Coordinator) {
        if let m = coordinator.monitor { NSEvent.removeMonitor(m) }
    }
}
