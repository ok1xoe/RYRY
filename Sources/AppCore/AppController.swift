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

/// Pole QSO okna.
public struct QSOFields: Codable, Sendable, Equatable {
    public var call = "", name = "", qth = "", locator = ""
    public var rstSent = "599", rstRcvd = "599"
    public var serialSent: Int?, serialRcvd: Int?
    public var exchangeSent = "", exchangeRcvd = "", notes = ""
    public var timeOn: Date?
    /// Ručně zadaná frekvence v Hz (bez rigu); zůstává i pro další spojení.
    public var frequency: Double?
    public init() {}

    public static let fieldNames = ["call", "name", "qth", "locator", "rstSent", "rstRcvd",
                                    "serialSent", "serialRcvd", "exchangeSent", "exchangeRcvd", "notes", "freq"]

    /// Frekvence v kHz pro zobrazení (bez zbytečných nul).
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
}

public enum AppEvent: Sendable {
    case engine(EngineEvent)
    case qsoChanged(QSOFields)
    case qsoLogged(QSORecord), qsoUpdated(QSORecord), qsoDeleted(UUID)
    /// Parametry modemu se změnily (GUI, API, profil) – aktuální hodnoty.
    case paramsChanged([String: ParameterValue])
    /// WAE: série QTC se změnily (odeslána nebo přijata).
    case qtcChanged
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
    /// Počet vyřízených požadavků na zalogování z makra (%l) – úspěšných i neúspěšných (ESM na ně čeká).
    public private(set) var logRequestsHandled = 0

    /// Databáze zemí DXCC (cty.dat); nil = bez zjišťování zemí.
    public nonisolated let countries: CountryDB?

