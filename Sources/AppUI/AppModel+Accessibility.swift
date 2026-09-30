// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import Foundation
import Localization
import QSOLog
import Settings

/// Keyboard routes for actions that used to be reachable with the mouse only: clicking the waterfall to tune,
/// the right button in the spectrum for a notch, clicking a word in the receive window.
/// The commands are `ShortcutCommand.tuneStrongest`, `.notchStrongest` and `.insertLastCall`.
extension AppModel {
    /// Level below which the line spectrum (0…1 after the display gain) counts as noise only.
    nonisolated public static let signalThreshold: Float = 0.25

    /// Hz of the middle of bin `i` of a line spectrum of `bins` bins covering `from`…`to`.
    nonisolated static func binHz(_ i: Int, bins: Int, from: Double, to: Double) -> Double {
        from + (Double(i) + 0.5) * (to - from) / Double(bins)
    }

    /// The current shift (space − mark); at least 20 Hz so that the search cannot degenerate.
    var shiftHz: Double { max(20, abs(space - mark)) }

    /// The mark of the strongest RTTY signal: the tone pair `f`, `f + shift` with the highest sum of levels.
    /// nil = an empty spectrum, or nothing above the noise.
    nonisolated public static func strongestMark(in line: [Float], from: Double, to: Double, shiftHz: Double,
                                     threshold: Float = signalThreshold) -> Double? {
        guard line.count > 1, to > from, shiftHz > 0 else { return nil }
        let hzPerBin = (to - from) / Double(line.count)
        let shiftBins = Int((shiftHz / hzPerBin).rounded())
        guard shiftBins > 0, shiftBins < line.count else { return nil }
        var best = (score: Float(-1), index: 0)
        for i in 0..<(line.count - shiftBins) {
            let s = line[i] + line[i + shiftBins]
            if s > best.score { best = (s, i) }
        }
        guard best.score > 2 * threshold else { return nil }
        return (binHz(best.index, bins: line.count, from: from, to: to) * 10).rounded() / 10
    }

    /// The strongest tone that is not the signal being received: the highest bin outside a ±max(shift/2, 50 Hz)
    /// window around mark and space. nil = nothing above the noise outside the received signal.
    nonisolated public static func strongestInterference(in line: [Float], from: Double, to: Double, mark: Double, space: Double,
                                            threshold: Float = signalThreshold) -> Double? {
        guard line.count > 1, to > from else { return nil }
        let guardHz = max(abs(space - mark) / 2, 50)
        var best = (level: Float(-1), index: -1)
        for i in 0..<line.count {
            let hz = binHz(i, bins: line.count, from: from, to: to)
            if abs(hz - mark) < guardHz || abs(hz - space) < guardHz { continue }
            if line[i] > best.level { best = (line[i], i) }
        }
        guard best.index >= 0, best.level > threshold else { return nil }
        return (binHz(best.index, bins: line.count, from: from, to: to) * 10).rounded() / 10
    }

    public func strongestMarkHz() -> Double? {
        Self.strongestMark(in: waterfall.spectrumLine, from: waterfallFromHz, to: waterfallToHz, shiftHz: shiftHz)
    }

    public func strongestInterferenceHz() -> Double? {
        Self.strongestInterference(in: waterfall.spectrumLine, from: waterfallFromHz, to: waterfallToHz,
                                   mark: mark, space: space)
    }

    /// The last word in the receive window that looks like a callsign (the keyboard equivalent of clicking it).
    /// Own callsign is skipped - it is the station calling us that we want in the QSO window.
    nonisolated public static func lastReceivedCall(in text: String, own: String = "") -> String? {
        let ownBase = QSORecord.baseCall(own.uppercased())
        let words = text.uppercased().split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        for w in words.reversed() {
            let word = String(w).trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "/")))
            guard WordClassifier.classify(word) == .call else { continue }
            if !ownBase.isEmpty, QSORecord.baseCall(word) == ownBase { continue }
            return word
        }
        return nil
    }

    // MARK: Commands

    /// ⌥⌘S: point the mark at the strongest signal in the spectrum (the keyboard route for clicking the waterfall).
    public func tuneToStrongestSignal() async {
        guard let hz = strongestMarkHz() else {
            note(L("Ve spektru není signál, na který by šlo naladit."))
            return
        }
        await tune(toMarkHz: hz)
        note(L("Naladěno na %.0f Hz (nejsilnější signál).", hz))
    }

    /// ⌥⌘N: a notch on the strongest tone outside the received signal (the keyboard route for the right button in the spectrum).
    public func notchStrongestInterference() async {
        guard let hz = strongestInterferenceHz() else {
            note(L("Mimo přijímaný signál není ve spektru co potlačit."))
            return
        }
        await notchClick(hz: hz)
        note(L("Zářez na %.0f Hz.", hz))
    }

    /// ⌥⌘C: the last received callsign into the QSO window (the keyboard route for clicking a word in the receive window).
    public func insertLastReceivedCall() async {
        guard let call = Self.lastReceivedCall(in: rxPlainText, own: settings.station.call) else {
            note(L("V příjmu není značka, kterou by šlo vložit do QSO."))
            return
        }
        await insertWord(call)
    }
}
