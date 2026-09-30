// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import Foundation
import Localization
import QSOLog
import Settings
import Spots

/// Highlighting of callsigns in the receive window and alerts (my own call, watched calls, needed entities).
extension AppModel {
    /// My own call as a base callsign (uppercase; empty = not set).
    public var myBaseCall: String {
        let c = settings.station.call.trimmingCharacters(in: .whitespaces)
        return c.isEmpty ? "" : QSORecord.baseCall(c)
    }

    // currentBand (the rig's band, otherwise the manual frequency) lives in AppModel.swift - it is shared by the multipliers and the alerts

    func countryRef(_ call: String) -> CountryRef? {
        app?.country(for: call).map { CountryRef(key: $0.primaryPrefix, name: $0.name) }
    }

    var contestSinceForIndex: Date? { settings.contest.enabled ? settings.contest.effectiveStart : nil }

    /// Rebuilds the log index (startup, switching logs, a change to the records).
    func rebuildLogIndex() {
        logIndexSince = contestSinceForIndex
        logIndex = LogIndex(records: logRecords, contestSince: logIndexSince,
                            dupePerMode: DupeCheck.perMode(preset: settings.contest.selectedPreset), country: { [app] in
            app?.country(for: $0).map { CountryRef(key: $0.primaryPrefix, name: $0.name) }
        })
        spotLogIndex = SpotLogIndex(logRecords)
        highlightBand = currentBand
        highlightVersion &+= 1
    }

    func addToLogIndex(_ r: QSORecord) {
        logIndex.add(r, contestSince: logIndexSince, country: countryRef)
        spotLogIndex.add(r)
        highlightVersion &+= 1
    }

    /// After a frequency/rig change: if the band changed, the styling of dupes and new entities has to be recomputed.
    func updateHighlightBand() {
        let b = currentBand
        if b != highlightBand { highlightBand = b; highlightVersion &+= 1 }
    }

    /// The style of a callsign for the receive window (nil = no style change).
    public func callStyle(for word: String) -> CallStyle? {
        CallHighlight.style(word: word, myBase: myBaseCall, band: currentBand, mode: "RTTY",
                            contest: settings.contest.enabled, index: logIndex)
    }

    // MARK: Alerts

    /// The reasons why a spot is needed (both for marking it in SpotsWindow and for the alert).
    public func neededReasons(for spot: Spot) -> [NeededCheck.Reason] {
        NeededCheck.check(call: spot.call, band: spot.band, country: countryRef(spot.call),
                          settings: settings.alerts, index: logIndex)
    }

    static func reasonText(_ r: NeededCheck.Reason) -> String {
        switch r {
        case .watched: return L("hlídaná značka")
        case .newCountry(let c): return L("nová země %@", c)
        case .newCountryBand(let c, let b): return L("nová země %@ na pásmu %@", c, b)
        }
    }

    /// The reasons as text for the tooltip/status bar.
    public static func neededText(_ rs: [NeededCheck.Reason]) -> String { rs.map(reasonText).joined(separator: ", ") }

    private var neededActive: Bool {
        let a = settings.alerts
        return a.newCountryAny || a.newCountryBand || !a.watchCalls.isEmpty
    }

    /// A new spot: alerts when it is needed (at most once per spot). A spot hidden by the display filter
    /// (unchecked band or mode group) raises no alert - only what the Spots table shows is alerted on.
    public func checkSpotNeeded(_ spot: Spot) {
        guard neededActive, settings.spots.filter.matches(spot) else { return }
        let reasons = neededReasons(for: spot)
        guard !reasons.isEmpty else { return }
        emitNeeded(call: spot.call, band: spot.band, reasons: reasons, source: L("spot"), interval: 3600, batch: true)
    }

