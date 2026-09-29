// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import CSerial
import Foundation

/// Bajtový kanál k rádiu (USB sériový port). Volání jsou blokující – SerialCATRig je volá na vlastní frontě.
public protocol CATTransport: AnyObject, Sendable {
    func open() throws
    func close()
    func write(_ bytes: [UInt8]) throws
    /// Až `max` bajtů; čeká nejvýše `timeout` (prázdné = nic nepřišlo).
    func read(max: Int, timeout: Duration) throws -> [UInt8]
    func discardInput()
}

/// Chyba vstupu/výstupu portu (odpojené USB apod.) – port se zavře a příští dotaz ho otevře znovu.
public enum CATIOError: Error, Equatable { case io(String) }

/// Protokol CAT: Icom CI-V (adresa rádia) nebo textový (Kenwood, Elecraft, Yaesu).
public enum CATProtocol: Sendable, Equatable {
    case icom(address: UInt8)
    case text(TextCAT.Dialect)
}

/// Vestavěné ovládání rádia přes CAT (bez hamlib). Požadavky se zpracují postupně na sériové frontě.
public final class SerialCATRig: Rig, @unchecked Sendable {
    public let name: String
    private let transport: CATTransport
    private let proto: CATProtocol
    private let timeout: Duration
    private let queue = DispatchQueue(label: "mmtty4mac.cat")
    private var isOpen = false { didSet { let v = isOpen; openLock.withLock { openFlag = v } } }
    /// Po výslovném disconnect() se port znovu neotevírá (dokud nepřijde connect()).
    private var closedByOwner = false
    /// Počet číslic frekvence podle poslední odpovědi rádia (starší Yaesu mají 8).
    private var faDigits: Int?

    public init(transport: CATTransport, protocol p: CATProtocol, timeout: Duration = .milliseconds(500), name: String = "CAT") {
        self.transport = transport; self.proto = p; self.timeout = timeout; self.name = name
    }

    private func onQueue<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
            queue.async { c.resume(with: Result { try body() }) }
        }
    }

    /// Bez blokování (queue.sync by čekal na běžící CAT dotaz až ~1 s na vlákně actoru Engine).
    public var isIdle: Bool { openLock.withLock { !openFlag } }
    private let openLock = NSLock()
    private var openFlag = false

    public func connect() async throws {
        try await onQueue { [self] in
            closedByOwner = false
            if isOpen { return }
            do { try transport.open() } catch { throw RigError.protocolError("\(error)") }
            isOpen = true
        }
    }

    public func disconnect() async {
        _ = try? await onQueue { [self] in transport.close(); isOpen = false; closedByOwner = true }
    }

    private func ensureOpen() throws {
        if isOpen { return }
        if closedByOwner { throw RigError.offline }
        do { try transport.open(); isOpen = true } catch { throw RigError.offline }
    }

    private func io<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch let e as RigError { throw e } catch {
            transport.close(); isOpen = false                   // odpojené USB → příště otevřít znovu
            throw RigError.offline
        }
    }

    // MARK: Icom CI-V

    /// Odešle rámec a počká na odpověď s příkazem `expect` (nebo FB/FA u nastavení).
    private func civ(_ addr: UInt8, _ frame: [UInt8], expect: UInt8?) throws -> CIV.Frame? {
        try ensureOpen()
        return try io {
            transport.discardInput()
            try transport.write(frame)
            var parser = CIV.Parser()
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                let chunk = try transport.read(max: 64, timeout: .milliseconds(20))
                for f in parser.feed(chunk) where f.from == addr {
                    if f.cmd == 0xFA { throw RigError.rejected(-1) }
                    if let expect { if f.cmd == expect { return f } } else if f.cmd == 0xFB { return nil }
                }
            }
            throw RigError.timeout
        }
    }

    // MARK: Textový CAT

    /// Dotaz: odpověď končí „;“ a začíná stejnými dvěma písmeny jako dotaz.
    private func textQuery(_ q: String) throws -> String {
        try ensureOpen()
        return try io {
            transport.discardInput()
            try transport.write(Array(q.utf8))
            var buf = ""
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                buf += String(decoding: try transport.read(max: 64, timeout: .milliseconds(20)), as: UTF8.self)
                while let semi = buf.firstIndex(of: ";") {
                    let msg = String(buf[...semi]); buf = String(buf[buf.index(after: semi)...])
                    if msg == "?;" || msg == "E;" || msg == "O;" { throw RigError.protocolError("rádio odmítlo \(q)") }
                    if msg.hasPrefix(String(q.prefix(2))) { return msg }
                }
            }
            throw RigError.timeout
        }
    }

    private func textSet(_ cmd: String) throws {
        try ensureOpen()
        try io { try transport.write(Array(cmd.utf8)) }
    }


    // MARK: Rig

    public func frequency() async throws -> Double {
        try await onQueue { [self] in
            switch proto {
            case .icom(let a):
                guard let f = try civ(a, CIV.readFrequency(to: a), expect: 0x03), let hz = CIV.fromBCD(Array(f.data.prefix(5))), hz > 0
                else { throw RigError.protocolError("frekvence") }
                return Double(hz)
            case .text:
                let r = try textQuery(TextCAT.frequencyQuery)
                guard let hz = TextCAT.parseFrequency(r) else { throw RigError.protocolError("frekvence") }
                faDigits = r.count - 3
                return hz
            }
        }
    }

    public func setFrequency(_ hz: Double) async throws {
        guard hz.isFinite, hz > 0, hz < 10e9 else { throw RigError.protocolError("frekvence \(hz)") }
        try await onQueue { [self] in
            switch proto {
            case .icom(let a): _ = try civ(a, CIV.setFrequency(hz, to: a), expect: nil)
            case .text(let d):
                try textSet(faDigits.map { TextCAT.setFrequency(hz, digits: $0) } ?? TextCAT.setFrequency(hz, dialect: d))
            }
        }
    }

    public func mode() async throws -> String {
        try await onQueue { [self] in
            switch proto {
            case .icom(let a):
                guard let f = try civ(a, CIV.readMode(to: a), expect: 0x04), let c = f.data.first, let m = CIV.modeName(c)
                else { throw RigError.protocolError("mód") }
                return m
            case .text(let d):
                guard let m = TextCAT.parseMode(try textQuery(TextCAT.modeQuery(d)), dialect: d) else { throw RigError.protocolError("mód") }
                return m
            }
        }
    }

    public func setMode(_ mode: String) async throws {
        try await onQueue { [self] in
            switch proto {
            case .icom(let a):
                guard let c = CIV.modeCode(mode) else { throw RigError.protocolError("neznámý mód \(mode)") }
                _ = try civ(a, CIV.frame(to: a, cmd: 0x06, [c]), expect: nil)
                let data = mode.uppercased().hasPrefix("PKT")
                // datový režim podporují jen novější rádia – u starších odmítnutí ignorovat, pokud ho nechceme zapnout
                do { _ = try civ(a, CIV.dataMode(data, to: a), expect: nil) } catch { if data { throw error } }
            case .text(let d):
                guard let cmd = TextCAT.setMode(mode, dialect: d) else { throw RigError.protocolError("neznámý mód \(mode)") }
                try textSet(cmd)
            }
        }
    }

    public func setPTT(_ on: Bool) async throws {
        try await onQueue { [self] in
            switch proto {
            case .icom(let a): _ = try civ(a, CIV.ptt(on, to: a), expect: nil)
            case .text(let d): try textSet(TextCAT.ptt(on, dialect: d))
            }
        }
    }
}

