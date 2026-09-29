// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import DXCC
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
    case unknownField(String), noLog, badMacro(Int), badMessage(Int), profile(String), log(String)
}

public enum AppEvent: Sendable {
    case engine(EngineEvent)
    case qsoChanged(QSOFields)
    case qsoLogged(QSORecord), qsoUpdated(QSORecord), qsoDeleted(UUID)
    /// Parametry modemu se změnily (GUI, API, profil) – aktuální hodnoty.
    case paramsChanged([String: ParameterValue])
    /// Závod: další pořadové číslo se změnilo (po zalogování) – klient ho uloží do nastavení.
    case contestSerial(Int)
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
    public nonisolated let log: QSOLogStore?
    private let profiles: ProfileStore?
    public nonisolated let rxText = TextHistory()
    public nonisolated let txText = TextHistory()
    public private(set) var qso = QSOFields()
    public private(set) var txDisabled = false
    private let broadcaster = AppBroadcaster()
    private var eventTask: Task<Void, Never>?
    private var repeatTask: Task<Void, Never>?

    /// Databáze zemí DXCC (cty.dat); nil = bez zjišťování zemí.
    public nonisolated let countries: CountryDB?

    public init(settings: AppSettings, engine: Engine, log: QSOLogStore?, profiles: ProfileStore? = nil,
                countries: CountryDB? = CountryDB.shared) {
        self.settings = settings; self.engine = engine; self.log = log; self.profiles = profiles
        self.countries = countries
        qso = Self.contestDefaults(settings.contest)
    }

    /// Prázdné QSO okno podle závodního formátu (odesílané číslo nebo pevná výměna).
    static func contestDefaults(_ c: ContestSettings) -> QSOFields {
        var q = QSOFields()
        guard c.enabled else { return q }
        switch c.format {
        case .serial:
            if c.exchange.isEmpty { q.serialSent = c.nextSerial } else { q.exchangeSent = c.exchange }
        case .cqrj: q.exchangeSent = c.exchange
        case .bartg: q.serialSent = c.nextSerial                 // čas se doplní se začátkem QSO
        case .ped: break
        }
        return q
    }

