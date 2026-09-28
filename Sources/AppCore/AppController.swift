// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Engine
import Foundation
import MacroEngine
import ModemKit
import QSOLog
import RigControl
import Settings

/// Pole QSO okna.
public struct QSOFields: Codable, Sendable, Equatable {
    public var call = "", name = "", qth = "", locator = ""
    public var rstSent = "599", rstRcvd = "599"
    public var serialSent: Int?, serialRcvd: Int?
    public var exchangeSent = "", exchangeRcvd = "", notes = ""
    public var timeOn: Date?
    public init() {}

    public static let fieldNames = ["call", "name", "qth", "locator", "rstSent", "rstRcvd",
                                    "serialSent", "serialRcvd", "exchangeSent", "exchangeRcvd", "notes"]
    public func value(_ name: String) -> String? {
        switch name {
        case "call": return call; case "name": return name_
        case "qth": return qth; case "locator": return locator
        case "rstSent": return rstSent; case "rstRcvd": return rstRcvd
        case "serialSent": return serialSent.map(String.init) ?? ""
        case "serialRcvd": return serialRcvd.map(String.init) ?? ""
        case "exchangeSent": return exchangeSent; case "exchangeRcvd": return exchangeRcvd
        case "notes": return notes
        default: return nil
        }
    }
    private var name_: String { self.name }
}

public enum AppError: Error, Equatable, Sendable {
    case unknownField(String), noLog, badMacro(Int), profile(String), log(String)
}

public enum AppEvent: Sendable {
    case engine(EngineEvent)
    case qsoChanged(QSOFields)
    case qsoLogged(QSORecord), qsoUpdated(QSORecord), qsoDeleted(UUID)
    case error(String)
}

final class AppBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var subs: [UUID: AsyncStream<AppEvent>.Continuation] = [:]
    private var finished = false
    func subscribe() -> AsyncStream<AppEvent> {
        let (s, c) = AsyncStream.makeStream(of: AppEvent.self, bufferingPolicy: .unbounded)
        let id = UUID()
        lock.withLock { if finished { c.finish() } else { subs[id] = c } }
        c.onTermination = { [weak self] _ in self?.lock.withLock { _ = self?.subs.removeValue(forKey: id) } }
        return s
    }
    func send(_ e: AppEvent) { for c in lock.withLock({ Array(subs.values) }) { c.yield(e) } }
    func finish() {
        let cs = lock.withLock { () -> [AsyncStream<AppEvent>.Continuation] in finished = true; defer { subs.removeAll() }; return Array(subs.values) }
        cs.forEach { $0.finish() }
    }
}

