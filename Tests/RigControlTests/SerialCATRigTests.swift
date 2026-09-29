// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import CSerial
import Foundation
import Testing
@testable import RigControl

/// Simulované rádio: odpověď podle zapsaných bajtů (volitelně s echem jako sběrnice CI-V).
final class FakeCATTransport: CATTransport, @unchecked Sendable {
    let lock = NSLock()
    var pending: [UInt8] = []
    var written: [[UInt8]] = []
    var opened = false
    var echo = false
    let respond: ([UInt8]) -> [UInt8]
    init(echo: Bool = false, respond: @escaping ([UInt8]) -> [UInt8]) { self.echo = echo; self.respond = respond }
    func open() throws { opened = true }
    func close() { opened = false }
    func write(_ b: [UInt8]) throws {
        lock.withLock { written.append(b); pending += (echo ? b : []) + respond(b) }
    }
    func read(max: Int, timeout: Duration) throws -> [UInt8] {
        lock.withLock { let n = min(max, pending.count); defer { pending.removeFirst(n) }; return Array(pending.prefix(n)) }
    }
    func discardInput() { lock.withLock { pending.removeAll() } }
}

/// IC-7300 (94h): frekvence 14,085 MHz, mód RTTY; ACK = FB.
func fakeIcom(freq: inout Int) -> FakeCATTransport {
    nonisolated(unsafe) var f = freq
    return FakeCATTransport(echo: true) { b in
        guard b.count >= 6 else { return [] }
        let hdr: [UInt8] = [0xFE, 0xFE, 0xE0, 0x94]
        switch b[4] {
        case 0x03: return hdr + [0x03] + CIV.bcd(f) + [0xFD]
        case 0x04: return hdr + [0x04, 0x04, 0x01, 0xFD]
        case 0x05: f = CIV.fromBCD(Array(b[5..<10])) ?? f; return hdr + [0xFB, 0xFD]
        case 0x1C, 0x06, 0x1A: return hdr + [0xFB, 0xFD]
        default: return hdr + [0xFA, 0xFD]
        }
    }
}

@Test func icomRigRoundTrip() async throws {
    var f = 14_085_000
    let t = fakeIcom(freq: &f)
    let rig = SerialCATRig(transport: t, protocol: .icom(address: 0x94), timeout: .milliseconds(200))
    try await rig.connect()
    #expect(try await rig.frequency() == 14_085_000)
    #expect(try await rig.mode() == "RTTY")
    try await rig.setFrequency(7_045_000)
    #expect(try await rig.frequency() == 7_045_000)
    try await rig.setPTT(true)
    #expect(t.written.last == CIV.ptt(true, to: 0x94))
    try await rig.setMode("PKTUSB")                                  // USB + datový režim
    #expect(t.written.suffix(2) == [CIV.frame(to: 0x94, cmd: 0x06, [0x01]), CIV.dataMode(true, to: 0x94)])
    await rig.disconnect()
    #expect(!t.opened)
}

@Test func icomNakAndTimeout() async throws {
    let nak = FakeCATTransport { b in [0xFE, 0xFE, 0xE0, 0x94, 0xFA, 0xFD] }
    let r1 = SerialCATRig(transport: nak, protocol: .icom(address: 0x94), timeout: .milliseconds(100))
    try await r1.connect()
    await #expect(throws: RigError.self) { try await r1.setPTT(true) }
    let silent = FakeCATTransport { _ in [] }
    let r2 = SerialCATRig(transport: silent, protocol: .icom(address: 0x94), timeout: .milliseconds(100))
    try await r2.connect()
    await #expect(throws: RigError.timeout) { try await r2.frequency() }
}

@Test func kenwoodAndYaesuRig() async throws {
    nonisolated(unsafe) var fa = "FA00014085000;"
    let k = FakeCATTransport { b in
        let s = String(decoding: b, as: UTF8.self)
        if s == "FA;" { return Array(fa.utf8) }
        if s == "MD;" { return Array("MD6;".utf8) }
        if s.hasPrefix("FA") { fa = s }
        return []                                                     // nastavovací příkazy Kenwood nepotvrzuje
    }
    let rig = SerialCATRig(transport: k, protocol: .text(.kenwood), timeout: .milliseconds(200))
    try await rig.connect()
    #expect(try await rig.frequency() == 14_085_000)
    #expect(try await rig.mode() == "RTTY")
    try await rig.setFrequency(3_590_000)
    #expect(try await rig.frequency() == 3_590_000)
    try await rig.setPTT(true); try await rig.setPTT(false)
    #expect(k.written.suffix(2).map { String(decoding: $0, as: UTF8.self) } == ["TX1;", "RX;"])

    let y = FakeCATTransport { b in String(decoding: b, as: UTF8.self) == "FA;" ? Array("FA014085000;".utf8) : [] }
    let yr = SerialCATRig(transport: y, protocol: .text(.yaesu), timeout: .milliseconds(200))
    try await yr.connect()
    #expect(try await yr.frequency() == 14_085_000)
    try await yr.setFrequency(14_080_000)
    #expect(String(decoding: y.written.last!, as: UTF8.self) == "FA014080000;")
    // rádio odpoví „?;“ (neznámý příkaz) → chyba protokolu
    let q = FakeCATTransport { _ in Array("?;".utf8) }
    let qr = SerialCATRig(transport: q, protocol: .text(.kenwood), timeout: .milliseconds(100))
    try await qr.connect()
    await #expect(throws: RigError.self) { try await qr.frequency() }
}