    /// Série QTC (WAE DX Contest); nil = bez QTC.
    public nonisolated let qtcStore: QTCStore?
    /// Odeslaná série čekající na potvrzení příjemce (R R ALL OK).
    private var pendingQTC: QTCSeries?

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
        case .wae: q.serialSent = c.nextSerial
        case .zone: q.exchangeSent = c.exchange              // prázdné → doplní vlastní zónu z DXCC
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
        // MMTTY: HisRST = co posílám (%r %N), MyRST = co jsem dostal (%s %M); v závodě „599“ + číslo nebo výměna
        // BARTG: do začátku QSO aktuální čas (MMTTY UpdateBARTG každou minutu)
        let sentExch = isBARTG && qso.exchangeSent.isEmpty ? Self.hhmm.string(from: Date()) : qso.exchangeSent
        c.hisRST = qso.rstSent + Self.exchangeSuffix(qso.serialSent, sentExch)
        c.myRST = qso.rstRcvd + Self.exchangeSuffix(qso.serialRcvd, qso.exchangeRcvd)
        c.now = Date()
        c.hisUTCOffsetHours = country(for: qso.call)?.utcOffsetHours
        return c
    }

    private var isBARTG: Bool { settings.contest.enabled && settings.contest.format == .bartg }

    /// BARTG: první vysílání se zadanou značkou = začátek QSO → čas se zafixuje (MMTTY SetHisUTC).
    private func lockBARTGTime() {
        guard isBARTG, !qso.call.isEmpty, qso.exchangeSent.isEmpty else { return }
        qso.exchangeSent = Self.hhmm.string(from: Date())
        broadcaster.send(.qsoChanged(qso))
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
        if let sec = Macro.validRepeat(settings.macros[index].repeatSeconds) { startRepeat(index, every: sec) }
    }

    private func runMacroOnce(_ index: Int) async throws {
        guard settings.macros.indices.contains(index) else { throw AppError.badMacro(index) }
        lockBARTGTime()
        let m = MacroEngine.expand(settings.macros[index].text, context: macroContext())
        if txDisabled, m.mode == .send { throw EngineError.pttUnavailable(L("TX zakázáno (rx_only)")) }
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
                try? await Task.sleep(for: .seconds(sec))           // sec ověřené (0,1–3600 s)
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
            qso.call = v.uppercased()
            if !v.isEmpty, qso.timeOn == nil { qso.timeOn = Date() }
            // RST + CQ zóna: zóna protistanice podle DXCC (klik na číslo v příjmu ji přepíše)
            if !v.isEmpty, settings.contest.enabled, settings.contest.prefillsZone, qso.exchangeRcvd.isEmpty,
               let z = country(for: v)?.cqZone {
                qso.exchangeRcvd = String(z)
            }
            // BARTG: smazaná značka = QSO nezačalo, čas se znovu bere aktuální (MMTTY UpdateBARTG)
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
        broadcaster.send(.qsoChanged(qso))
    }

    public func clearQSO() {
        let f = qso.frequency
        qso = QSOFields()
        qso.frequency = f                                // pásmo zůstává pro další spojení
        applyContestDefaults()
        broadcaster.send(.qsoChanged(qso))
    }

    /// Závod: odesílané pořadové číslo (nebo pevná výměna) do prázdného QSO okna.
    private func applyContestDefaults() {
        let d = Self.contestDefaults(settings.contest)
        qso.serialSent = d.serialSent; qso.exchangeSent = d.exchangeSent
        if settings.contest.enabled, settings.contest.sendsOwnZone, qso.exchangeSent.isEmpty,
           let z = country(for: settings.station.call)?.cqZone {
            qso.exchangeSent = String(z)                      // RST + CQ zóna, CQ/RJ: moje zóna z DXCC
        }
    }

    /// Frekvence pro log: rig online, jinak ručně zadaná.
    func currentFrequency(manual: Double?) async -> Double? {
        if let st = await engine.rigStatus, st.online, let f = st.frequency { return f }
        // s nastaveným rigem, který zrovna neodpovídá, jen frekvenci zadanou v této relaci (ne starou uloženou)
        if settings.rig.type != .none, !manualFrequencySetThisSession { return nil }
        return manual
    }

    /// Ruční frekvence zadaná od startu (ne jen převzatá z uloženého nastavení).
    private var manualFrequencySetThisSession = false

    /// Duplicita v závodě pro značku v QSO okně (stejná stanice, pásmo a mód od začátku závodu).
    public func dupe() async -> Bool {
        guard settings.contest.enabled, !qso.call.isEmpty, let log else { return false }
        let band = Bands.band(forHz: await currentFrequency(manual: qso.frequency))
        let mode = await engine.currentMode().adifMode
        return DupeCheck.isDupe(call: qso.call, band: band, mode: mode, records: await log.previous(call: qso.call),
                                since: settings.contest.effectiveStart)
    }

    func updateSettingsForTesting(_ s: AppSettings) { settings = s }

    @discardableResult
    public func logQSO() async throws -> QSORecord {
        guard let log else { throw AppError.noLog }
        lockBARTGTime()
        let qso = self.qso                      // snímek – během await se pole mohou změnit
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
            // závod: rovnou další spojení s dalším číslem – ale nemazat, co operátor mezitím napsal
            if self.qso == qso { clearQSO() }
            else if settings.contest.sendsSerial, self.qso.serialSent == r.serialSent {
                self.qso.serialSent = settings.contest.nextSerial
                if isBARTG { self.qso.exchangeSent = "" }   // čas zalogovaného QSO nedědit
                broadcaster.send(.qsoChanged(self.qso))
            }
        }
        return r
    }

    // MARK: QTC (WAE DX Contest)

    public struct QTCStatus: Sendable, Equatable {
        public var available: [QTCLine]        // co lze stanici poslat
        public var exchanged: Int              // už vyměněno (odeslaná + přijatá), max. 10
        public var nextSeries: Int
        public var differentContinent: Bool?   // v RTTY jen mezi kontinenty; nil = neznámý kontinent
        public var points: Int                 // body za QTC celkem
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

    /// Odešle sérii QTC stanici v QSO okně (uloží se až po `confirmSentQTC`).
    /// Kontroluje pravidla: jiný kontinent, limit dvojice, řádky nenahlášené a ne o této stanici.
    public func sendQTC(_ lines: [QTCLine]) async throws {
        guard qtcStore != nil else { throw AppError.qtc(L("QTC není k dispozici")) }
        let call = qso.call
        guard !call.isEmpty else { throw AppError.qtc(L("chybí značka protistanice")) }
        guard !lines.isEmpty, lines.count <= QTCPlanner.maxPerPair else { throw AppError.qtc(L("série musí mít 1–10 QTC")) }
        let st = await qtcStatus(for: call)
        if st.differentContinent == false { throw AppError.qtc(L("%@ je na stejném kontinentu – v RTTY QTC nelze", call)) }
        if pendingQTC?.counterpart == call, pendingQTC?.lines == lines {
            // stejná série znovu (před potvrzením) – číslo i limity už ověřené
        } else {
            guard st.exchanged + lines.count <= QTCPlanner.maxPerPair else { throw AppError.qtc(L("s %@ už vyměněno %ld QTC", call, st.exchanged)) }
            guard Set(lines).isSubset(of: Set(st.available)) else { throw AppError.qtc(L("řádky nejsou pro %@ povolené (už nahlášené nebo o této stanici)", call)) }
        }
        let number = pendingQTC?.counterpart == call ? pendingQTC!.number : st.nextSeries
        let series = QTCSeries(direction: .sent, number: number, counterpart: call, time: Date(),
                               frequency: await engine.rigStatus?.frequency, lines: lines)
        try await sendPlain(QTCText.body(number: number, lines: lines))
        pendingQTC = series                          // až po úspěšném předání k vysílání
    }

    /// Zopakuje řádek odesílané série (index od 1, na žádost AGN N).
    public func repeatQTC(index: Int) async throws {
        guard let p = pendingQTC, (1...p.count).contains(index) else { throw AppError.qtc(L("není co opakovat")) }
        try await sendPlain(QTCText.repeatLine(p.lines[index - 1], index: index))
    }

    /// Příjemce potvrdil – série se zaloguje.
    public func confirmSentQTC() async throws {
        guard let p = pendingQTC, let store = qtcStore else { throw AppError.qtc(L("žádná odeslaná série")) }
        do { try await store.append(p) } catch { throw AppError.qtc("\(error)") }
        pendingQTC = nil
        broadcaster.send(.qtcChanged)
    }

    public func cancelSentQTC() { pendingQTC = nil }
    public var pendingQTCSeries: QTCSeries? { pendingQTC }

    /// Uloží přijatou sérii (protistanice se předává explicitně – QSO okno se mezitím mohlo vyčistit).
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

    /// Oprava uložené série (okno Log → QTC).
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

    /// Krátké provozní zprávy QTC.
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

    // MARK: Odeslání textového souboru (MMTTY „Send Text…“)

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

    /// Obsah souboru → text k vysílání: UTF-8 (jinak Latin-1), CR LF, tabulátor = mezera, bez řídicích znaků.
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

    /// Vyšle text souboru (bez maker) a po dovysílání přejde na RX.
    public func sendFileText(_ data: Data) async throws { try await sendPlain(Self.fileText(data)) }

    /// Text bez maker: vysílat a po dovysílání RX.
    private func sendPlain(_ text: String) async throws {
        if txDisabled { throw EngineError.pttUnavailable(L("TX zakázáno (rx_only)")) }
        // bez MacroEngine.expand: značky v QTC se nesmí vykládat jako proměnné (%…) ani řídicí znaky
        try await engine.sendMacro(MacroResult.plain(text, end: .rxAfter))
    }

    /// Země DXCC pro značku (nil = neznámá nebo /MM).
    public nonisolated func country(for call: String) -> CountryInfo? { countries?.lookup(call) }

    /// Log (volitelně za období) ve formátu Cabrillo s hlavičkou z nastavení stanice a závodu.
    /// `contestOnly` = jen spojení s odeslaným číslem nebo výměnou.
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
        // opravená značka → znovu zjistit zemi DXCC
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