/// Aplikační vrstva nad Engine: QSO okno, log, makra, historie textu. Společná pro GUI i API.
public actor AppController {
    public nonisolated let engine: Engine
    public private(set) var settings: AppSettings
    public let log: QSOLogStore?
    private let profiles: ProfileStore?
    public nonisolated let rxText = TextHistory()
    public nonisolated let txText = TextHistory()
    public private(set) var qso = QSOFields()
    public private(set) var txDisabled = false
    private let broadcaster = AppBroadcaster()
    private var eventTask: Task<Void, Never>?

    public init(settings: AppSettings, engine: Engine, log: QSOLogStore?, profiles: ProfileStore? = nil) {
        self.settings = settings; self.engine = engine; self.log = log; self.profiles = profiles
    }

    public nonisolated func events() -> AsyncStream<AppEvent> { broadcaster.subscribe() }

    public func start() async throws {
        for (k, v) in settings.rtty {
            do { try await engine.setModemParam(k, v) } catch { broadcaster.send(.error("parametr \(k): \(error)")) }
        }
        let stream = engine.events()
        eventTask = Task { [weak self] in
            for await e in stream { await self?.handle(e) }
        }
        try await engine.start()
    }

    public func stop() async {
        await engine.stop()
        await eventTask?.value
        eventTask = nil
        broadcaster.finish()
    }

    private func handle(_ e: EngineEvent) async {
        switch e {
        case .modem(.rxText(let c, let echo)): (echo ? txText : rxText).append(String(c))
        case .logRequested:
            do { _ = try await logQSO() } catch { broadcaster.send(.error("log: \(error)")) }
        default: break
        }
        broadcaster.send(.engine(e))
    }

    // MARK: TX/RX

    public func setTxDisabled(_ on: Bool) { txDisabled = on }
    public func tx() async throws {
        if txDisabled { throw EngineError.pttUnavailable("TX zakázáno (rx_only)") }
        try await engine.tx()
    }
    public func tune() async throws {
        if txDisabled { throw EngineError.pttUnavailable("TX zakázáno (rx_only)") }
        try await engine.tune()
    }
    public func rx() async { await engine.rx() }
    public func rxNow() async { await engine.rxNow() }
    public func send(text: String) async { await engine.send(text: text) }
    public func clearTx() async { await engine.clearTx() }
    public var state: EngineState { get async { await engine.state } }

    public func macroContext() -> MacroContext {
        var c = MacroContext()
        c.myCall = settings.station.call.uppercased()
        c.hisCall = qso.call; c.name = qso.name; c.qth = qso.qth
        c.rstSent = qso.rstSent + (qso.serialSent.map { String(format: "%03d", $0) } ?? "")
        c.rstRcvd = qso.rstRcvd
        c.now = Date()
        return c
    }

    public func runMacro(index: Int) async throws {
        guard settings.macros.indices.contains(index) else { throw AppError.badMacro(index) }
        let m = MacroEngine.expand(settings.macros[index].text, context: macroContext())
        if txDisabled, m.mode == .send { throw EngineError.pttUnavailable("TX zakázáno (rx_only)") }
        try await engine.sendMacro(m)
    }

    public func setMacros(_ m: [Macro]) { settings.macros = m }
    public func setStation(_ st: Station) { settings.station = st }

    // MARK: QSO

    public func setQSOField(_ name: String, _ value: String) throws {
        let v = value.trimmingCharacters(in: .whitespaces)
        switch name {
        case "call":
            qso.call = v.uppercased()
            if !v.isEmpty, qso.timeOn == nil { qso.timeOn = Date() }
        case "name": qso.name = v
        case "qth": qso.qth = v
        case "locator": qso.locator = v.uppercased()
        case "rstSent": qso.rstSent = v
        case "rstRcvd": qso.rstRcvd = v
        case "serialSent": qso.serialSent = Int(v)
        case "serialRcvd": qso.serialRcvd = Int(v)
        case "exchangeSent": qso.exchangeSent = v
        case "exchangeRcvd": qso.exchangeRcvd = v
        case "notes": qso.notes = v
        default: throw AppError.unknownField(name)
        }
        broadcaster.send(.qsoChanged(qso))
    }

    public func clearQSO() {
        qso = QSOFields()
        broadcaster.send(.qsoChanged(qso))
    }

    @discardableResult
    public func logQSO() async throws -> QSORecord {
        guard let log else { throw AppError.noLog }
        guard !qso.call.isEmpty else { throw AppError.log("chybí značka") }
        let now = Date()
        var r = QSORecord(call: qso.call, timeOn: qso.timeOn ?? now, mode: await engine.currentMode().adifMode)
        r.timeOff = now
        r.frequency = await engine.rigStatus?.frequency
        r.rstSent = qso.rstSent; r.rstRcvd = qso.rstRcvd
        r.name = qso.name.isEmpty ? nil : qso.name
        r.qth = qso.qth.isEmpty ? nil : qso.qth
        r.grid = qso.locator.isEmpty ? nil : qso.locator
        r.serialSent = qso.serialSent; r.serialRcvd = qso.serialRcvd
        r.exchangeSent = qso.exchangeSent.isEmpty ? nil : qso.exchangeSent
        r.exchangeRcvd = qso.exchangeRcvd.isEmpty ? nil : qso.exchangeRcvd
        r.comment = qso.notes.isEmpty ? nil : qso.notes
        r.stationCallsign = settings.station.call.isEmpty ? nil : settings.station.call.uppercased()
        do { try await log.append(r) } catch { throw AppError.log("\(error)") }
        broadcaster.send(.qsoLogged(r))
        return r
    }

    public func updateQSO(_ r: QSORecord) async throws {
        guard let log else { throw AppError.noLog }
        do { try await log.update(r) } catch { throw AppError.log("\(error)") }
        broadcaster.send(.qsoUpdated(r))
    }

    public func deleteQSO(_ id: UUID) async throws {
        guard let log else { throw AppError.noLog }
        do { try await log.delete(id: id) } catch { throw AppError.log("\(error)") }
        broadcaster.send(.qsoDeleted(id))
    }

    // MARK: Rig a modem

    public func setFrequency(_ hz: Double) async throws { try await engine.setRigFrequency(hz) }
    public func setRigMode(_ m: String) async throws { try await engine.setRigMode(m) }
    public func modemParam(_ id: String) async -> ParameterValue? { await engine.modemParam(id) }
    public func setModemParam(_ id: String, _ v: ParameterValue) async throws { try await engine.setModemParam(id, v) }
    public func modemParams() async -> [String: ParameterValue] { await engine.modemParams() }

    // MARK: Profily

    public func loadProfile(_ slot: Int) async throws {
        guard let profiles else { throw AppError.profile("bez úložiště profilů") }
        let all = profiles.load()
        guard all.indices.contains(slot), let p = all[slot] else { throw AppError.profile("slot \(slot) je prázdný") }
        for (k, v) in p.rtty { try await engine.setModemParam(k, v) }
    }

    public func saveProfile(_ slot: Int, name: String) async throws {
        guard let profiles else { throw AppError.profile("bez úložiště profilů") }
        do { try profiles.save(Profile(name: name, rtty: await engine.modemParams()), slot: slot) }
        catch { throw AppError.profile("\(error)") }
    }

    public func profileList() -> [Profile?] { profiles?.load() ?? [] }

    public func deleteProfile(_ slot: Int) throws {
        guard let profiles else { throw AppError.profile("bez úložiště profilů") }
        do { try profiles.save(nil, slot: slot) } catch { throw AppError.profile("\(error)") }
    }
}
