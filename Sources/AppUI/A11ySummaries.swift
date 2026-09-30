// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Localization
import ModemKit

/// Spoken descriptions of the drawn views (spectrum, waterfall, demodulator scope, band map labels).
/// A picture of noise says nothing, so the values behind the picture are spoken instead. Pure functions - testable,
/// the views only read them.
public enum SpokenSummary {
    /// Relative signal strength 0…1 on the same scale as the meter in the top bar (four decades of the demodulator level).
    public static func signalFraction(level: Double) -> Double {
        min(1, max(0, log10(max(level, 1)) / 4))
    }

    /// A coarse (spoken) signal strength - an exact number means nothing by ear.
    public static func signalWord(level: Double) -> String {
        let f = signalFraction(level: level)
        if f < 0.05 { return L("bez signálu") }
        if f < 0.3 { return L("slabý signál") }
        if f < 0.55 { return L("střední signál") }
        if f < 0.8 { return L("silný signál") }
        return L("velmi silný signál")
    }

    /// The tuning summary = the accessibility value of the spectrum and the waterfall.
    public static func tuning(mark: Double, space: Double, afc: Bool, level: Double, squelchOpen: Bool,
                              notches: Int = 0) -> String {
        var parts = [L("mark %ld Hz", Int(mark.rounded())),
                     L("space %ld Hz", Int(space.rounded())),
                     L("shift %ld Hz", Int(abs(space - mark).rounded())),
                     afc ? L("AFC zapnuto") : L("AFC vypnuto"),
                     signalWord(level: level),
                     squelchOpen ? L("squelch otevřen") : L("squelch zavřen")]
        if notches > 0 { parts.append(L("zářezů: %ld", notches)) }
        return parts.joined(separator: ", ")
    }

    /// The demodulator scope: what the traces show (the window, the mark/space levels, the decided bit, the start bits).
    /// `width` = how many samples are displayed, `offset` 0…1 = the shift of the window (the same as what is drawn).
    public static func scope(source: String, scope: DemodScope?, sourceIndex: Int, frozen: Bool,
                             width: Int, offset: Double) -> String {
        let head = L("scope, zdroj %@", source)
        guard let d = scope, !d.bit.isEmpty, d.marks.indices.contains(sourceIndex),
              d.spaces.indices.contains(sourceIndex) else {
            return head + ", " + L("čekám na data")
        }
        let mk = d.marks[sourceIndex], sp = d.spaces[sourceIndex]
        guard !mk.isEmpty, mk.count == sp.count else { return head + ", " + L("tento zdroj se neplní") }
        let n = min(d.bit.count, mk.count)
        let w = max(1, min(n, width))
        let start = min(max(0, Int(Double(n - w) * min(max(offset, 0), 1))), max(0, n - w))
        let range = start..<(start + w)
        func mean(_ v: [Float]) -> Double { v[range].reduce(0) { $0 + Double(abs($1)) } / Double(w) }
        let m = mean(mk), s = mean(sp)
        let peak = max(m, s, 1e-9)
        var parts = [head,
                     L("zobrazeno %ld z %ld vzorků", w, n),
                     L("mark %ld procent", Int((m / peak * 100).rounded())),
                     L("space %ld procent", Int((s / peak * 100).rounded())),
                     L("bit v mark %ld procent času", Int((Double(d.bit[range].filter { $0 > 0.5 }.count) / Double(w) * 100).rounded()))]
        if d.sync.count >= start + w {
            parts.append(L("startbitů: %ld", d.sync[range].filter { $0 < -0.75 }.count))
        }
        if frozen { parts.append(L("zmrazeno")) }
        return parts.joined(separator: ", ")
    }

    /// A band map / waterfall label: callsign, frequency, age and whether the station is new, worked or a dupe.
    /// `ageMinutes` = nil for a record from the log (its age is given by the chosen window).
    public static func spot(call: String, kHz: Double, ageMinutes: Int?, status: String) -> String {
        var parts = [spokenCall(call), L("%.1f kHz", kHz)]
        if let a = ageMinutes { parts.append(L("před %ld min", a)) }
        parts.append(status)
        return parts.joined(separator: ", ")
    }

    /// A callsign letter by letter would be too slow; a screen reader reads the groups of letters and digits
    /// of a callsign reasonably on its own, only the slash is spelled out ("OK1XOE/P").
    public static func spokenCall(_ call: String) -> String {
        call.replacingOccurrences(of: "/", with: " " + L("lomeno") + " ")
    }
}

/// Reading the received text on demand (the "read the last line" / "read the previous line" commands).
/// RTTY arrives character by character and is often garbled, so nothing is read continuously - the operator asks.
public enum RxLineReader {
    /// At most this many characters are spoken from one line (RTTY can run on without a CR); the end of the line is kept,
    /// because that is the newest text.
    public static let maxSpoken = 240
    /// How many lines back can be stepped through (the snapshot for the "previous line" command).
    public static let maxLines = 60

    /// The lines of the received text in their natural order (the oldest first). Empty lines and lines of only
    /// whitespace are skipped - noise between transmissions produces plenty of them and they say nothing.
    public static func lines(_ text: String) -> [String] {
        // isNewline also covers CR LF, which Swift treats as a single character
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The last `maxLines` lines (a snapshot for stepping back, so newly arriving text does not shift the lines).
    public static func recentLines(_ text: String) -> [String] { Array(lines(text).suffix(maxLines)) }

    /// `back` = 0 the last line, 1 the one before it…; nil = there is no such line.
    public static func line(_ lines: [String], back: Int) -> String? {
        guard back >= 0, back < lines.count else { return nil }
        return spoken(lines[lines.count - 1 - back])
    }

    /// The text of a line for reading aloud: shortened to `maxSpoken` characters (the end of the line is kept).
    public static func spoken(_ line: String) -> String {
        line.count <= maxSpoken ? line : String(line.suffix(maxSpoken))
    }
}