    static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HHmm"; return f
    }()

    public nonisolated func events() -> AsyncStream<AppEvent> { broadcaster.subscribe() }

    /// Pořadí uložených parametrů při startu: kmitočty a typ filtru před zářezy
    /// (CLMS::SetWindow přesune zářez uvnitř okna mark–space do středu).
    static func startupOrder(_ p: [String: ParameterValue]) -> [(String, ParameterValue)] {
        let first = ["baud", "mark", "shift", "reverse", "lmsType", "notchTaps", "twoNotch"]
        let last = ["notchFreq", "notch2Freq", "lms"]
        func rank(_ k: String) -> Int { first.firstIndex(of: k) ?? (last.firstIndex(of: k).map { 100 + $0 } ?? 50) }
        return p.sorted { (rank($0.key), $0.key) < (rank($1.key), $1.key) }
    }

    public func start() async throws {
        for (k, v) in Self.startupOrder(settings.rtty) {
            do { try await engine.setModemParam(k, v) } catch { broadcaster.send(.error("parametr \(k): \(error)")) }
        }
        let stream = engine.events()
        eventTask = Task { [weak self] in
            for await e in stream { await self?.handle(e) }
        }
        try await engine.start()
    }

    public func stop() async {
        stopMacroRepeat()
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
    public func rxNow() async { stopMacroRepeat(); await engine.rxNow() }
    public func send(text: String) async { await engine.send(text: text) }
    public func clearTx() async { await engine.clearTx() }
    public var state: EngineState { get async { await engine.state } }

    public func macroContext() -> MacroContext {
        var c = MacroContext()
        c.myCall = settings.station.call.uppercased()
        c.hisCall = qso.call; c.name = qso.name; c.qth = qso.qth
        // MMTTY: HisRST = co posílám (%r %N), MyRST = co jsem dostal (%s %M); v závodě „599“ + číslo nebo výměna
        c.hisRST = qso.rstSent + Self.exchangeSuffix(qso.serialSent, qso.exchangeSent)
        c.myRST = qso.rstRcvd + Self.exchangeSuffix(qso.serialRcvd, qso.exchangeRcvd)
        c.now = Date()
        c.hisUTCOffsetHours = country(for: qso.call)?.utcOffsetHours
        return c
    }

    /// Část za RST: číslo, výměna, nebo obojí „NNN-výměna“ (MMTTY BARTG „599NNN-HHMM“; %x/%y).
    static func exchangeSuffix(_ serial: Int?, _ exch: String) -> String {
        switch (serial, exch.isEmpty) {
        case (let n?, true): return String(format: "%03d", n)
        case (let n?, false): return String(format: "%03d", n) + "-" + exch
        case (nil, _): return exch
        }
    }

    public func runMacro(index: Int) async throws {
        stopMacroRepeat()
        try await runMacroOnce(index)
        if let sec = settings.macros[index].repeatSeconds, sec > 0 { startRepeat(index, every: sec) }
    }

    private func runMacroOnce(_ index: Int) async throws {
        guard settings.macros.indices.contains(index) else { throw AppError.badMacro(index) }
        let m = MacroEngine.expand(settings.macros[index].text, context: macroContext())
        if txDisabled, m.mode == .send { throw EngineError.pttUnavailable("TX zakázáno (rx_only)") }
        try await engine.sendMacro(m)
    }

    /// CQ smyčka (MMTTY UserTimer): po návratu do RX počkat `every` s a makro zopakovat.
    /// Zastaví ji přijatý znak (někdo odpověděl), stopMacroRepeat() nebo rxNow().
    private func startRepeat(_ index: Int, every sec: Double) {
        let engine = self.engine, rx = rxText
        repeatTask = Task { [weak self] in
            while !Task.isCancelled {
                while await engine.state != .rx, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) }
                let mark = rx.absoluteEnd                 // absolutní – text.clear_rx ji nesníží
                try? await Task.sleep(for: .milliseconds(Int(sec * 1000)))
                if Task.isCancelled || rx.absoluteEnd > mark { break }
                guard await engine.state == .rx else { continue }
                do { try await self?.runMacroOnce(index) } catch { break }
            }
        }
    }

    public func stopMacroRepeat() {
        repeatTask?.cancel(); repeatTask = nil
    }

    public func setMacros(_ m: [Macro]) { settings.macros = m }
    public func setMessages(_ m: [Macro]) { settings.messages = m }

    /// Zpráva ze seznamu (MMTTY MsgList) – odešle se stejně jako makro.
    public func runMessage(index: Int) async throws {
        guard settings.messages.indices.contains(index) else { throw AppError.badMessage(index) }
        stopMacroRepeat()
        let m = MacroEngine.expand(settings.messages[index].text, context: macroContext())
        if txDisabled, m.mode == .send { throw EngineError.pttUnavailable("TX zakázáno (rx_only)") }
        try await engine.sendMacro(m)
    }
    public func setStation(_ st: Station) { settings.station = st }

    // MARK: QSO

    public func setQSOField(_ name: String, _ value: String) throws {
        let v = value.trimmingCharacters(in: .whitespaces)
        switch name {
        case "call":
            qso.call = v.uppercased()
            if !v.isEmpty, qso.timeOn == nil { qso.timeOn = Date() }
            // BARTG: čas začátku QSO jako odesílaná výměna (MMTTY SetHisUTC)
            if !v.isEmpty, settings.contest.enabled, settings.contest.format == .bartg, qso.exchangeSent.isEmpty {
                qso.exchangeSent = Self.hhmm.string(from: qso.timeOn ?? Date())
            }
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
        applyContestDefaults()
        broadcaster.send(.qsoChanged(qso))
    }

    /// Závod: odesílané pořadové číslo (nebo pevná výměna) do prázdného QSO okna.
    private func applyContestDefaults() {
        let d = Self.contestDefaults(settings.contest)
        qso.serialSent = d.serialSent; qso.exchangeSent = d.exchangeSent
    }

    @discardableResult
    public func logQSO() async throws -> QSORecord {
        guard let log else { throw AppError.noLog }
        let qso = self.qso                      // snímek – během await se pole mohou změnit
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
        if let ci = country(for: qso.call) {
            r.country = ci.name; r.continent = ci.continent; r.cqZone = ci.cqZone; r.ituZone = ci.ituZone
        }
        do { try await log.append(r) } catch { throw AppError.log("\(error)") }
        broadcaster.send(.qsoLogged(r))
        if settings.contest.enabled {
            if let n = r.serialSent, n >= settings.contest.nextSerial {
                settings.contest.nextSerial = n + 1
                broadcaster.send(.contestSerial(n + 1))
            }
            // závod: rovnou další spojení s dalším číslem – ale nemazat, co operátor mezitím napsal
            if self.qso == qso { clearQSO() }
            else if settings.contest.sendsSerial, self.qso.serialSent == r.serialSent {
                self.qso.serialSent = settings.contest.nextSerial
                broadcaster.send(.qsoChanged(self.qso))
            }
        }
        return r
    }

    /// Země DXCC pro značku (nil = neznámá nebo /MM).
    public nonisolated func country(for call: String) -> CountryInfo? { countries?.lookup(call) }

    /// Log (volitelně za období) ve formátu Cabrillo s hlavičkou z nastavení stanice a závodu.
    /// `contestOnly` = jen spojení s odeslaným číslem nebo výměnou.
    public func cabrillo(from: Date? = nil, to: Date? = nil, contestOnly: Bool = false) async -> String {
        var recs = await log?.query(from: from, to: to) ?? []
        if contestOnly { recs = recs.filter { $0.serialSent != nil || !($0.exchangeSent ?? "").isEmpty } }
        var h = CabrilloHeader(callsign: settings.station.call, contest: settings.contest.name)
        h.categories = settings.contest.category.split(separator: ";").map(String.init)
        h.locator = settings.station.locator; h.name = settings.station.name
        return Cabrillo.export(recs, header: h)
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
    public func setModemParam(_ id: String, _ v: ParameterValue) async throws {
        try await engine.setModemParam(id, v)
        broadcaster.send(.paramsChanged(await engine.modemParams()))
    }
    public func modemParams() async -> [String: ParameterValue] { await engine.modemParams() }
    /// Zářez na kmitočtu (pravé tlačítko ve spektru jako MMTTY).
    public func notchClick(hz: Double) async {
        // MMTTY: během vysílání se kliky do spektra ignorují
        guard ![.keying, .pttOn, .tx, .drain, .pttOff].contains(await engine.state) else { return }
        await engine.withModem { $0.notchClick(hz: hz) }
        broadcaster.send(.paramsChanged(await engine.modemParams()))
    }

    // MARK: Profily

    public func loadProfile(_ slot: Int) async throws {
        guard let profiles else { throw AppError.profile("bez úložiště profilů") }
        let all = profiles.load()
        guard all.indices.contains(slot), let p = all[slot] else { throw AppError.profile("slot \(slot) je prázdný") }
        for (k, v) in p.rtty { try await engine.setModemParam(k, v) }
        broadcaster.send(.paramsChanged(await engine.modemParams()))
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
