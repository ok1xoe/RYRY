// Copyright 2026 OK1XOE (RYRY), LGPL v3
import AppCore
import Engine
import Foundation
import ModemKit
import QSOLog
import XMLRPC

/// An XML-RPC server compatible with fldigi (a subset of the methods, see spec 7.1).
public final class FldigiXMLRPCServer: @unchecked Sendable {
    public static let version = "0.1.0"
    private let app: AppController
    private var http: HTTPServer?
    private let host: String, port: UInt16
    private let lock = NSLock()
    private var rxCursor = 0, txCursor = 0
    private var rxAfterTx = false          // fldigi ^r in text.add_tx before main.tx

    public init(app: AppController, host: String = "127.0.0.1", port: UInt16 = 7362) {
        self.app = app; self.host = host; self.port = port
    }

    public func start() async throws -> UInt16 {
        let s = HTTPServer(host: host, port: port) { [weak self] req in
            guard let self else { return HTTPResponse(status: 503, headers: [:], body: Data()) }
            return await self.handle(req)
        }
        http = s
        return try await s.start()
    }

    public func stop() { http?.stop(); http = nil }

    struct Fault: Error { let code: Int; let msg: String }
    static func badParams(_ m: String) -> Fault { Fault(code: -32602, msg: "\(m): invalid parameters") }

    private func handle(_ req: HTTPRequest) async -> HTTPResponse {
        let body: Data
        do {
            let (method, params) = try XMLRPCCodec.decodeCall(req.body)
            body = XMLRPCCodec.encodeResponse(try await call(method, params))
        } catch let f as Fault {
            body = XMLRPCCodec.encodeFault(XMLRPCFault(code: f.code, message: f.msg))
        } catch let e as XMLRPCCodecError {
            body = XMLRPCCodec.encodeFault(XMLRPCFault(code: -32700, message: "parse error: \(e)"))
        } catch {
            body = XMLRPCCodec.encodeFault(XMLRPCFault(code: -32001, message: "\(error)"))
        }
        return HTTPResponse(status: 200, headers: ["Content-Type": "text/xml"], body: body)
    }

    // MARK: Metody

