// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import AppUI
import Localization
import Settings
import SwiftUI

/// Okno „Skóre“: po pásmech QSO, body, násobiče (u WAE s váhou a QTC), řádek Celkem a výsledné skóre se vzorcem.
public struct ScoreWindow: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = model.score {
                header(s.rule)
                result(s)
                table(s)
                footer(s)
            } else {
                Text(L("Skóre se počítá jen v zapnutém závodě se zvolenou předvolbou (Nastavení → Závod)."))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
    }

    func header(_ rule: ScoreRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rule.preset.title).font(.headline)
            Text(rule.pointsNote).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    func result(_ s: ScoreTally) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("Skóre %@", ScoreTally.format(s.score)))
                .font(.system(size: 28, weight: .bold)).monospacedDigit().textSelection(.enabled)
            Text(s.formulaText).font(.title3).monospacedDigit().foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    var isWAE: Bool { model.score?.rule.formula == .qsoPlusQTCTimesWeightedMultipliers }
    var hasMultipliers: Bool { model.score?.multipliers.rule.hasMultipliers ?? false }

    func rows(_ s: ScoreTally) -> [String] { Multipliers.sortBands(Array(Set(Multipliers.contestBands + s.bands))) }

    func table(_ s: ScoreTally) -> some View {
        let m = s.multipliers
        return Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 4) {
            GridRow {
                Text(L("Pásmo")).bold().gridColumnAlignment(.leading)
                Text("QSO").bold()
                Text(L("Duplicity")).bold()
                Text(L("Body")).bold()
                if hasMultipliers { Text(L("Násobiče")).bold() }
                if isWAE { Text(L("S váhou")).bold(); Text("QTC").bold() }
            }
            Divider()
            ForEach(rows(s), id: \.self) { b in
                let x = s.band(b)
                GridRow {
                    Text(b == ScoreTally.unknownBand ? L("neznámé") : b).gridColumnAlignment(.leading)
                    num(x.qsos)
                    num(x.dupes)
                    num(x.points)
                    if hasMultipliers { num(m.count(band: b)) }
                    if isWAE { Text("\(m.count(band: b)) × \(m.rule.bandWeights[b] ?? 1)").monospacedDigit(); num(x.qtc) }
                }
            }
            if s.showsOnceMultiplierRow {
                GridRow {
                    Text(L("Za závod")).gridColumnAlignment(.leading)
                    Text(""); Text(""); Text("")
                    num(m.onceCount)
                    if isWAE { Text(""); Text("") }
                }
            }
            Divider()
            GridRow {
                Text(L("Celkem")).bold()
                num(s.qsos).bold()
                num(s.dupes).bold()
                num(s.points).bold()
                if hasMultipliers { num(s.tableMultiplierTotal).bold() }   // BARTG: bez kontinentů (ve vzorci zvlášť)
                if isWAE { num(m.weightedTotal).bold(); num(s.qtc).bold() }
            }
        }
    }

    func num(_ n: Int) -> Text { Text(ScoreTally.format(n)).monospacedDigit() }

    func footer(_ s: ScoreTally) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if s.ownCountryUnknown {
                Label(L("Vlastní země není známá (chybí značka v Nastavení → Stanice nebo databáze zemí) – body a násobiče nejsou správné."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if s.ownLocatorMissing {
                Label(L("Chybí vlastní lokátor (Nastavení → Stanice nebo výměna závodu) – spojení mají 0 bodů."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if s.rule.formula == .pointsTimesMultipliersTimesContinents {
                Text(L("Kontinenty: %ld (jednou za závod, násobí se zvlášť)", s.continents)).font(.callout)
            }
            Text(L("Duplicity (stejná stanice na stejném pásmu) mají 0 bodů; spojení mimo dobu závodu se nepočítají. Výsledek je odhad – vyhodnocení závodu odečte chybná a nepotvrzená spojení."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !s.rule.verified || !s.rule.unverifiedNote.isEmpty {
                Label(s.rule.verified ? L("Neověřeno: %@", s.rule.unverifiedNote) : L("Pravidlo neověřeno v oficiálních pravidlech."),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if !s.multipliers.rule.unverifiedNote.isEmpty {
                Label(L("Násobiče – neověřeno: %@", s.multipliers.rule.unverifiedNote), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let url = URL(string: s.rule.source) {
                Link(L("Pravidla závodu"), destination: url).font(.caption)
            }
        }
    }
}
