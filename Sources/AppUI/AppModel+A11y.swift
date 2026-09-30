// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Localization
import ModemKit

/// Accessibility: spoken announcements of events and reading the drawn views / the received text on demand.
/// The views only read `tuningSummary`, `scopeSummary(…)`; the commands from the menu call `speak…()`.
extension AppModel {
    // MARK: Announcements (automatic, rate-limited)

    /// An event the operator should learn about without watching the screen (my own call, a dupe, a new multiplier,
    /// a needed station). It goes through `AnnouncementLimiter`, so speech never floods, and it can be turned off
    /// in Settings → Alerts. `key` identifies the event (the same event is not repeated straight away).
    func announce(_ text: String, key: String) {
        guard settings.alerts.speakAlerts, !text.isEmpty else { return }
        guard let dropped = announcementLimiter.allow(key: key, now: alertClock()) else { return }
        lastAnnouncement = dropped > 0 ? L("%@ (%ld hlášení přeskočeno)", text, dropped) : text
        announcer.announce(lastAnnouncement, interrupts: false)
    }

    /// Text the operator explicitly asked for (a shortcut): it is not rate-limited and it interrupts what is being read.
    public func speak(_ text: String) {
        lastAnnouncement = text
        announcer.announce(text, interrupts: true)
    }

    /// A needed station (a watched call, a new entity) from a spot or from the received text.
    func announceNeeded(call: String, band: String?, text: String) {
        announce(L("Potřebná stanice %@, %@", SpokenSummary.spokenCall(call), text),
                 key: NeededCheck.dedupeKey(call: call, band: band))
    }

    /// DUPE / NEW MULT from the QSO panel. A callsign is typed character by character, so it is spoken only when
    /// the state actually changes - not on every keystroke.
    func announceQSOState() {
        let call = qso.call.uppercased()
        if isDupe, !call.isEmpty {
            if call != spokenDupeCall {
                spokenDupeCall = call
                announce(L("Duplicita: %@", SpokenSummary.spokenCall(call)), key: "dupe|" + call)
            }
        } else {
            spokenDupeCall = ""
        }
        let mult = newMultiplier.isEmpty ? "" : newMultiplier.text
        if !mult.isEmpty, !call.isEmpty {
            if mult != spokenMultText {
                spokenMultText = mult
                announce(L("Nový násobič: %@", mult), key: "mult|" + call + "|" + mult)
            }
        } else {
            spokenMultText = ""
        }
    }

    // MARK: Spoken summaries of the drawn views

    /// The tuning summary (the value of the spectrum and the waterfall element, and the ⌥⌘T command).
    public var tuningSummary: String {
        SpokenSummary.tuning(mark: mark, space: space, afc: param("afc") == .bool(true), level: signalLevel,
                             squelchOpen: squelchOpen, notches: notchMarkers.count)
    }

    /// The summary of the demodulator scope for the chosen window (the value of the Scope window element).
    /// `source` = the displayed name of the source (the window knows its own translation of the names).
    public func scopeSummary(source: String, width: Int, offset: Double) -> String {
        SpokenSummary.scope(source: source, scope: demodScope, sourceIndex: scopeSource,
                            frozen: scopeFrozen, width: width, offset: offset)
    }

    // MARK: Reading the received text on demand

    /// Reads the last received line. Repeated use of `speakPreviousRxLine()` steps further back through the snapshot,
    /// so text arriving in the meantime does not shift the lines.
    public func speakLastRxLine() {
        rxReadLines = RxLineReader.recentLines(rxPlainText)
        rxReadBack = 0
        speakRxLine()
    }

    /// Reads the line before the one last read (the first use without "read the last line" reads the last but one).
    public func speakPreviousRxLine() {
        if rxReadLines.isEmpty { rxReadLines = RxLineReader.recentLines(rxPlainText) }
        guard !rxReadLines.isEmpty else { rxReadBack = 0; speak(L("Příjem je prázdný.")); return }
        rxReadBack += 1
        speakRxLine()
    }

    private func speakRxLine() {
        if let line = RxLineReader.line(rxReadLines, back: rxReadBack) {
            speak(line)
        } else if rxReadBack <= 0 {
            speak(L("Příjem je prázdný."))
        } else {
            rxReadBack -= 1
            speak(L("Dřívější řádek už není."))
        }
    }

    /// The tuning summary on demand (the shortcut) - the same text the spectrum reports.
    public func speakTuning() { speak(tuningSummary) }
}
