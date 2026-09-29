// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
@testable import QSOLog

private func tmp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("imp-\(UUID())") }

private let adi = """
Export z MMTTY
<ADIF_VER:5>3.1.0 <EOH>
<CALL:6>DL1ABC <QSO_DATE:8>20251012 <TIME_ON:4>1203 <BAND:3>20m <MODE:4>RTTY <FREQ:9>14.085000
<RST_SENT:3>599 <RST_RCVD:3>579 <NAME:4>Hans <QTH:6>Berlin <SRX:3>015 <STX:1>7 <COMMENT:5>tnx73 <EOR>
<call:4>W1AW <qso_date:8>20251012 <time_on:6>130512 <mode:3>SSB <band:3>40m <eor>
<CALL:5>OK1XX <MODE:4>RTTY <EOR>
"""

// ADIF → záznamy: čas, frekvence, RST, jméno, čísla; bez data = neplatný záznam (přeskočí se)
@Test func adifImportRecords() throws {
    let r = ADIF.importRecords(adi)
    #expect(r.records.count == 2 && r.skipped == 1)
    let a = r.records[0]
    #expect(a.call == "DL1ABC" && a.mode == "RTTY" && a.frequency == 14_085_000)
    #expect(a.timeOn == ISO8601DateFormatter().date(from: "2025-10-12T12:03:00Z"))
    #expect(a.rstSent == "599" && a.rstRcvd == "579" && a.name == "Hans" && a.qth == "Berlin")
    #expect(a.serialRcvd == 15 && a.serialSent == 7 && a.comment == "tnx73")
    let b = r.records[1]
    #expect(b.call == "W1AW" && b.mode == "SSB" && b.frequency == 7_000_000)   // jen pásmo → dolní okraj
    #expect(b.timeOn == ISO8601DateFormatter().date(from: "2025-10-12T13:05:12Z"))
}

// Import do logu: duplicity (stejná značka, pásmo, mód, čas ±1 min) se přeskočí
@Test func logImportSkipsDuplicates() async throws {
    let s = try QSOLogStore(directory: tmp())
    let first = try await s.importRecords(ADIF.importRecords(adi).records)
    var n = await s.records.count
    #expect(first.added == 2 && first.duplicates == 0 && n == 2)
    let again = try await s.importRecords(ADIF.importRecords(adi).records)
    n = await s.records.count
    #expect(again.added == 0 && again.duplicates == 2 && n == 2)
    let ok = await s.isADIFConsistent()
    #expect(ok)
    // vlastní export se naimportuje zpět beze ztrát (APP_MMTTY4MAC_ID = stejné spojení)
    let t = try String(contentsOf: await s.adifURL, encoding: .utf8)
    let s2 = try QSOLogStore(directory: tmp())
    let back = try await s2.importRecords(ADIF.importRecords(t).records)
    let ids2 = await s2.records.map(\.id), ids1 = await s.records.map(\.id)
    #expect(back.added == 2 && ids2 == ids1)
}
