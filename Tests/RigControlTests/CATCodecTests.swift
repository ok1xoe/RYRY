// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Testing
@testable import RigControl

// CI-V: rámec FE FE <rádio> E0 <příkaz> … FD, frekvence 5 bajtů BCD od nejnižšího řádu
@Test func civFrames() {
    #expect(CIV.frame(to: 0x94, cmd: 0x03) == [0xFE, 0xFE, 0x94, 0xE0, 0x03, 0xFD])
    #expect(CIV.bcd(14_085_123) == [0x23, 0x51, 0x08, 0x14, 0x00])
    #expect(CIV.fromBCD([0x23, 0x51, 0x08, 0x14, 0x00]) == 14_085_123)
    #expect(CIV.setFrequency(14_085_000, to: 0x94) == [0xFE, 0xFE, 0x94, 0xE0, 0x05, 0x00, 0x50, 0x08, 0x14, 0x00, 0xFD])
    #expect(CIV.ptt(true, to: 0xA4) == [0xFE, 0xFE, 0xA4, 0xE0, 0x1C, 0x00, 0x01, 0xFD])
}

// Rozbor proudu bajtů: echo vlastních rámců (od E0) a vysílání do všech (00) se přeskočí
@Test func civParseStream() {
    let echo = CIV.frame(to: 0x94, cmd: 0x03)
    let answer: [UInt8] = [0xFE, 0xFE, 0xE0, 0x94, 0x03, 0x00, 0x50, 0x08, 0x14, 0x00, 0xFD]
    let broadcast: [UInt8] = [0xFE, 0xFE, 0x00, 0x94, 0x00, 0x00, 0x60, 0x08, 0x14, 0x00, 0xFD]
    var p = CIV.Parser()
    let frames = p.feed(echo + broadcast + [0x00] + answer)
    #expect(frames.count == 1)
    #expect(frames[0].cmd == 0x03 && frames[0].from == 0x94)
    #expect(CIV.fromBCD(Array(frames[0].data)) == 14_085_000)
    var q = CIV.Parser()
    #expect(q.feed(Array(answer.prefix(6))).isEmpty && q.feed(Array(answer.dropFirst(6))).count == 1)   // po částech
}

@Test func civModes() {
    #expect(CIV.modeName(0x04) == "RTTY" && CIV.modeName(0x08) == "RTTYR" && CIV.modeName(0x01) == "USB")
    #expect(CIV.modeCode("RTTY") == 0x04 && CIV.modeCode("PKTUSB") == 0x01 && CIV.modeCode("XYZ") == nil)
}

// Textový CAT: Kenwood/Elecraft 11 číslic, Yaesu 9 číslic
@Test func textCATCommands() {
    #expect(TextCAT.setFrequency(14_085_000, dialect: .kenwood) == "FA00014085000;")
    #expect(TextCAT.setFrequency(14_085_000, dialect: .elecraft) == "FA00014085000;")
    #expect(TextCAT.setFrequency(14_085_000, dialect: .yaesu) == "FA014085000;")
    #expect(TextCAT.parseFrequency("FA00014085000;") == 14_085_000)
    #expect(TextCAT.parseFrequency("FA014085000;") == 14_085_000)
    #expect(TextCAT.parseFrequency("?;") == nil)
    #expect(TextCAT.ptt(true, dialect: .kenwood) == "TX1;" && TextCAT.ptt(false, dialect: .kenwood) == "RX;")
    #expect(TextCAT.ptt(true, dialect: .elecraft) == "TX;" && TextCAT.ptt(false, dialect: .elecraft) == "RX;")
    #expect(TextCAT.ptt(true, dialect: .yaesu) == "TX1;" && TextCAT.ptt(false, dialect: .yaesu) == "TX0;")
    #expect(TextCAT.modeQuery(.yaesu) == "MD0;" && TextCAT.modeQuery(.kenwood) == "MD;")
    #expect(TextCAT.parseMode("MD6;", dialect: .kenwood) == "RTTY" && TextCAT.parseMode("MD9;", dialect: .kenwood) == "RTTYR")
    #expect(TextCAT.parseMode("MD0C;", dialect: .yaesu) == "PKTUSB" && TextCAT.parseMode("MD06;", dialect: .yaesu) == "RTTY")
    #expect(TextCAT.setMode("RTTY", dialect: .kenwood) == "MD6;" && TextCAT.setMode("PKTUSB", dialect: .yaesu) == "MD0C;")
    #expect(TextCAT.setMode("PKTUSB", dialect: .kenwood) == "MD2;DA1;")
    #expect(TextCAT.setMode("nonsense", dialect: .kenwood) == nil)
}