    private func emitNeeded(call: String, band: String?, reasons: [NeededCheck.Reason], source: String, interval: TimeInterval,
                            batch: Bool = false) {
        let now = alertClock()
        guard alertThrottle.allow(NeededCheck.dedupeKey(call: call, band: band) + "|" + source, now: now, interval: interval) else { return }
        let text = Self.neededText(reasons)
        if batch { queueNeededSummary(call: call, text: text, source: source, now: now) }
        else { note(L("Potřebné (%@): %@ – %@", source, call, text)) }
        // sound and notification at most once every 3 s (a burst of spots arrives after connecting to the cluster)
        guard alertThrottle.allow("needed-sound", now: now, interval: 3) else { return }
        if settings.alerts.neededSound { alertSink.playSound() }
        if settings.alerts.neededNotification { alertSink.notify(title: L("Potřebná stanice: %@", call), body: text) }
    }

    /// Interval of the "Needed: N (…)" summary line in the status bar.
    static let neededSummaryInterval: TimeInterval = 5

    /// Spots: the first needed one goes out immediately as a line, further ones within `neededSummaryInterval` go into a single summary.
    private func queueNeededSummary(call: String, text: String, source: String, now: Date) {
        if neededPending.isEmpty, neededLastLine.map({ now.timeIntervalSince($0) >= Self.neededSummaryInterval }) ?? true {
            note(L("Potřebné (%@): %@ – %@", source, call, text))
            neededLastLine = now
            return
        }
        neededPending.append("\(call) – \(text)")
        guard neededFlushTask == nil else { return }
        neededFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.neededSummaryInterval))
            self?.flushNeededSummary()
        }
    }

    /// Emits the pending summary (at most 5 calls by name).
    func flushNeededSummary() {
        neededFlushTask?.cancel(); neededFlushTask = nil
        guard !neededPending.isEmpty else { return }
        let n = neededPending.count
        let list = neededPending.prefix(5).joined(separator: "; ") + (n > 5 ? "; …" : "")
        note(L("Potřebné: %ld (%@)", n, list))
        neededPending = []
        neededLastLine = alertClock()
    }

    /// Received text: completed words are checked against my own call and the needed calls. Echo is skipped.
    ///
    /// RTTY noise produces random "callsigns": a new entity is only reported from the receive side for a call known to Super Check Partial
    /// or to the log, one that follows DE/CQ, or one that arrived at least twice within 10 minutes. Watched calls are reported immediately.
    func scanRxForAlerts(_ s: String, echo: Bool) {
        let words = rxScanner.feed(s, echo: echo)
        if echo { rxPrevWord = "" }
        guard !words.isEmpty else { return }
        let my = myBaseCall
        let now = alertClock()
        for w in words {
            let prev = rxPrevWord
            rxPrevWord = WordClassifier.callCandidate(w) ?? ""
            guard let call = WordClassifier.callCandidate(w) else { continue }
            let base = QSORecord.baseCall(call)
            if !my.isEmpty, base.count >= 3, base == my {
                alertMyCall(call)
            } else if neededActive, WordClassifier.classify(call) == .call {
                let seen = rxCallSightings.record(base, now: now)
                let reasons = NeededCheck.check(call: call, band: currentBand, country: countryRef(call),
                                                settings: settings.alerts, index: logIndex)
                guard !reasons.isEmpty else { continue }
                let confirmed = reasons.contains(.watched) || prev == "DE" || prev == "CQ" || seen >= 2
                    || logIndex.worked(call) || superCheck.contains(call) || superCheck.contains(base)
                if confirmed { emitNeeded(call: call, band: currentBand, reasons: reasons, source: L("příjem"), interval: 600) }
            }
        }
    }

    private func alertMyCall(_ call: String) {
        let a = settings.alerts
        guard a.myCallSound || a.myCallNotification else { return }
        guard alertThrottle.allow("my-call", now: alertClock(), interval: 20) else { return }
        if a.myCallSound { alertSink.playSound() }
        if a.myCallNotification { alertSink.notify(title: L("Někdo vás volá"), body: L("V příjmu je vaše značka %@.", call)) }
    }
}
