// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import DXCC
import Engine
import Foundation
import Localization
import MacroEngine
import ModemKit
import QSOLog
import RigControl
import Settings

/// Fields of the QSO window.
public struct QSOFields: Codable, Sendable, Equatable {
    public var call = "", name = "", qth = "", locator = ""
    public var rstSent = "599", rstRcvd = "599"
    public var serialSent: Int?, serialRcvd: Int?
    public var exchangeSent = "", exchangeRcvd = "", notes = ""
    public var timeOn: Date?
    /// Manually entered frequency in Hz (without a rig); it stays for further QSOs as well.
    public var frequency: Double?
    /// Fields filled from the call history (field name → value); for the GUI only ("from history"), not written to JSON.
    /// A field counts as filled only as long as it still has this value.
    public var historyFilled: [String: String] = [:]
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case call, name, qth, locator, rstSent, rstRcvd, serialSent, serialRcvd, exchangeSent, exchangeRcvd, notes, timeOn, frequency
    }

    public static let fieldNames = ["call", "name", "qth", "locator", "rstSent", "rstRcvd",
                                    "serialSent", "serialRcvd", "exchangeSent", "exchangeRcvd", "notes", "freq"]

    /// Frequency in kHz for display (without needless zeros).
    public static func kHzString(_ hz: Double?) -> String {
        guard let hz else { return "" }
        var s = String(format: "%.3f", hz / 1000)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
    public func value(_ name: String) -> String? {
        switch name {
        case "call": return call; case "name": return name_
        case "qth": return qth; case "locator": return locator
        case "rstSent": return rstSent; case "rstRcvd": return rstRcvd
        case "serialSent": return serialSent.map(String.init) ?? ""
        case "serialRcvd": return serialRcvd.map(String.init) ?? ""
        case "exchangeSent": return exchangeSent; case "exchangeRcvd": return exchangeRcvd
        case "notes": return notes
        case "freq": return Self.kHzString(frequency)
        default: return nil
        }
    }
    private var name_: String { self.name }
}

public enum AppError: Error, Equatable, Sendable {
    case unknownField(String), noLog, badMacro(Int), badMessage(Int), profile(String), log(String), qtc(String), badValue(String)
    /// The rig is not retuned while transmitting.
    case transmitting
    /// The engine is not running (audio not started / stopped) – the rig is not connected.
    case engineStopped
}

public enum AppEvent: Sendable {
    case engine(EngineEvent)
    case qsoChanged(QSOFields)
    case qsoLogged(QSORecord), qsoUpdated(QSORecord), qsoDeleted(UUID)
    /// The modem parameters have changed (GUI, API, profile) – the current values.
    case paramsChanged([String: ParameterValue])
    /// WAE: the QTC series have changed (one was sent or received).
    case qtcChanged
    /// Contest: the next serial number has changed (after logging) – the client saves it into the settings.
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

/// The application layer above Engine: QSO window, log, macros, text history. Shared by the GUI and the API.
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
    /// Number of handled log requests from a macro (%l) – both successful and unsuccessful (ESM waits for them).
    public private(set) var logRequestsHandled = 0

    /// The DXCC country database (cty.dat); nil = without country lookup.
    public nonisolated let countries: CountryDB?

    /// QTC series (WAE DX Contest); nil = without QTC.
    public nonisolated let qtcStore: QTCStore?
    /// A sent series waiting for the recipient's confirmation (R R ALL OK).
    private var pendingQTC: QTCSeries?
    /// Call history (N1MM Call History); nil = not loaded. Used only when `settings.callHistory.enabled`.
    private var callHistory: CallHistory?
    /// The other station's zone prefilled from DXCC (counts as empty: the history overwrites it, a call change recomputes it).
    private var dxccFilledZone: String?

    public init(settings: AppSettings, engine: Engine, log: QSOLogStore?, profiles: ProfileStore? = nil,
                countries: CountryDB? = CountryDB.shared, qtc: QTCStore? = nil) {
        self.settings = settings; self.engine = engine; self.log = log; self.profiles = profiles
        self.countries = countries; self.qtcStore = qtc
        qso = Self.contestDefaults(settings.contest)
        qso.frequency = settings.log.manualFrequency
        if settings.contest.enabled, settings.contest.sendsOwnZone, qso.exchangeSent.isEmpty,
           let z = countries?.lookup(settings.station.call)?.cqZone {
            qso.exchangeSent = String(z)
        }
    }

