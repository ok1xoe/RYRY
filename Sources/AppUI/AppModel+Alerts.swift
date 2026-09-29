// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import Foundation
import Localization
import QSOLog
import Settings
import Spots

/// Zvýrazňování značek v příjmu a upozornění (moje značka, hlídané značky, potřebné země).
extension AppModel {
    /// Moje značka jako základní značka (velkými písmeny; prázdné = nenastaveno).
    public var myBaseCall: String {
        let c = settings.station.call.trimmingCharacters(in: .whitespaces)
        return c.isEmpty ? "" : QSORecord.baseCall(c)
    }

    /// Pásmo pro duplicity a „nová země na pásmu“: frekvence rigu, jinak ručně zadaná (jako `AppController.currentFrequency`).
    public var currentBand: String? {
        if let r = rig, r.online, let f = r.frequency { return Bands.band(forHz: f) }
        return Bands.band(forHz: qso.frequency)
    }

    func countryRef(_ call: String) -> CountryRef? {
        app?.country(for: call).map { CountryRef(key: $0.primaryPrefix, name: $0.name) }
    }

    var contestSinceForIndex: Date? { settings.contest.enabled ? settings.contest.effectiveStart : nil }

    /// Přestaví index logu (start, přepnutí logu, změna záznamů).
    func rebuildLogIndex() {
        logIndex = LogIndex(records: logRecords, contestSince: contestSinceForIndex, country: { [app] in
            app?.country(for: $0).map { CountryRef(key: $0.primaryPrefix, name: $0.name) }
        })
        highlightBand = currentBand
        highlightVersion &+= 1
    }

    func addToLogIndex(_ r: QSORecord) {
        logIndex.add(r, contestSince: contestSinceForIndex, country: countryRef)
        highlightVersion &+= 1
    }

    /// Po změně frekvence/rigu: pokud se změnilo pásmo, styl duplicit a nových zemí se musí přepočítat.
    func updateHighlightBand() {
        let b = currentBand
        if b != highlightBand { highlightBand = b; highlightVersion &+= 1 }
    }

    /// Styl značky pro okno příjmu (nil = beze změny stylu).
    public func callStyle(for word: String) -> CallStyle? {
        CallHighlight.style(word: word, myBase: myBaseCall, band: currentBand, mode: "RTTY",
                            contest: settings.contest.enabled, index: logIndex)
    }

    // MARK: Upozornění

    /// Důvody, proč je spot potřebný (pro označení ve SpotsWindow i upozornění).
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

    /// Text důvodů pro tooltip/stavový řádek.
    public static func neededText(_ rs: [NeededCheck.Reason]) -> String { rs.map(reasonText).joined(separator: ", ") }

    private var neededActive: Bool {
        let a = settings.alerts
        return a.newCountryAny || a.newCountryBand || !a.watchCalls.isEmpty
    }

    /// Nový spot: když je potřebný, upozorní (max. 1× za spot).
    public func checkSpotNeeded(_ spot: Spot) {
        guard neededActive else { return }
        let reasons = neededReasons(for: spot)
        guard !reasons.isEmpty else { return }
        emitNeeded(call: spot.call, band: spot.band, reasons: reasons, source: L("spot"), interval: 3600)
    }

    private func emitNeeded(call: String, band: String?, reasons: [NeededCheck.Reason], source: String, interval: TimeInterval) {
        let now = alertClock()
        guard alertThrottle.allow(NeededCheck.dedupeKey(call: call, band: band) + "|" + source, now: now, interval: interval) else { return }
        let text = Self.neededText(reasons)
        note(L("Potřebné (%@): %@ – %@", source, call, text))
        // zvuk a oznámení nejvýš jednou za 3 s (po připojení ke clusteru přijde dávka spotů)
        guard alertThrottle.allow("needed-sound", now: now, interval: 3) else { return }
        if settings.alerts.neededSound { alertSink.playSound() }
        if settings.alerts.neededNotification { alertSink.notify(title: L("Potřebná stanice: %@", call), body: text) }
    }

    /// Přijatý text: dokončená slova se zkontrolují na moji značku a potřebné značky. Echo se přeskakuje.
    func scanRxForAlerts(_ s: String, echo: Bool) {
        let words = rxScanner.feed(s, echo: echo)
        guard !words.isEmpty else { return }
        let my = myBaseCall
        for w in words {
            guard let call = WordClassifier.callCandidate(w) else { continue }
            let base = QSORecord.baseCall(call)
            if !my.isEmpty, base.count >= 3, base == my {
                alertMyCall(call)
            } else if neededActive, WordClassifier.classify(call) == .call {
                let reasons = NeededCheck.check(call: call, band: currentBand, country: countryRef(call),
                                                settings: settings.alerts, index: logIndex)
                if !reasons.isEmpty { emitNeeded(call: call, band: currentBand, reasons: reasons, source: L("příjem"), interval: 600) }
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
