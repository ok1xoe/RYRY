// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import AppUI
import Localization
import Settings
import SwiftUI

/// The "Multipliers" window: a band × multiplier-kind grid, a summary and the worked / missing multipliers.
public struct MultipliersWindow: View {
    @Bindable var model: AppModel
    /// The band selected for the detail view; nil = "once per contest" multipliers.
    @State private var detailBand: String?
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let rule = model.multiplierRule {
                header(rule)
                if rule.hasMultipliers, let t = model.multipliers {
                    summary(t)
                    grid(t)
                    Divider()
                    detail(t)
                }
            } else {
                Text(L("Násobiče se počítají jen v zapnutém závodě se zvolenou předvolbou (Nastavení → Závod)."))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
    }

    func header(_ rule: MultiplierRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rule.preset.title).font(.headline)
            Text(rule.note).font(.callout).fixedSize(horizontal: false, vertical: true)
            if !rule.verified || !rule.unverifiedNote.isEmpty {
                Label(rule.verified ? L("Neověřeno: %@", rule.unverifiedNote) : L("Pravidlo neověřeno v oficiálních pravidlech."),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let url = URL(string: rule.source) {
                Link(L("Pravidla závodu"), destination: url).font(.caption)
            }
        }
    }

    func summary(_ t: MultiplierTally) -> some View {
        HStack(spacing: 16) {
            Text(L("Násobičů celkem: %ld", t.total)).font(.title3.bold())
            if !t.rule.bandWeights.isEmpty {
                Text(L("s váhou pásem: %ld", t.weightedTotal)).font(.title3)
            }
            Text(L("Spojení v závodě: %ld", t.qsoCount)).foregroundStyle(.secondary)
        }
    }

    var perBandKinds: [MultiplierKind] { (model.multiplierRule?.components ?? []).filter(\.perBand).map(\.kind) }
    var onceKinds: [MultiplierKind] { (model.multiplierRule?.components ?? []).filter { !$0.perBand }.map(\.kind) }
    func rows(_ t: MultiplierTally) -> [String] { Multipliers.sortBands(Array(Set(Multipliers.contestBands + t.bands))) }

    func grid(_ t: MultiplierTally) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
            GridRow {
                Text(L("Pásmo")).bold().gridColumnAlignment(.leading)
                ForEach(perBandKinds, id: \.self) { Text(t.rule.title($0)).bold() }
                ForEach(onceKinds, id: \.self) { Text(t.rule.title($0)).bold() }
                Text(L("Celkem")).bold()
            }
            Divider()
            if !perBandKinds.isEmpty {
                ForEach(rows(t), id: \.self) { b in
                    GridRow {
                        Button(b) { detailBand = b }.buttonStyle(.link)
                        ForEach(perBandKinds, id: \.self) { k in Text("\(t.worked(k, band: b).count)").monospacedDigit() }
                        ForEach(onceKinds, id: \.self) { _ in Text("") }
                        Text(weighted(t, b)).monospacedDigit()
                    }
                }
            }
            if !onceKinds.isEmpty {
                GridRow {
                    Button(L("Za závod")) { detailBand = nil }.buttonStyle(.link)
                    ForEach(perBandKinds, id: \.self) { _ in Text("") }
                    ForEach(onceKinds, id: \.self) { k in Text("\(t.worked(k, band: nil).count)").monospacedDigit() }
                    Text("\(t.onceCount)").monospacedDigit()
                }
            }
            Divider()
            GridRow {
                Text(L("Celkem")).bold()
                ForEach(perBandKinds, id: \.self) { k in Text("\(t.total(k))").bold().monospacedDigit() }
                ForEach(onceKinds, id: \.self) { k in Text("\(t.total(k))").bold().monospacedDigit() }
                Text("\(t.total)").bold().monospacedDigit()
            }
        }
    }

    func weighted(_ t: MultiplierTally, _ b: String) -> String {
        let n = t.count(band: b)
        guard let w = t.rule.bandWeights[b], w != 1 else { return "\(n)" }
        return "\(n) × \(w)"
    }

    @ViewBuilder func detail(_ t: MultiplierTally) -> some View {
        let bandKinds = perBandKinds, once = onceKinds
        Picker(L("Detail"), selection: $detailBand) {
            if !bandKinds.isEmpty { ForEach(rows(t), id: \.self) { Text($0).tag(String?.some($0)) } }
            if !once.isEmpty { Text(L("Za závod")).tag(String?.none) }
        }
        .pickerStyle(.segmented)
        .onAppear { if detailBand == nil, once.isEmpty { detailBand = rows(t).first { t.count(band: $0) > 0 } ?? rows(t).first } }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(detailBand == nil ? once : bandKinds, id: \.self) { k in
                    let worked = Self.sorted(t.worked(k, band: detailBand))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(t.rule.title(k)) (\(worked.count))").bold()
                        Text(worked.isEmpty ? "—" : worked.map(k.label).joined(separator: " "))
                            .font(.body.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        if let miss = t.missing(k, band: detailBand), !miss.isEmpty {
                            Text(L("Chybí (%ld): %@", miss.count, miss.map(k.label).joined(separator: " ")))
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Numbers (zones) numerically, everything else alphabetically.
    static func sorted(_ s: Set<String>) -> [String] {
        s.sorted { a, b in
            if let x = Int(a), let y = Int(b) { return x < y }
            return a < b
        }
    }
}
