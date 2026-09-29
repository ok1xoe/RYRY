// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// Band map: převod RF frekvence spotu na audio pozici ve vodopádu a rozložení štítků.
public enum BandMap {
    /// Zobrazitelná audio frekvence (vodopád 0–4000 Hz).
    public static let audioRange = 0.0...4000.0
    /// Nejvýše tolik štítků (nejnovější spoty).
    public static let maxMarkers = 20
    /// Nejvýše tolik řádků štítků nad vodopádem; co se nevejde, se nezobrazí.
    public static let maxRows = 4

    /// Jak rádio převádí RF na audio podle módu z rigu.
    public enum Sideband: Sendable, Equatable {
        case upper, lower
        /// RTTY/FSK (rig hlásí dial ≈ mark): spot na dialu zní na aktuálním marku, vyšší RF = nižší tón.
        case rtty
        /// RTTYR / FSK-R: obráceně, vyšší RF = vyšší tón.
        case rttyReverse
    }

    /// USB/PKTUSB → horní pásmo; LSB/PKTLSB → dolní; RTTY/FSK → `rtty`, RTTYR/RTTY-R/FSKR/FSK-R → `rttyReverse`.
    /// Neznámý mód (CW, AM…) → nil.
    public static func sideband(mode: String?) -> Sideband? {
        guard let m = mode?.uppercased(), !m.isEmpty else { return nil }
        if m.contains("USB") { return .upper }
        if m.contains("LSB") { return .lower }
        if m.contains("RTTY") || m.contains("FSK") {
            let reversed = m.hasSuffix("R") || m.contains("-R") || m.contains("REV")
            return reversed ? .rttyReverse : .rtty
        }
        return nil
    }

    /// Audio pozice (Hz) spotu při dialu rigu `dialHz` a módu `mode`; nil pro neznámý mód nebo pozici mimo 0…4000 Hz.
    ///
    /// USB/LSB: dvojklik (`useSpot`) nastaví rig na `spot + offsetHz` (cíl `target`). Tón, který si tím uživatel
    /// zvolil, je `offsetHz` v dolním pásmu (LSB/AFSK s mark 2125 Hz → +2125) a `−offsetHz` v horním; od něj se pozice
    /// počítá podle vzdálenosti dialu od cíle. Výsledek je fyzikální (USB: spot − dial, LSB: dial − spot):
    /// po dvojkliku leží značka přesně na tónu daném posunem a klik na značku (mark = audio pozice) míří na totéž.
    ///
    /// RTTY/FSK: rádio hlásí dial ≈ mark a stanice na dialu zní na tónu, na který je naladěný dekodér –
    /// audio = `markHz` (aktuální mark) + (dial − spot), u RTTYR opačné znaménko. Posun se v tomto módu nepoužije
    /// (pro FSK má být 0: dvojklik pak naladí stanici přímo na mark). Bez `markHz` → nil.
    public static func audioOffset(spotHz: Double, dialHz: Double, mode: String?, offsetHz: Double, markHz: Double? = nil) -> Double? {
        guard let sb = sideband(mode: mode), spotHz > 0, dialHz > 0 else { return nil }
        let target = spotHz + offsetHz
        let audio: Double
        switch sb {
        case .upper: audio = -offsetHz + (target - dialHz)
        case .lower: audio = offsetHz + (dialHz - target)
        case .rtty, .rttyReverse:
            guard let markHz, markHz.isFinite else { return nil }
            audio = sb == .rtty ? markHz + (dialHz - spotHz) : markHz + (spotHz - dialHz)
        }
        return audioRange.contains(audio) ? audio : nil
    }

    /// Rozloží štítky (šířky v bodech, střed `centers[i]`) do řádků: v pořadí priority (první = nejdůležitější) každý
    /// dostane první řádek, kde se nepřekrývá s dřívějšími (mezera `gap`). Bez místa v `maxRows` řádcích → nil.
    /// Štítek se posune tak, aby zůstal v 0…`totalWidth`; překryv se počítá s posunutou polohou.
    public static func layoutRows(centers: [Double], widths: [Double], totalWidth: Double,
                                  gap: Double = 2, maxRows: Int = BandMap.maxRows) -> [Int?] {
        var rows = [[ClosedRange<Double>]](repeating: [], count: max(0, maxRows))
        var out: [Int?] = []
        for (c, w) in zip(centers, widths) {
            let lo = min(max(c - w / 2, 0), max(0, totalWidth - w))
            let r = (lo - gap)...(lo + w + gap)
            if let i = rows.indices.first(where: { row in !rows[row].contains { $0.overlaps(r) } }) {
                rows[i].append(lo...(lo + w)); out.append(i)
            } else { out.append(nil) }
        }
        return out
    }
}