    static let methods: [(String, String, String)] = [
        ("fldigi.list", "A:n", "Returns the list of methods"),
        ("fldigi.name", "s:n", "Returns the program name"),
        ("fldigi.version", "s:n", "Returns the program version as a string"),
        ("fldigi.name_version", "s:n", "Returns the program name and version"),
        ("fldigi.version_struct", "S:n", "Returns the program version as a struct"),
        ("main.get_trx_status", "s:n", "Returns transmit/tune/receive status"),
        ("main.tx", "n:n", "Transmits"), ("main.rx", "n:n", "Receives"), ("main.tune", "n:n", "Tunes"),
        ("main.abort", "n:n", "Aborts a transmit or tune"),
        ("main.rx_only", "n:n", "Disables Tx."), ("main.rx_tx", "n:n", "Sets normal Rx/Tx switching."),
        ("main.get_frequency", "d:n", "Returns the RF carrier frequency"),
        ("main.set_frequency", "d:d", "Sets the RF carrier frequency. Returns the old value"),
        ("main.get_afc", "b:n", "Returns the AFC state"), ("main.set_afc", "b:b", "Sets the AFC state. Returns the old state"),
        ("main.get_reverse", "b:n", "Returns the Reverse Sideband state"),
        ("main.set_reverse", "b:b", "Sets the Reverse Sideband state. Returns the old state"),
        ("main.get_squelch", "b:n", "Returns the squelch state"),
        ("main.set_squelch", "b:b", "Sets the squelch state. Returns the old state"),
        ("main.get_squelch_level", "d:n", "Returns the squelch level"),
        ("main.set_squelch_level", "d:d", "Sets the squelch level. Returns the old level"),
        ("modem.get_name", "s:n", "Returns the name of the current modem"),
        ("modem.get_names", "A:n", "Returns all modem names"),
        ("modem.set_by_name", "s:s", "Sets the current modem. Returns old name"),
        ("modem.get_carrier", "i:n", "Returns the modem carrier frequency"),
        ("modem.set_carrier", "i:i", "Sets modem carrier. Returns old carrier"),
        ("rig.get_frequency", "d:n", "Returns the RF carrier frequency"),
        ("rig.set_frequency", "d:d", "Sets the RF carrier frequency. Returns the old value"),
        ("rig.get_mode", "s:n", "Returns the name of the current transceiver mode"),
        ("rig.set_mode", "n:s", "Selects a mode"),
        ("rig.get_modes", "A:n", "Returns the list of available rig modes"),
        ("rig.get_name", "s:n", "Returns the rig name"),
        ("text.add_tx", "n:s", "Adds a string to the TX text widget"),
        ("text.add_tx_bytes", "n:6", "Adds a byte string to the TX text widget"),
        ("text.clear_tx", "n:n", "Clears the TX text widget"),
        ("text.get_rx_length", "i:n", "Returns the number of characters in the RX widget"),
        ("text.get_rx", "6:ii", "Returns a range of characters (start, length) from the RX text widget"),
        ("text.clear_rx", "n:n", "Clears the RX text widget"),
        ("rx.get_data", "6:n", "Returns all RX data received since last query."),
        ("tx.get_data", "6:n", "Returns all TX data transmitted since last query."),
        ("log.clear", "n:n", "Clears the contents of the log fields"),
        ("log.get_call", "s:n", "Returns the Call field contents"), ("log.set_call", "n:s", "Sets the Call field contents"),
        ("log.get_name", "s:n", "Returns the Name field contents"), ("log.set_name", "n:s", "Sets the Name field contents"),
        ("log.get_qth", "s:n", "Returns the QTH field contents"), ("log.set_qth", "n:s", "Sets the QTH field contents"),
        ("log.get_locator", "s:n", "Returns the Locator field contents"), ("log.set_locator", "n:s", "Sets the Locator field contents"),
        ("log.get_rst_in", "s:n", "Returns the RST(r) field contents"), ("log.set_rst_in", "n:s", "Sets the RST(r) field contents"),
        ("log.get_rst_out", "s:n", "Returns the RST(s) field contents"), ("log.set_rst_out", "n:s", "Sets the RST(s) field contents"),
        ("log.get_serial_number", "s:n", "Returns the serial number field contents"),
        ("log.set_serial_number", "n:s", "Sets the serial number field contents"),
        ("log.get_serial_number_sent", "s:n", "Returns the serial number (sent) field contents"),
        ("log.get_exchange", "s:n", "Returns the contest exchange field contents"),
        ("log.set_exchange", "n:s", "Sets the contest exchange field contents"),
        ("log.get_notes", "s:n", "Returns the Notes field contents"),
        ("log.set_notes", "n:s", "Sets the Notes field contents"),
        ("log.set_serial_number_sent", "n:s", "Sets the serial number (sent) field contents"),
        ("log.get_frequency", "s:n", "Returns the Frequency field contents"),
        ("log.get_band", "s:n", "Returns the current band name"),
        ("log.get_time_on", "s:n", "Returns the Time-On field contents"),
        ("log.get_time_off", "s:n", "Returns the Time-Off field contents"),
    ]

    private func str(_ p: [XMLRPCValue], _ m: String) throws -> String {
        guard let s = p.first?.stringValue else { throw Self.badParams(m) }; return s
    }
    private func dbl(_ p: [XMLRPCValue], _ m: String) throws -> Double {
        guard let v = p.first else { throw Self.badParams(m) }
        switch v { case .double(let d): return d; case .int(let i): return Double(i)
        default: throw Self.badParams(m) }
    }
    private func int(_ p: [XMLRPCValue], _ i: Int, _ m: String) throws -> Int {
        guard p.count > i, let v = p[i].intValue else { throw Self.badParams(m) }; return v
    }
    private func bool(_ p: [XMLRPCValue], _ m: String) throws -> Bool {
        guard let v = p.first?.boolValue else { throw Self.badParams(m) }; return v
    }