/// USB sériový port pro CAT (termios přes CSerial): 8 datových bitů, bez parity, 1 nebo 2 stop bity.
public final class SerialCATTransport: CATTransport, @unchecked Sendable {
    public let path: String
    let baud: Int, stopBits: Int
    private var fd: Int32 = -1

    /// `rts`: po otevření zapnout RTS (Yaesu „CAT RTS = ENABLE“ bez něj příkazy nepřijme).
    let rts: Bool
    public init(path: String, baud: Int, stopBits: Int = 1, rts: Bool = false) {
        self.path = path; self.baud = baud; self.stopBits = stopBits; self.rts = rts
    }
    deinit { close() }

    private static func err(_ e: Int32) -> String { String(cString: strerror(e)) }

    public func open() throws {
        if fd >= 0 { return }
        var f: Int32 = -1
        var e = cserial_open(path, &f)
        if e != 0 { throw CATIOError.io("\(path): \(Self.err(e))") }
        e = cserial_configure(f, 8, Int32(stopBits))
        if e == 0 { e = cserial_set_speed(f, UInt(baud)) }
        if e == 0, rts { e = cserial_set_rts(f, 1) }
        if e != 0 { _ = cserial_close(f); throw CATIOError.io("\(path): \(Self.err(e))") }
        fd = f
    }

    public func close() { if fd >= 0 { _ = cserial_close(fd); fd = -1 } }

    public func write(_ bytes: [UInt8]) throws {
        guard fd >= 0 else { throw CATIOError.io("port zavřený") }
        // limit 1 s: zaseknutý USB port nesmí zablokovat frontu CAT (a s ní odpojení a zastavení engine)
        let e = bytes.withUnsafeBufferPointer { cserial_write_timeout(fd, $0.baseAddress, UInt($0.count), 1000) }
        if e != 0 { throw CATIOError.io("zápis: \(Self.err(e))") }
    }

    public func read(max: Int, timeout: Duration) throws -> [UInt8] {
        guard fd >= 0 else { throw CATIOError.io("port zavřený") }
        var buf = [UInt8](repeating: 0, count: max)
        var got = 0
        let ms = Int32(timeout.components.seconds * 1000 + timeout.components.attoseconds / 1_000_000_000_000_000)
        let e = buf.withUnsafeMutableBufferPointer { cserial_read(fd, $0.baseAddress, UInt(max), ms, &got) }
        if e != 0 { throw CATIOError.io("čtení: \(Self.err(e))") }
        return Array(buf.prefix(got))
    }

    public func discardInput() { if fd >= 0 { _ = cserial_flush_input(fd) } }
}
