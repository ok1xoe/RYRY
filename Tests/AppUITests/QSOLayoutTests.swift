import Testing
import Settings
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