    private func boolParam(_ id: String) async -> Bool {
        if case .bool(let b)? = await app.modemParam(id) { return b }; return false
    }
    private func doubleParam(_ id: String) async -> Double {
        if case .double(let d)? = await app.modemParam(id) { return d }; return 0
    }
    private func setParam(_ id: String, _ v: ParameterValue, _ m: String) async throws {
        do { try await app.setModemParam(id, v) } catch { throw Self.badParams(m) }
    }
    private func tx(_ f: () async throws -> Void) async throws {
        do { try await f() } catch { throw Fault(code: -32001, msg: "TX odmítnuto: \(error)") }
    }

    private static let utcHHMM: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HHmm"; return f
    }()

    func call(_ m: String, _ p: [XMLRPCValue]) async throws -> XMLRPCValue {
        let engine = app.engine
        switch m {
        case "fldigi.list":
            return .array(Self.methods.map { .dict(["name": .string($0.0), "signature": .string($0.1), "help": .string($0.2)]) })
        case "fldigi.name": return .string("RYRY")
        case "fldigi.version": return .string(Self.version)
        case "fldigi.name_version": return .string("RYRY-\(Self.version)")
        case "fldigi.version_struct": return .dict(["major": .int(0), "minor": .int(1), "patch": .string("0")])

        case "main.get_trx_status":
            let st = await engine.state
            if await engine.isTuning { return .string("tune") }
            return .string([.rx, .stopped].contains(st) ? "rx" : "tx")
        case "main.tx":
            try await tx { try await app.tx() }
            if lock.withLock({ defer { rxAfterTx = false }; return rxAfterTx }) { await app.rx() }
            return .nil_
        case "main.tune": try await tx { try await app.tune() }; return .nil_
        case "main.rx": await app.rx(); return .nil_
        case "main.abort": await app.rxNow(); return .nil_
        case "main.rx_only": await app.setTxDisabled(true); return .nil_
        case "main.rx_tx": await app.setTxDisabled(false); return .nil_

        case "main.get_frequency", "rig.get_frequency":
            return .double(await engine.rigStatus?.frequency ?? 0)
        case "main.set_frequency", "rig.set_frequency":
            let f = try dbl(p, m)
            guard f.isFinite, f > 0 else { throw Self.badParams(m) }
            let old = await engine.rigStatus?.frequency ?? 0
            // without a rig (or offline) stay quiet like fldigi – loggers call set_frequency on every band change
            try? await app.setFrequency(f)
            return .double(old)

        case "main.get_afc": return .bool(await boolParam("afc"))
        case "main.set_afc":
            let old = await boolParam("afc"); try await setParam("afc", .bool(try bool(p, m)), m); return .bool(old)
        case "main.get_reverse": return .bool(await boolParam("reverse"))
        case "main.set_reverse":
            let old = await boolParam("reverse"); try await setParam("reverse", .bool(try bool(p, m)), m); return .bool(old)
        case "main.get_squelch": return .bool(await boolParam("squelch"))
        case "main.set_squelch":
            let old = await boolParam("squelch"); try await setParam("squelch", .bool(try bool(p, m)), m); return .bool(old)
        case "main.get_squelch_level": return .double(await doubleParam("squelchLevel") / 1024 * 100)
        case "main.set_squelch_level":
            let old = await doubleParam("squelchLevel") / 1024 * 100
            let v = try dbl(p, m)
            try await setParam("squelchLevel", .double(min(100, max(0, v)) * 1024 / 100), m)
            return .double(old)

        case "modem.get_name": return .string("RTTY")
        case "modem.get_names": return .array([.string("RTTY")])
        case "modem.set_by_name":
            guard try str(p, m).uppercased().hasPrefix("RTTY") else { throw Fault(code: -32602, msg: "only RTTY is available") }
            return .string("RTTY")
        case "modem.get_carrier":
            let mark = await doubleParam("mark"), shift = await doubleParam("shift")
            return .int(Int((mark + shift / 2).rounded()))
        case "modem.set_carrier":
            let c = Double(try int(p, 0, m))
            let mark = await doubleParam("mark"), shift = await doubleParam("shift")
            try await setParam("mark", .double(c - shift / 2), m)
            return .int(Int((mark + shift / 2).rounded()))

        case "rig.get_mode": return .string(await engine.rigStatus?.mode ?? "")
        case "rig.set_mode":
            do { try await app.setRigMode(try str(p, m)) } catch let f as Fault { throw f } catch { throw Fault(code: -32002, msg: "rig: \(error)") }
            return .nil_
        case "rig.get_modes": return .array(["USB", "LSB", "FSK", "PKTUSB"].map { .string($0) })
        case "rig.get_name": return .string(await engine.rigName)

        case "text.add_tx":
            // fldigi: ^r / ^R = switch to RX after the text has been transmitted
            var text = try str(p, m)
            var rxAfter = false
            for marker in ["^r", "^R"] where text.contains(marker) {
                rxAfter = true; text = text.replacingOccurrences(of: marker, with: "")
            }
            await app.send(text: text)
            if rxAfter {
                if [.keying, .pttOn, .tx].contains(await engine.state) { await app.rx() }
                else { lock.withLock { rxAfterTx = true } }
            }
            return .nil_
        case "text.add_tx_bytes":
            guard case .base64(let d)? = p.first else { throw Self.badParams(m) }
            await app.send(text: String(decoding: d, as: UTF8.self)); return .nil_
        case "text.clear_tx": await app.clearTx(); return .nil_
        case "text.get_rx_length": return .int(app.rxText.totalLength)
        case "text.get_rx":
            let s = try int(p, 0, m), l = try int(p, 1, m)
            return .base64(Data(app.rxText.range(start: s, length: l).utf8))
        case "text.clear_rx": app.rxText.clear(); return .nil_
        case "rx.get_data":
            let t = lock.withLock { app.rxText.takeNew(cursor: &rxCursor) }
            return .base64(Data(t.utf8))
        case "tx.get_data":
            let t = lock.withLock { app.txText.takeNew(cursor: &txCursor) }
            return .base64(Data(t.utf8))

        case "log.clear": await app.clearQSO(); return .nil_
        case "log.get_frequency":
            return .string((await engine.rigStatus?.frequency).map { String(format: "%.3f", $0 / 1000) } ?? "")
        case "log.get_band": return .string(Bands.band(forHz: await engine.rigStatus?.frequency) ?? "")
        case "log.get_time_on":
            return .string((await app.qso.timeOn).map { Self.utcHHMM.string(from: $0) } ?? "")
        case "log.get_time_off": return .string(Self.utcHHMM.string(from: Date()))
        default:
            if let r = try await logField(m, p) { return r }
            throw Fault(code: -32601, msg: "unknown method: \(m)")
        }
    }

    private static let logMap: [String: String] = [
        "call": "call", "name": "name", "qth": "qth", "locator": "locator", "rst_in": "rstRcvd",
        "rst_out": "rstSent", "serial_number": "serialRcvd", "serial_number_sent": "serialSent",
        "exchange": "exchangeRcvd", "notes": "notes",
    ]

    private func logField(_ m: String, _ p: [XMLRPCValue]) async throws -> XMLRPCValue? {
        guard m.hasPrefix("log.get_") || m.hasPrefix("log.set_") else { return nil }
        let key = String(m.dropFirst(8))
        guard let field = Self.logMap[key] else { return nil }
        if m.hasPrefix("log.get_") { return .string(await app.qso.value(field) ?? "") }
        do { try await app.setQSOField(field, try str(p, m)) } catch let f as Fault { throw f } catch { throw Self.badParams(m) }
        return .nil_
    }
}