    /// An empty QSO window according to the contest format (the sent serial number or a fixed exchange).
    static func contestDefaults(_ c: ContestSettings) -> QSOFields {
        var q = QSOFields()
        guard c.enabled else { return q }
        switch c.format {
        case .serial:
            if c.exchange.isEmpty { q.serialSent = c.nextSerial } else { q.exchangeSent = c.exchange }
        case .cqrj: q.exchangeSent = c.exchange
        case .bartg: q.serialSent = c.nextSerial                 // the time is filled in at the QSO start
        case .ped: break
        case .wae: q.serialSent = c.nextSerial
        case .zone: q.exchangeSent = c.exchange              // empty → fills in my own zone from DXCC
        }
        return q
    }

    static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HHmm"; return f
    }()

    public nonisolated func events() -> AsyncStream<AppEvent> { broadcaster.subscribe() }

    /// Order of the saved parameters at startup: frequencies and filter type before the notches
    /// (CLMS::SetWindow moves a notch inside the mark–space window to the center).
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
            logRequestsHandled += 1
        default: break
        }
        broadcaster.send(.engine(e))
    }

    // MARK: TX/RX

    public func setTxDisabled(_ on: Bool) { txDisabled = on }
    public func tx() async throws {
        if txDisabled { throw EngineError.pttUnavailable(L("TX zakázáno (rx_only)")) }
        lockBARTGTime()
        try await engine.tx()
    }
    public func tune() async throws {
        if txDisabled { throw EngineError.pttUnavailable(L("TX zakázáno (rx_only)")) }
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
        // MMTTY: HisRST = what I send (%r %N), MyRST = what I received (%s %M); in a contest "599" + serial or exchange
        // BARTG: until the QSO start the current time (MMTTY UpdateBARTG every minute)
        let sentExch = isBARTG && qso.exchangeSent.isEmpty ? Self.hhmm.string(from: Date()) : qso.exchangeSent
        c.hisRST = qso.rstSent + Self.exchangeSuffix(qso.serialSent, sentExch)
        c.myRST = qso.rstRcvd + Self.exchangeSuffix(qso.serialRcvd, qso.exchangeRcvd)
        c.now = Date()
        c.hisUTCOffsetHours = country(for: qso.call)?.utcOffsetHours
        return c
    }

    /// Context for DX cluster commands: like `macroContext()` + the station frequency in kHz for `%k` (see `clusterSpotKHz`).
    public func clusterMacroContext() async -> MacroContext {
        var c = macroContext()
        var rigHz: Double?
        if let st = await engine.rigStatus, st.online, let f = st.frequency { rigHz = f }
        let manual = rigHz == nil ? await currentFrequency(manual: qso.frequency) : nil
        c.rigKHz = Self.clusterSpotKHz(rigHz: rigHz, manualHz: manual, offsetHz: settings.spots.offsetHz)
        return c
    }

    /// Frequency for a spot (`%k`, kHz): from the rig = rig − the spot offset (the opposite of `AppModel.useSpot`, which tunes
    /// to spot + offset, the offset clamped the same), so the spot carries the station's RF frequency and not the dial; the manual
    /// QSO frequency is already RF (without a rig the spot frequency goes in directly) – no offset subtracted. nil = unknown or ≤ 0.
    public static func clusterSpotKHz(rigHz: Double?, manualHz: Double?, offsetHz: Double) -> Double? {
        let off = min(max(offsetHz, SpotSettings.offsetRange.lowerBound), SpotSettings.offsetRange.upperBound)
        let hz: Double? = rigHz.map { $0 - off } ?? manualHz
        guard let hz, hz.isFinite, hz > 0 else { return nil }
        return hz / 1000
    }

    private var isBARTG: Bool { settings.contest.enabled && settings.contest.format == .bartg }

    /// BARTG: the first transmission with a call entered = the QSO start → the time is fixed (MMTTY SetHisUTC).
    private func lockBARTGTime() {
        guard isBARTG, !qso.call.isEmpty, qso.exchangeSent.isEmpty else { return }
        qso.exchangeSent = Self.hhmm.string(from: Date())
        broadcaster.send(.qsoChanged(qso))
    }

    /// The part after RST: a serial, an exchange, or both "NNN-exchange" (MMTTY BARTG "599NNN-HHMM"; %x/%y).
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
        if let sec = Macro.validRepeat(settings.macros[index].repeatSeconds) { startRepeat(index, every: sec) }
    }

    private func runMacroOnce(_ index: Int) async throws {
        guard settings.macros.indices.contains(index) else { throw AppError.badMacro(index) }
        lockBARTGTime()
        let m = MacroEngine.expand(settings.macros[index].text, context: macroContext())
        if txDisabled, m.mode == .send { throw EngineError.pttUnavailable(L("TX zakázáno (rx_only)")) }
        try await engine.sendMacro(m)
    }

    /// CQ loop (MMTTY UserTimer): after returning to RX wait `every` s and repeat the macro.
    /// It is stopped by a received character (somebody answered), stopMacroRepeat() or rxNow().
    private func startRepeat(_ index: Int, every sec: Double) {
        let engine = self.engine, rx = rxText
        repeatTask = Task { [weak self] in
            while !Task.isCancelled {
                while await engine.state != .rx, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) }
                let mark = rx.absoluteEnd                 // absolute – text.clear_rx does not lower it
                try? await Task.sleep(for: .seconds(sec))           // sec validated (0.1–3600 s)
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

    /// A message from the list (MMTTY MsgList) – it is sent the same way as a macro.
    public func runMessage(index: Int) async throws {
        guard settings.messages.indices.contains(index) else { throw AppError.badMessage(index) }
        stopMacroRepeat()
        lockBARTGTime()
        let m = MacroEngine.expand(settings.messages[index].text, context: macroContext())
        if txDisabled, m.mode == .send { throw EngineError.pttUnavailable(L("TX zakázáno (rx_only)")) }
        try await engine.sendMacro(m)
    }
    public func setStation(_ st: Station) { settings.station = st }

    // MARK: QSO

    public func setQSOField(_ name: String, _ value: String) throws {
        let v = value.trimmingCharacters(in: .whitespaces)
        switch name {
        case "call":
            let changed = v.uppercased() != qso.call
            qso.call = v.uppercased()
            if !v.isEmpty, qso.timeOn == nil { qso.timeOn = Date() }
            if changed { releaseAutoFilled() }
            // Priority: manual entry > call history > (callbook, in the GUI) > zone guess from DXCC
            applyCallHistory(v)
            // RST + CQ zone: the other station's zone by DXCC (a click on a number in the receive text overwrites it)
            if !v.isEmpty, settings.contest.enabled, settings.contest.prefillsZone, qso.exchangeRcvd.isEmpty,
               let z = country(for: v)?.cqZone {
                qso.exchangeRcvd = String(z)
                dxccFilledZone = String(z)
            }
            // BARTG: a cleared call = the QSO has not started, the time is taken as current again (MMTTY UpdateBARTG)
            if v.isEmpty, isBARTG { qso.exchangeSent = ""; qso.timeOn = nil }
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
        case "freq":
            if v.isEmpty { qso.frequency = nil; break }
            guard let k = Double(v.replacingOccurrences(of: ",", with: ".")), k.isFinite, k > 10, k < 10_000_000
            else { throw AppError.badValue(L("Neplatná frekvence „%@“ (zadejte kHz, např. 14080).", v)) }
            qso.frequency = (k * 1000).rounded()
            manualFrequencySetThisSession = true
        default: throw AppError.unknownField(name)
        }
        if name != "call" {                                // a manual field entry (even with the same value) clears the "from history" mark; a change clears "from DXCC"
            qso.historyFilled[name] = nil
            if name == "exchangeRcvd", qso.exchangeRcvd != dxccFilledZone { dxccFilledZone = nil }
        }
        broadcaster.send(.qsoChanged(qso))
    }

    // MARK: Call history

    /// Sets (or clears) the loaded call history. A change takes effect on the next call change.
    public func setCallHistory(_ h: CallHistory?) { callHistory = h }

    private func setAutoField(_ f: String, _ v: String) {
        switch f {
        case "name": qso.name = v
        case "locator": qso.locator = v
        case "exchangeRcvd": qso.exchangeRcvd = v
        default: break
        }
    }

    /// Call change: values filled automatically (and not edited since) belonged to the old call – they are cleared.
    private func releaseAutoFilled() {
        for (f, val) in qso.historyFilled where qso.value(f) == val { setAutoField(f, "") }
        qso.historyFilled = [:]
        if let z = dxccFilledZone, qso.exchangeRcvd == z { qso.exchangeRcvd = "" }
        dxccFilledZone = nil
    }

    private func applyCallHistory(_ call: String) {
        let cfg = settings.callHistory
        guard cfg.enabled, !call.isEmpty, let hist = callHistory, let e = hist.lookup(call) else { return }
        let country = country(for: call)
        let na = country.map { ["K", "VE"].contains($0.primaryPrefix) }
        for (f, val) in hist.fields(for: e, contest: settings.contest, isNorthAmerica: na) {
            let cur = qso.value(f) ?? ""
            let isDXCC = f == "exchangeRcvd" && !cur.isEmpty && cur == dxccFilledZone
            guard cur.isEmpty || isDXCC || !cfg.fillEmptyOnly else { continue }
            setAutoField(f, val)
            qso.historyFilled[f] = val
            if f == "exchangeRcvd" { dxccFilledZone = nil }
        }
    }

    public func clearQSO() {
        let f = qso.frequency
        qso = QSOFields()
        dxccFilledZone = nil
        qso.frequency = f                                // the band stays for further QSOs
        applyContestDefaults()
        broadcaster.send(.qsoChanged(qso))
    }

    /// Contest: the sent serial number (or a fixed exchange) into an empty QSO window.
    private func applyContestDefaults() {
        let d = Self.contestDefaults(settings.contest)
        qso.serialSent = d.serialSent; qso.exchangeSent = d.exchangeSent
        if settings.contest.enabled, settings.contest.sendsOwnZone, qso.exchangeSent.isEmpty,
           let z = country(for: settings.station.call)?.cqZone {
            qso.exchangeSent = String(z)                      // RST + CQ zone, CQ/RJ: my zone from DXCC
        }
    }

    /// Frequency for the log: the rig if online, otherwise the manually entered one.
    func currentFrequency(manual: Double?) async -> Double? {
        if let st = await engine.rigStatus, st.online, let f = st.frequency { return f }
        // with a rig configured but not responding, only the frequency entered in this session (not an old saved one)
        if settings.rig.type != .none, !manualFrequencySetThisSession { return nil }
        return manual
    }

    /// A manual frequency entered since startup (not just taken from the saved settings).
    private var manualFrequencySetThisSession = false

    /// Dupe in a contest for the call in the QSO window (same station and band since the start; mode only in a custom contest).
    public func dupe() async -> Bool {
        guard settings.contest.enabled, !qso.call.isEmpty, let log else { return false }
        let band = Bands.band(forHz: await currentFrequency(manual: qso.frequency))
        let mode = await engine.currentMode().adifMode
        return DupeCheck.isDupe(call: qso.call, band: band, mode: mode, records: await log.previous(call: qso.call),
                                since: settings.contest.effectiveStart,
                                perMode: DupeCheck.perMode(preset: settings.contest.selectedPreset))
    }

    func updateSettingsForTesting(_ s: AppSettings) { settings = s }

    @discardableResult
    public func logQSO() async throws -> QSORecord {
        guard let log else { throw AppError.noLog }
        lockBARTGTime()
        let qso = self.qso                      // snapshot – the fields may change during await
        guard !qso.call.isEmpty else { throw AppError.log(L("chybí značka")) }
        let now = Date()
        var r = QSORecord(call: qso.call, timeOn: qso.timeOn ?? now, mode: await engine.currentMode().adifMode)
        r.timeOff = now
        r.frequency = await currentFrequency(manual: qso.frequency)
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
            // contest: on to the next QSO with the next serial – but do not erase what the operator typed meanwhile
            if self.qso == qso { clearQSO() }
            else if settings.contest.sendsSerial, self.qso.serialSent == r.serialSent {
                self.qso.serialSent = settings.contest.nextSerial
                if isBARTG { self.qso.exchangeSent = "" }   // do not inherit the logged QSO's time
                broadcaster.send(.qsoChanged(self.qso))
            }
        }
        return r
    }

    // MARK: QTC (WAE DX Contest)

    public struct QTCStatus: Sendable, Equatable {
        public var available: [QTCLine]        // what can be sent to the station
        public var exchanged: Int              // already exchanged (sent + received), max. 10
        public var nextSeries: Int
        public var differentContinent: Bool?   // in RTTY only between continents; nil = unknown continent
        public var points: Int                 // total points for QTC
    }

    private func planner() async -> QTCPlanner {
        QTCPlanner(records: await log?.records ?? [], series: await qtcStore?.series ?? [], since: settings.contest.effectiveStart)
    }

    public func qtcStatus(for call: String) async -> QTCStatus {
        let p = await planner()
        let mine = country(for: settings.station.call)?.continent, his = country(for: call)?.continent
        let diff: Bool? = (mine != nil && his != nil) ? mine != his : nil
        return QTCStatus(available: call.isEmpty ? [] : p.available(for: call), exchanged: p.exchanged(with: call),
                         nextSeries: p.nextSeriesNumber, differentContinent: diff, points: p.points)
    }

    /// Sends a QTC series to the station in the QSO window (it is stored only after `confirmSentQTC`).
    /// It checks the rules: a different continent, the per-pair limit, lines not yet reported and not about this station.
    public func sendQTC(_ lines: [QTCLine]) async throws {
        guard qtcStore != nil else { throw AppError.qtc(L("QTC není k dispozici")) }
        let call = qso.call
        guard !call.isEmpty else { throw AppError.qtc(L("chybí značka protistanice")) }
        guard !lines.isEmpty, lines.count <= QTCPlanner.maxPerPair else { throw AppError.qtc(L("série musí mít 1–10 QTC")) }
        let st = await qtcStatus(for: call)
        if st.differentContinent == false { throw AppError.qtc(L("%@ je na stejném kontinentu – v RTTY QTC nelze", call)) }
        if pendingQTC?.counterpart == call, pendingQTC?.lines == lines {
            // the same series again (before confirmation) – the number and the limits are already checked
        } else {
            guard st.exchanged + lines.count <= QTCPlanner.maxPerPair else { throw AppError.qtc(L("s %@ už vyměněno %ld QTC", call, st.exchanged)) }
            guard Set(lines).isSubset(of: Set(st.available)) else { throw AppError.qtc(L("řádky nejsou pro %@ povolené (už nahlášené nebo o této stanici)", call)) }
        }
        let number = pendingQTC?.counterpart == call ? pendingQTC!.number : st.nextSeries
        let series = QTCSeries(direction: .sent, number: number, counterpart: call, time: Date(),
                               frequency: await engine.rigStatus?.frequency, lines: lines)
        try await sendPlain(QTCText.body(number: number, lines: lines))
        pendingQTC = series                          // only after it has been successfully handed over for transmission
    }

    /// Repeats a line of the sent series (index from 1, on an AGN N request).
    public func repeatQTC(index: Int) async throws {
        guard let p = pendingQTC, (1...p.count).contains(index) else { throw AppError.qtc(L("není co opakovat")) }
        try await sendPlain(QTCText.repeatLine(p.lines[index - 1], index: index))
    }

    /// The recipient confirmed – the series is logged.
    public func confirmSentQTC() async throws {
        guard let p = pendingQTC, let store = qtcStore else { throw AppError.qtc(L("žádná odeslaná série")) }
        do { try await store.append(p) } catch { throw AppError.qtc("\(error)") }
        pendingQTC = nil
        broadcaster.send(.qtcChanged)
    }

    public func cancelSentQTC() { pendingQTC = nil }
    public var pendingQTCSeries: QTCSeries? { pendingQTC }

    /// Stores a received series (the counterpart is passed explicitly – the QSO window may have been cleared meanwhile).
    public func saveReceivedQTC(counterpart: String, number: Int, declaredCount: Int?, lines: [QTCLine]) async throws {
        guard let store = qtcStore else { throw AppError.qtc(L("QTC není k dispozici")) }
        let call = counterpart.uppercased()
        guard !call.isEmpty else { throw AppError.qtc(L("chybí značka protistanice")) }
        guard number > 0, !lines.isEmpty else { throw AppError.qtc(L("prázdná série")) }
        let st = await qtcStatus(for: call)
        if st.differentContinent == false { throw AppError.qtc(L("%@ je na stejném kontinentu – v RTTY QTC nelze", call)) }
        guard st.exchanged + lines.count <= QTCPlanner.maxPerPair else { throw AppError.qtc(L("s %@ už vyměněno %ld QTC", call, st.exchanged)) }
        let s = QTCSeries(direction: .received, number: number, counterpart: call, time: Date(),
                          frequency: await engine.rigStatus?.frequency, lines: lines,
                          declaredCount: declaredCount.flatMap { $0 != lines.count ? $0 : nil })
        do { try await store.append(s) } catch { throw AppError.qtc("\(error)") }
        broadcaster.send(.qtcChanged)
    }

    /// Editing a stored series (the Log → QTC window).
    public func updateQTCSeries(_ s: QTCSeries) async throws {
        guard let store = qtcStore else { throw AppError.qtc(L("QTC není k dispozici")) }
        guard !s.counterpart.isEmpty, !s.lines.isEmpty, s.lines.count <= QTCPlanner.maxPerPair else {
            throw AppError.qtc(L("série musí mít protistanici a 1–10 řádků"))
        }
        do { try await store.update(s) } catch { throw AppError.qtc("\(error)") }
        broadcaster.send(.qtcChanged)
    }

    public func deleteQTCSeries(_ id: UUID) async throws {
        guard let store = qtcStore else { throw AppError.qtc(L("QTC není k dispozici")) }
        do { try await store.delete(id: id) } catch { throw AppError.qtc("\(error)") }
        broadcaster.send(.qtcChanged)
    }

    /// Short QTC operating messages.
    public enum QTCPhrase: Sendable { case ask, qrvQuery, qrv, agn(Int), allOK }
    public func sendQTCPhrase(_ p: QTCPhrase) async throws {
        let c = qso.call.isEmpty ? "" : "\(qso.call) "
        let t: String
        switch p {
        case .ask: t = "\(c)QTC? QTC? BK"
        case .qrvQuery: t = "\(c)QRV? QRV? BK"
        case .qrv: t = "\(c)QRV QRV BK"
        case .agn(let n): t = "\(c)AGN \(n) \(n) BK"
        case .allOK: t = "\(c)R R ALL OK QSL BK"
        }
        try await sendPlain("\r\n" + t + "\r\n")
    }

    // MARK: Sending a text file (MMTTY "Send Text…")

    public enum FileTextError: Error, LocalizedError {
        case empty, tooLong
        public var errorDescription: String? {
            switch self {
            case .empty: return L("Soubor je prázdný.")
            case .tooLong: return L("Soubor je příliš dlouhý (max. 20 000 znaků).")
            }
        }
    }
    static let fileTextLimit = 20_000

    /// File contents → text to transmit: UTF-8 (otherwise Latin-1), CR LF, tab = space, without control characters.
    public static func fileText(_ data: Data) throws -> String {
        guard data.count <= fileTextLimit * 4 else { throw FileTextError.tooLong }
        let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")
        let clean = String(String.UnicodeScalarView(lines.unicodeScalars.filter { $0 == "\n" || !CharacterSet.controlCharacters.contains($0) }))
        guard !clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FileTextError.empty }
        guard clean.count <= fileTextLimit else { throw FileTextError.tooLong }
        return clean.replacingOccurrences(of: "\n", with: "\r\n")
    }

    /// Transmits the text of the file (without macros) and switches to RX once it has been sent.
    public func sendFileText(_ data: Data) async throws { try await sendPlain(Self.fileText(data)) }

    /// Text without macros: transmit and go to RX once it has been sent.
    private func sendPlain(_ text: String) async throws {
        if txDisabled { throw EngineError.pttUnavailable(L("TX zakázáno (rx_only)")) }
        // without MacroEngine.expand: calls in QTC must not be interpreted as variables (%…) or control characters
        try await engine.sendMacro(MacroResult.plain(text, end: .rxAfter))
    }

    /// DXCC country for a call (nil = unknown or /MM).
    public nonisolated func country(for call: String) -> CountryInfo? { countries?.lookup(call) }

    /// The log (optionally for a period) in the Cabrillo format with a header from the station and contest settings.
    /// `contestOnly` = only QSOs with a sent serial number or exchange.
    public func cabrillo(from: Date? = nil, to: Date? = nil, contestOnly: Bool = false) async -> String {
        var recs = await log?.query(from: from, to: to) ?? []
        if contestOnly { recs = recs.filter { $0.serialSent != nil || !($0.exchangeSent ?? "").isEmpty } }
        let qtcFrom = from ?? (settings.contest.enabled ? settings.contest.effectiveStart : nil)
        let qtc = await qtcStore?.series.filter { s in
            (qtcFrom.map { s.time >= $0 } ?? true) && (to.map { s.time <= $0 } ?? true) } ?? []
        var h = CabrilloHeader(callsign: settings.station.call, contest: settings.contest.name)
        h.categories = settings.contest.category.split(separator: ";").map(String.init)
        h.locator = settings.station.locator; h.name = settings.station.name
        return Cabrillo.export(recs, header: h, qtc: qtc)
    }

    public func updateQSO(_ r0: QSORecord) async throws {
        guard let log else { throw AppError.noLog }
        var r = r0
        // a corrected call → look up the DXCC country again
        if let old = await log.records.first(where: { $0.id == r.id }), old.call != r.call {
            let ci = country(for: r.call)
            r.country = ci?.name; r.continent = ci?.continent; r.cqZone = ci?.cqZone; r.ituZone = ci?.ituZone
        }
        do { try await log.update(r) } catch { throw AppError.log("\(error)") }
        broadcaster.send(.qsoUpdated(r))
    }

    public func deleteQSO(_ id: UUID) async throws {
        guard let log else { throw AppError.noLog }
        do { try await log.delete(id: id) } catch { throw AppError.log("\(error)") }
        broadcaster.send(.qsoDeleted(id))
    }

    // MARK: Rig and modem

    /// Retunes the rig. Refuses while transmitting (the transmitter keyed) and with the engine stopped – the state is taken
    /// from the engine, so it applies to both the GUI and the API (the `notchClick` pattern).
    public func setFrequency(_ hz: Double) async throws {
        let st = await engine.state
        if Self.transmittingStates.contains(st) { throw AppError.transmitting }
        if st == .stopped { throw AppError.engineStopped }
        try await engine.setRigFrequency(hz)
    }
    /// Engine states in which the transmitter is keyed or is being keyed.
    public static let transmittingStates: Set<EngineState> = [.keying, .pttOn, .tx, .drain, .pttOff]
    public func setRigMode(_ m: String) async throws { try await engine.setRigMode(m) }
    public func modemParam(_ id: String) async -> ParameterValue? { await engine.modemParam(id) }
    public func setModemParam(_ id: String, _ v: ParameterValue) async throws {
        try await engine.setModemParam(id, v)
        broadcaster.send(.paramsChanged(await engine.modemParams()))
    }
    public func modemParams() async -> [String: ParameterValue] { await engine.modemParams() }
    /// A notch at a frequency (right mouse button in the spectrum as in MMTTY).
    public func notchClick(hz: Double) async {
        // MMTTY: clicks in the spectrum are ignored while transmitting
        guard !Self.transmittingStates.contains(await engine.state) else { return }
        await engine.withModem { $0.notchClick(hz: hz) }
        broadcaster.send(.paramsChanged(await engine.modemParams()))
    }

    // MARK: Profiles

    public func loadProfile(_ slot: Int) async throws {
        guard let profiles else { throw AppError.profile(L("bez úložiště profilů")) }
        let all = profiles.load()
        guard all.indices.contains(slot), let p = all[slot] else { throw AppError.profile(L("slot %ld je prázdný", slot)) }
        for (k, v) in p.rtty { try await engine.setModemParam(k, v) }
        broadcaster.send(.paramsChanged(await engine.modemParams()))
    }

    public func saveProfile(_ slot: Int, name: String) async throws {
        guard let profiles else { throw AppError.profile(L("bez úložiště profilů")) }
        do { try profiles.save(Profile(name: name, rtty: await engine.modemParams()), slot: slot) }
        catch { throw AppError.profile("\(error)") }
    }

    public func profileList() -> [Profile?] { profiles?.load() ?? [] }

    public func deleteProfile(_ slot: Int) throws {
        guard let profiles else { throw AppError.profile(L("bez úložiště profilů")) }
        do { try profiles.save(nil, slot: slot) } catch { throw AppError.profile("\(error)") }
    }
}
