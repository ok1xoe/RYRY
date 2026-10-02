// Copyright 2026 OK1XOE (RYRY), LGPL v3
import Localization
import SwiftUI

/// The macro variables as a clear table: the codes bold in the accent color, grouped (stations, report and exchange,
/// time, control). Shown in the macro editor and in Settings → Contest.
struct MacroVariablesHelp: View {
    struct Group: Identifiable { let id: String; let rows: [(String, String)] }

    static var groups: [Group] {
        [Group(id: L("Stanice"), rows: [
            ("%c", L("značka protistanice")), ("%n", L("jméno protistanice (jinak OM)")), ("%q", L("QTH protistanice")),
            ("%m", L("moje značka")), ("%a", L("moje jméno (bez diakritiky)")), ("%o", L("můj lokátor")),
            ("%Z", L("moje CQ zóna")),
        ]),
         Group(id: L("Report a výměna"), rows: [
            ("%r", L("odesílané RST (s výměnou)")), ("%R", L("odesílané RST (jen 3 znaky)")), ("%s", L("přijaté RST (s výměnou)")),
            ("%N", L("odesílaná výměna závodu bez RST – 001, BHE, 015 TOMAS DX")), ("%M", L("přijatá výměna")),
            ("%S", L("moje pořadové číslo")), ("%X", L("text výměny bez čísla – zóna, teritorium, jméno + QTH")),
            ("%x %y", L("číslo a čas (BARTG)")),
        ]),
         Group(id: L("Čas a pozdrav"), rows: [
            ("%g", L("pozdrav GOOD MORNING/AFTERNOON/EVENING podle místního času protistanice")), ("%f", L("totéž krátce GM/GA/GE")),
            ("%D", L("datum UTC")), ("%T %t", L("čas UTC (12:34 / 1234)")),
        ]),
         Group(id: L("Řízení"), rows: [
            ("%l", L("zalogovat QSO")), ("%{…}", L("CW identifikace")), ("%L %F", L("LTRS / FIGS")), ("%E", L("konec makra")),
            ("\\", L("na konci = po odvysílání příjem, na začátku = vysílat a text do okna")),
            ("#", L("na konci = zůstat ve vysílání, na začátku = jen do okna vysílání")),
        ])]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.groups) { g in
                VStack(alignment: .leading, spacing: 4) {
                    Text(g.id).font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                        ForEach(g.rows, id: \.0) { code, text in
                            GridRow {
                                Text(code).font(.system(.body, design: .monospaced).bold()).foregroundStyle(Color.accentColor)
                                    .gridColumnAlignment(.trailing)
                                Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}