// Skutečný sériový transport přes pseudoterminál: na druhém konci simulované IC-7300 (bez echa)
@Test func serialTransportOverPTY() async throws {
    var master: Int32 = -1, slave: Int32 = -1
    var name = [CChar](repeating: 0, count: 128)
    guard openpty(&master, &slave, &name, nil, nil) == 0 else { return }
    let path = String(cString: name)
    // slave nechat otevřený do konce (jinak master čte EIO); transport si otevře vlastní deskriptor
    nonisolated(unsafe) let m = master
    let radio = Thread {
        var parser = CIV.Parser(), buf = [UInt8](repeating: 0, count: 256)
        // rádio čte rámce určené jemu (to 94, from E0) – vlastní parser: prohodit role
        while true {
            let n = read(m, &buf, 256)
            if n <= 0 { break }
            var bytes = Array(buf[0..<n])
            // převést rámce pro rádio na rámce „pro E0“, aby je CIV.Parser přijal
            for i in bytes.indices where i + 3 < bytes.count && bytes[i] == 0xFE && bytes[i + 1] == 0xFE && bytes[i + 2] == 0x94 {
                bytes[i + 2] = 0xE0; bytes[i + 3] = 0x94
            }
            for f in parser.feed(bytes) where f.cmd == 0x03 {
                let ans: [UInt8] = [0xFE, 0xFE, 0xE0, 0x94, 0x03] + CIV.bcd(3_590_000) + [0xFD]
                _ = ans.withUnsafeBufferPointer { write(m, $0.baseAddress, $0.count) }
            }
        }
    }
    radio.start()
    let rig = SerialCATRig(transport: SerialCATTransport(path: path, baud: 19200), protocol: .icom(address: 0x94),
                           timeout: .milliseconds(500))
    do {
        try await rig.connect()
        #expect(try await rig.frequency() == 3_590_000)
    } catch RigError.protocolError(let m) where m.contains("Inappropriate ioctl") {
        Issue.record("PTY: \(m)")
    }
    await rig.disconnect()
    close(slave); close(master)
}

// Review 1: I/O chyba (vytažené USB) zavře port a další dotaz ho otevře znovu
@Test func catReopensAfterIOError() async throws {
    final class Flaky: CATTransport, @unchecked Sendable {
        var opens = 0, failNext = false
        func open() throws { opens += 1 }
        func close() {}
        func write(_ b: [UInt8]) throws { if failNext { failNext = false; throw CATIOError.io("EIO") } }
        func read(max: Int, timeout: Duration) throws -> [UInt8] { Array("FA00014085000;".utf8) }
        func discardInput() {}
    }
    let t = Flaky()
    let rig = SerialCATRig(transport: t, protocol: .text(.kenwood), timeout: .milliseconds(100))
    #expect(try await rig.frequency() == 14_085_000)
    t.failNext = true
    await #expect(throws: RigError.offline) { try await rig.frequency() }
    #expect(try await rig.frequency() == 14_085_000)
    #expect(t.opens == 2)
}

// Review 2: starší Yaesu (FTDX3000, FT-950) mají FA s 8 číslicemi – délka se převezme z odpovědi rádia
@Test func yaesuFrequencyDigitsFromRadio() async throws {
    let y = FakeCATTransport { b in String(decoding: b, as: UTF8.self) == "FA;" ? Array("FA14085000;".utf8) : [] }
    let rig = SerialCATRig(transport: y, protocol: .text(.yaesu), timeout: .milliseconds(200))
    #expect(try await rig.frequency() == 14_085_000)
    try await rig.setFrequency(7_045_000)
    #expect(String(decoding: y.written.last!, as: UTF8.self) == "FA07045000;")
}

// Review 13: Kenwood při odchodu z datového režimu vypne DA; Elecraft zná PKTLSB
@Test func textModesLeaveDataMode() {
    #expect(TextCAT.setMode("RTTY", dialect: .kenwood) == "MD6;DA0;")
    #expect(TextCAT.setMode("USB", dialect: .kenwood) == "MD2;DA0;")
    #expect(TextCAT.setMode("PKTLSB", dialect: .elecraft) == "MD9;DT0;")
}

// Review (odloženo): zápis na zaseknutý port (plný buffer) skončí po limitu, nezablokuje frontu CAT
@Test func serialWriteTimesOut() throws {
    var fds: [Int32] = [0, 0]
    #expect(pipe(&fds) == 0)
    let w = fds[1]
    _ = fcntl(w, F_SETFL, fcntl(w, F_GETFL) | O_NONBLOCK)
    let chunk = [UInt8](repeating: 0x55, count: 4096)
    while chunk.withUnsafeBufferPointer({ write(w, $0.baseAddress, 4096) }) > 0 {}      // naplnit buffer roury
    _ = fcntl(w, F_SETFL, fcntl(w, F_GETFL) & ~O_NONBLOCK)
    let t0 = Date()
    let e = chunk.withUnsafeBufferPointer { cserial_write_timeout(w, $0.baseAddress, 16, 200) }
    #expect(e == ETIMEDOUT)
    #expect(Date().timeIntervalSince(t0) < 1)
    close(fds[0]); close(fds[1])
}
