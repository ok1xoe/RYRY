import Testing
import Settings
import AppCore
@testable import AppUI

private func layout(_ enabled: Bool, _ f: ContestFormat = .serial, exchange: String = "") -> [QSOLayout.Row] {
    var c = ContestSettings(); c.enabled = enabled; c.format = f; c.exchange = exchange
    return QSOLayout.rows(for: c)
}

@Test func qsoFieldsWithoutContest() {
    #expect(layout(false) == [.single("call", "Call"), .country, .single("name", "Name"), .single("qth", "QTH"),
                              .single("locator", "Locator"), .pair("rstSent", "RST s", "rstRcvd", "RST r"), .single("notes", "Notes")])
    #expect(!QSOLayout.showsQTC(ContestSettings()))
}

@Test func qsoFieldsPerContestFormat() {
    let base: [QSOLayout.Row] = [.single("call", "Call"), .country, .pair("rstSent", "RST s", "rstRcvd", "RST r")]
    #expect(layout(true, .serial) == base + [.pair("serialSent", "Nr s", "serialRcvd", "Nr r"), .single("notes", "Notes")])
    #expect(layout(true, .serial, exchange: "DL") == base + [.pair("exchangeSent", "Exch s", "exchangeRcvd", "Exch r"), .single("notes", "Notes")])
    #expect(layout(true, .cqrj) == base + [.pair("exchangeSent", "Zóna/QTH s", "exchangeRcvd", "Zóna/QTH r"), .single("notes", "Notes")])
    #expect(layout(true, .bartg) == base + [.pair("serialSent", "Nr s", "serialRcvd", "Nr r"),
                                            .pair("exchangeSent", "Čas s", "exchangeRcvd", "Čas r"), .single("notes", "Notes")])
    #expect(layout(true, .ped) == base + [.single("notes", "Notes")])
    #expect(layout(true, .wae) == base + [.pair("serialSent", "Nr s", "serialRcvd", "Nr r"), .single("notes", "Notes")])
    var c = ContestSettings(); c.enabled = true; c.format = .wae
    #expect(QSOLayout.showsQTC(c))
    c.enabled = false
    #expect(!QSOLayout.showsQTC(c))
}

@Test func arrlRoundupHasStateField() {
    let c = ContestSettings.preset(.arrlRoundup, year: 2027)
    #expect(QSOLayout.rows(for: c) == [.single("call", "Call"), .country, .pair("rstSent", "RST s", "rstRcvd", "RST r"),
                                       .pair("serialSent", "Nr s", "serialRcvd", "Nr r"), .single("exchangeRcvd", "Stát/prov. r"),
                                       .single("notes", "Notes")])
}

@Test func zoneFormatLayoutAndClicks() {
    #expect(layout(true, .zone) == [.single("call", "Call"), .country, .pair("rstSent", "RST s", "rstRcvd", "RST r"),
                                    .pair("exchangeSent", "Zóna s", "exchangeRcvd", "Zóna r"), .single("notes", "Notes")])
    var q = QSOFields(); q.call = "W1AW"
    func f(_ w: String) -> [String] { WordClassifier.contestUpdate(w, format: .zone, serialMode: false, current: q).map { "\($0.0)=\($0.1)" } }
    #expect(f("14") == ["exchangeRcvd=14"])
    #expect(f("59914") == ["exchangeRcvd=14"])
    #expect(f("599") == ["rstRcvd=599"])
    #expect(f("TEST") == [])
    #expect(f("41") == [])                                                // the CQ zone is 1–40
}
