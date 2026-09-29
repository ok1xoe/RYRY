// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import Localization
import Settings

/// „Enter Sends Message“ (N1MM Logger+): co pošle Enter v QSO okně podle režimu Run / S&P a stavu spojení.
/// Čistá logika bez vedlejších účinků; provedení je v `AppModel.esmEnter()`.
public enum ESM {
    public enum Step: Equatable, Sendable {
        case none            // nic (mimo závod, během TX, S&P bez značky)
        case cq              // Run: prázdná značka
        case exchange        // Run: značka + výměna
        case tu              // Run: poděkování a zalogování
        case myCall          // S&P: moje značka
        case exchangeAndLog  // S&P: výměna a zalogování
        case agn             // jen část výměny přijata → AGN?
    }

    /// Co už v tomto spojení odešlo (platí jen pro značku `call`; jiná značka = nové spojení).
    public struct Progress: Equatable, Sendable {
        public var call = ""
        public var exchangeSent = false
        public var myCallSent = false
        public init(call: String = "", exchangeSent: Bool = false, myCallSent: Bool = false) {
            self.call = call; self.exchangeSent = exchangeSent; self.myCallSent = myCallSent
        }
        /// Průběh pro danou značku (jiná značka → od začátku).
        public func forCall(_ call: String) -> Progress { self.call == call ? self : Progress(call: call) }
    }

    public enum Received: Equatable, Sendable { case none, partial, complete }

    /// Pole přijaté výměny podle rozložení QSO okna (bez RST, které je předvyplněné 599).
    public static func receivedFields(_ c: ContestSettings) -> [String] {
        QSOLayout.rows(for: c).compactMap { row in
            if case .pair(_, _, let rcvd, _) = row, rcvd != "rstRcvd" { return rcvd }
            return nil
        }
    }

    public static func received(_ q: QSOFields, _ c: ContestSettings) -> Received {
        let fields = receivedFields(c)
        let filled = fields.filter { !(q.value($0) ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.count
        if filled == fields.count { return .complete }        // i formát bez výměny (PED)
        return filled == 0 ? .none : .partial
    }

    /// Krok pro Enter. Mimo závod a během vysílání nic.
    public static func step(mode: ESMMode, contest: ContestSettings, qso: QSOFields, progress: Progress, transmitting: Bool) -> Step {
        guard contest.enabled, !transmitting else { return .none }
        let call = qso.call.trimmingCharacters(in: .whitespaces)
        let p = progress.forCall(qso.call)
        let rcv = received(qso, contest)
        switch mode {
        case .run:
            if call.isEmpty { return .cq }
            if !p.exchangeSent { return .exchange }
            switch rcv { case .complete: return .tu; case .partial: return .agn; case .none: return .exchange }
        case .sp:
            if call.isEmpty { return .none }
            if !p.myCallSent { return .myCall }
            switch rcv { case .complete: return .exchangeAndLog; case .partial: return .agn; case .none: return .myCall }
        }
    }

    /// Makro (index 0…15) pro krok podle nastavení.
    public static func macro(for step: Step, _ e: ESMSettings) -> Int? {
        switch step {
        case .none: nil
        case .cq: e.runCQ
        case .exchange: e.runExchange
        case .tu: e.runTU
        case .myCall: e.spMyCall
        case .exchangeAndLog: e.spExchange
        case .agn: e.agn
        }
    }

    /// Makro obsahuje %l (zaloguje samo) – stejná pravidla jako MacroEngine: %% není proměnná, %E ukončí text.
    public static func macroLogs(_ text: String) -> Bool {
        var it = text.makeIterator()
        while let ch = it.next() {
            guard ch == "%", let code = it.next() else { continue }
            if code == "E" { return false }
            if code == "l" { return true }
        }
        return false
    }

    /// Krok, který má spojení zalogovat, a makro to neudělá samo.
    public static func needsExplicitLog(_ step: Step, macroText: String) -> Bool {
        (step == .tu || step == .exchangeAndLog) && !macroLogs(macroText)
    }

    /// Pole, kam se po kroku přesune fokus: po výměně/značce první prázdné pole přijaté výměny, jinak Call.
    public static func nextFocus(after step: Step, qso: QSOFields, contest: ContestSettings) -> String {
        switch step {
        case .exchange, .myCall, .agn:
            let f = receivedFields(contest)
            return f.first { (qso.value($0) ?? "").trimmingCharacters(in: .whitespaces).isEmpty } ?? f.first ?? "call"
        case .none, .cq, .tu, .exchangeAndLog:
            return "call"
        }
    }

    /// Popis kroku pro nápovědu v QSO panelu („→ Výměna“).
    public static func title(_ step: Step) -> String {
        switch step {
        case .none: "—"
        case .cq: "CQ"
        case .exchange: L("Výměna")
        case .tu: "TU + Log"
        case .myCall: L("Moje značka")
        case .exchangeAndLog: L("Výměna + Log")
        case .agn: "AGN?"
        }
    }
}
