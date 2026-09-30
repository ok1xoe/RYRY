// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import AppCore
import Localization
import Settings

/// "Enter Sends Message" (N1MM Logger+): what Enter sends in the QSO window, depending on the Run / S&P mode and the state of the QSO.
/// Pure logic with no side effects; the execution lives in `AppModel.esmEnter()`.
public enum ESM {
    public enum Step: Equatable, Sendable {
        case none            // nothing (outside a contest, during TX, S&P without a call)
        case cq              // Run: empty call
        case exchange        // Run: call + exchange
        case tu              // Run: thanks and log the QSO
        case myCall          // S&P: my own call
        case exchangeAndLog  // S&P: exchange and log the QSO
        case agn             // only part of the exchange received → AGN?
    }

    /// What has already been sent in this QSO (valid only for the call `call`; a different call = a new QSO).
    public struct Progress: Equatable, Sendable {
        public var call = ""
        public var exchangeSent = false
        public var myCallSent = false
        public init(call: String = "", exchangeSent: Bool = false, myCallSent: Bool = false) {
            self.call = call; self.exchangeSent = exchangeSent; self.myCallSent = myCallSent
        }
        /// The progress for the given call (a different call → start over).
        public func forCall(_ call: String) -> Progress { self.call == call ? self : Progress(call: call) }
    }

    public enum Received: Equatable, Sendable { case none, partial, complete }

    /// The received exchange fields, following the QSO window layout (without RST, which is pre-filled with 599): the received fields of the pairs
    /// as well as the standalone received exchange rows (ARRL RU "State/prov. r").
    public static func receivedFields(_ c: ContestSettings) -> [String] {
        QSOLayout.rows(for: c).compactMap { row in
            switch row {
            case .pair(_, _, let rcvd, _) where rcvd != "rstRcvd": return rcvd
            case .single(let f, _) where f.hasSuffix("Rcvd"): return f
            default: return nil
            }
        }
    }

    /// Groups of received fields: a group is complete once at least one of its fields is filled in.
    /// ARRL RTTY Roundup: W/VE send a state/province, everyone else a number → number OR state.
    public static func receivedGroups(_ c: ContestSettings) -> [[String]] {
        let f = receivedFields(c)
        if c.isRoundupStateExchange, Set(f) == ["serialRcvd", "exchangeRcvd"] { return [f] }
        return f.map { [$0] }
    }

    public static func received(_ q: QSOFields, _ c: ContestSettings) -> Received {
        let groups = receivedGroups(c)
        func has(_ f: String) -> Bool { !(q.value(f) ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        let filled = groups.filter { $0.contains(where: has) }.count
        if filled == groups.count { return .complete }        // also a format without an exchange (PED)
        return filled == 0 ? .none : .partial
    }

    /// The step for Enter. Nothing outside a contest and during transmit.
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

    /// The macro (index 0…15) for the step, according to the settings.
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

    /// The macro contains %l (it logs the QSO itself) - the same rules as MacroEngine: %% is not a variable, %E ends the text.
    public static func macroLogs(_ text: String) -> Bool {
        var it = text.makeIterator()
        while let ch = it.next() {
            guard ch == "%", let code = it.next() else { continue }
            if code == "E" { return false }
            if code == "l" { return true }
        }
        return false
    }

    /// A step that should log the QSO where the macro does not do it itself.
    public static func needsExplicitLog(_ step: Step, macroText: String) -> Bool {
        (step == .tu || step == .exchangeAndLog) && !macroLogs(macroText)
    }

    /// The field the focus moves to after the step: after the exchange/call the first empty received exchange field, otherwise Call.
    public static func nextFocus(after step: Step, qso: QSOFields, contest: ContestSettings) -> String {
        switch step {
        case .exchange, .myCall, .agn:
            let f = receivedFields(contest)
            return f.first { (qso.value($0) ?? "").trimmingCharacters(in: .whitespaces).isEmpty } ?? f.first ?? "call"
        case .none, .cq, .tu, .exchangeAndLog:
            return "call"
        }
    }

    /// Description of the step for the hint in the QSO panel ("→ Exchange").
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
