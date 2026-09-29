// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import APIServer
import AVFoundation
import AppCore
import DXCC
import AudioIO
import Engine
import Foundation
import Keying
import ModemKit
import Observation
import OSLog
import QSOLog
import RigControl
import RTTYModem
import Settings
import WaveFile

public struct RxRun: Equatable, Sendable, Identifiable {
    public let id: Int
    public var text: String
    public var echo: Bool
}

public enum SendMode: String, CaseIterable, Sendable { case char, word, line }

public extension AppSettings {
    /// Konfigurace jádra RTTY (vyžaduje nový modem, tj. restart Engine).
    func modemConfig() -> RTTYModem.Config {
        var c = RTTYModem.Config()
        c.codeSet = rttyCore.japanese ? .japanese : .us
        c.doubleShift = rttyCore.doubleShift
        c.txUOS = rttyCore.txUOS
        c.rxClockPPM = clock.clampedRx
        c.txClockPPM = clock.clampedTx
        return c
    }
}

/// Výchozí parametry modemu (pro rozhodnutí, co ukládat do nastavení).
enum AppDefaults {
    static let rtty: [String: ParameterValue] = {
        guard let m = try? RTTYModem() else { return [:] }
        var d: [String: ParameterValue] = [:]
        for p in m.parameters { d[p.id] = p.defaultValue }
        return d
    }()
}

/// Stav a akce pro GUI. Veškerá logika je v AppController/Engine, tady jen propojení a odvozený stav.
@MainActor @Observable
public final class AppModel {
    public static let rxLimit = 200_000

    public typealias EngineFactory = @MainActor (AppSettings, Rig) -> Engine

    private let settingsStore: SettingsStore
    private let profileStore: ProfileStore
    private let engineFactory: EngineFactory
    private let spectrumFPS: Double

    public private(set) var settings: AppSettings
    public private(set) var state: EngineState = .stopped
    public private(set) var rxRuns: [RxRun] = []
    public private(set) var rxCharCount = 0
    /// Absolutní počitadla pro inkrementální zobrazení (co přibylo na konec / co se ořízlo zepředu).
    public private(set) var rxAppendedTotal = 0
    public private(set) var rxTrimmedTotal = 0
    private var nextRunId = 0
    public var txDraft = ""
    public var sendMode: SendMode = .word
    public private(set) var signalLevel = 0.0
    public private(set) var squelchOpen = true
    public private(set) var mark = 2125.0
    public private(set) var space = 2295.0
    public private(set) var fig = false
    public private(set) var rig: RigStatus?
    public private(set) var qso = QSOFields()
    public private(set) var previousQSOs: [QSORecord] = []
    public private(set) var logRecords: [QSORecord] = []
    public private(set) var messages: [String] = []
    public private(set) var apiStatus = ""
    public private(set) var waterfall = WaterfallRenderer(width: 600, height: 200)
    public private(set) var params: [String: ParameterValue] = [:]
    public private(set) var descriptors: [ParameterDescriptor] = []
    public private(set) var profileNames: [String?] = []
    public private(set) var xyPoints: [XYPoint] = []
    public private(set) var xyEnabled = false
    /// Scope demodulátoru (okno „Scope“): poslední dávka, zdroj 0–3, zmrazení (jednorázový záznam).
    public private(set) var demodScope: DemodScope?
    public private(set) var demodScopeEnabled = false
    public var scopeSource = 2
    public var scopeFrozen = false
    private var sqTarget: Double?
    private var sqChain: Task<Void, Never>?
    var lastSentForTesting = ""
    private let logger = Logger(subsystem: "cz.ok1xoe.mmtty4mac", category: "app")
    static let micWaitMessage = "Čekám na povolení přístupu k mikrofonu (systémový dialog)…"
    public var waterfallFromHz: Double { settings.display.fromHz }
    public var waterfallToHz: Double { settings.display.toHz }

    /// Zobrazení (rozsah, zesílení, písmo, časové značky) – bez restartu, hned uloží.
    public func setDisplay(_ change: (inout DisplaySettings) -> Void) async {
        var d = settings.display
        change(&d)
        if !(d.fromHz >= 0 && d.toHz <= DisplaySettings.maxHz && d.toHz - d.fromHz >= 200) { d.fromHz = settings.display.fromHz; d.toHz = settings.display.toHz }
        d.gainDB = min(30, max(-30, d.gainDB))
        settings.display = d
        syncDisplay()
        do { try settingsStore.save(settings) } catch { note("Nastavení nelze uložit: \(error)") }
    }

    private func syncDisplay() {
        waterfall.gainDB = settings.display.gainDB
        waterfall.autoGain = settings.display.autoGain
    }

    public private(set) var app: AppController?
    private var fldigi: FldigiXMLRPCServer?
    private var json: JSONRPCServer?
    private var eventTask: Task<Void, Never>?
    private var spectrumTask: Task<Void, Never>?
    /// Start/stop/applySettings běží postupně (jinak by vznikaly osiřelé enginy s otevřeným PTT portem).
    private var lifecycle: Task<Void, Never>?

    private func serialized(_ op: @escaping @MainActor () async -> Void) async {
        let prev = lifecycle
        let t = Task { @MainActor in await prev?.value; await op() }
        lifecycle = t
        await t.value
    }

    public init(settingsStore: SettingsStore = SettingsStore(), profileStore: ProfileStore = ProfileStore(),
                engineFactory: EngineFactory? = nil, spectrumFPS: Double = 15) {
        self.settingsStore = settingsStore; self.profileStore = profileStore
        self.engineFactory = engineFactory ?? AppModel.realEngine
        self.spectrumFPS = spectrumFPS
        let (s, w) = settingsStore.load()
        settings = s
        messages = w
        syncDisplay()
    }

    /// Stav oprávnění k mikrofonu; při prvním spuštění se zeptá (asynchronně).
    nonisolated static func microphoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    public static func makeRig(_ r: RigSettings) -> Rig {
        switch r.type {
        case .hamlib: return HamlibClient(host: r.host, port: UInt16(clamping: r.effectivePort))
        case .flrig: return FlrigClient(host: r.host, port: r.effectivePort)
        case .none: return NoRig()
        }
    }

    public static let realEngine: EngineFactory = { s, rig in
        // RTTYModem na 11025 Hz (± 2 % korekce hodin) nemůže selhat
        Engine(modem: try! RTTYModem(config: s.modemConfig()), rig: rig, audio: CoreAudioBackend(), config: s.engineConfig())
    }

    func noteForTesting(_ m: String) { note(m) }

    private func note(_ m: String) {
        logger.notice("\(m, privacy: .public)")
        messages.append(m)
        if messages.count > 50 { messages.removeFirst(messages.count - 50) }
    }

    // MARK: Start/stop

    public func start() async { await serialized { [weak self] in await self?.startNow() } }

    private func startNow() async {
        guard app == nil else { return }                 // už běží
        let rig = Self.makeRig(settings.rig)
        let engine = engineFactory(settings, rig)
        let log: QSOLogStore?
        do { log = try QSOLogStore(directory: URL(fileURLWithPath: settings.log.directory)) }
        catch { log = nil; note("Log nedostupný: \(error)") }
        if let log { for w in await log.warnings { note(w) } }
        let app = AppController(settings: settings, engine: engine, log: log, profiles: profileStore)
        self.app = app
        let events = app.events()
        eventTask = Task { [weak self] in
            for await e in events { self?.handle(e) }
        }
        await refreshParams()
        // Oprávnění k mikrofonu vyžádat předem (jinak spuštění zvukového vstupu čeká na dialog).
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            note(Self.micWaitMessage)
        }
        let micOK = await Self.microphoneAccess()
        messages.removeAll { $0 == Self.micWaitMessage }       // dialog vyřízen
        if !micOK {
            note("Přístup k mikrofonu zamítnut – povolte ho v Nastavení systému → Soukromí → Mikrofon. Příjem nefunguje.")
        }
        do { try await app.start() }
        catch EngineError.audio(let m) { note("Zvuk nefunguje: \(m) – zkontrolujte zařízení a oprávnění k mikrofonu") }
        catch { note("Start selhal: \(error)") }
        qso = await app.qso                              // např. odesílané číslo závodu
        state = await engine.state
        await refreshParams()
        if let log { logRecords = await log.query() }
        profileNames = profileStore.load().map { $0?.name }
        if xyEnabled { await engine.setXYScope(true) }
        if demodScopeEnabled { await engine.setDemodScope(true) }
        let st = await engine.state
        logger.info("start: stav \(st.rawValue, privacy: .public)")
        await startAPIs(app)
        startSpectrum(engine)
    }

    private func startAPIs(_ app: AppController) async {
        let host = settings.api.allowRemote ? "0.0.0.0" : "127.0.0.1"
        var parts: [String] = []
        if settings.api.fldigiEnabled {
            let s = FldigiXMLRPCServer(app: app, host: host, port: UInt16(clamping: settings.api.fldigiPort))
            do { let p = try await s.start(); fldigi = s; parts.append("fldigi XML-RPC :\(p)") }
            catch { note("fldigi XML-RPC nespuštěno (port \(settings.api.fldigiPort) obsazen?): \(error)") }
        }
        if settings.api.jsonRPCEnabled {
            let s = JSONRPCServer(app: app, host: host, port: UInt16(clamping: settings.api.jsonRPCPort))
            do { let p = try await s.start(); json = s; parts.append("JSON-RPC :\(p)") }
            catch { note("JSON-RPC nespuštěno (port \(settings.api.jsonRPCPort) obsazen?): \(error)") }
        }
        apiStatus = parts.isEmpty ? "API vypnuto" : parts.joined(separator: " · ")
    }

    private func startSpectrum(_ engine: Engine) {
        guard spectrumFPS > 0 else { return }
        let interval = Int(1000 / spectrumFPS)
        spectrumTask = Task { [weak self] in
            while !Task.isCancelled {
                if let f = await engine.spectrum(), let self {
                    self.waterfall.push(f, fromHz: self.waterfallFromHz, toHz: self.waterfallToHz)
                    if self.xyEnabled, let pts = await engine.xyScope() { self.xyPoints = pts }
                    await self.pollDemodScope()
                }
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
    }

    public func stop() async { await serialized { [weak self] in await self?.stopNow() } }

    /// Ukončení aplikace: okamžitě RX (PTT off), pak stop s časovým limitem – ⌘Q nesmí viset.
    public func shutdown(timeout: Duration = .seconds(3)) async {
        await app?.rxNow()
        let stopper = Task { @MainActor in await self.stop() }
        await withTaskGroup(of: Void.self) { g in
            g.addTask { await stopper.value }
            g.addTask { try? await Task.sleep(for: timeout) }
            await g.next(); g.cancelAll()
        }
    }

    private func stopNow() async {
        await stopWAV()
        spectrumTask?.cancel(); spectrumTask = nil
        fldigi?.stop(); json?.stop(); fldigi = nil; json = nil
        await app?.stop()
        await eventTask?.value
        eventTask = nil
        app = nil
        state = .stopped
    }

    /// Uloží nastavení a restartuje (Engine je jednorázový). Během vysílání nejdřív bezpečně RX.
    /// Sekce z dialogu Nastavení se sloučí do aktuálního nastavení; parametry modemu a makra
    /// (mění se jinde, okamžitě) se nepřepisují starou kopií z dialogu.
    /// Použije nastavení z dialogu. `baseline` = stav, ze kterého dialog vyšel: pořadové číslo závodu
    /// a zobrazení se mění i jinde (log, rychlé menu), proto se převezmou jen pole, která uživatel změnil.
    public func applySettings(_ s: AppSettings, baseline: AppSettings? = nil) async {
        await serialized { [weak self] in
            guard let self else { return }
            let base = baseline ?? self.settings
            func merge(_ cur: AppSettings) -> AppSettings {
                var m = cur
                m.station = s.station; m.audio = s.audio; m.ptt = s.ptt; m.fsk = s.fsk
                m.rig = s.rig; m.api = s.api; m.log = s.log
                m.clock = s.clock; m.rttyCore = s.rttyCore
                func take<T: Equatable>(_ kp: WritableKeyPath<AppSettings, T>) { if s[keyPath: kp] != base[keyPath: kp] { m[keyPath: kp] = s[keyPath: kp] } }
                take(\.display.fromHz); take(\.display.toHz); take(\.display.gainDB); take(\.display.autoGain)
                take(\.display.timestamps); take(\.display.fontSize)
                take(\.contest.enabled); take(\.contest.format); take(\.contest.name); take(\.contest.category); take(\.contest.exchange)
                take(\.contest.nextSerial)
                return m
            }
            do { try self.settingsStore.save(merge(self.settings)) } catch { self.note("Nastavení nelze uložit: \(error)") }
            if let app = self.app, await app.engine.state != .rx { await app.rxNow() }
            await self.stopNow()
            // znovu sloučit: během zastavování mohl přijít .contestSerial (makro s %l)
            let merged = merge(self.settings)
            do { try self.settingsStore.save(merged) } catch { self.note("Nastavení nelze uložit: \(error)") }
            self.settings = merged
            self.syncDisplay()
            await self.startNow()
        }
    }

    // MARK: Události

    private func handle(_ e: AppEvent) {
        switch e {
        case .engine(.state(let s)):
            let prev = state
            state = s
            // MMTTY „Time stamp“: UTC čas při přepnutí na TX a zpět
            if settings.display.timestamps, prev != s {
                if prev == .rx, s != .stopped { appendRx("\r\n[\(Self.stampFmt.string(from: Date())) UTC TX]\r\n", echo: true) }
                else if s == .rx, prev != .stopped { appendRx("\r\n[\(Self.stampFmt.string(from: Date())) UTC RX]\r\n", echo: false) }
            }
            if s == .tx, !txDraft.isEmpty { Task { await self.sendDraft(mode: self.sendMode) } }   // rozepsaný text hned vysílat
        case .engine(.modem(.rxText(let c, let echo))): appendRx(String(c), echo: echo)
        case .engine(.modem(.signal(let l, let sq))): signalLevel = l; squelchOpen = sq
        case .engine(.modem(.tuning(let t))): mark = t.mark; space = t.space
        case .engine(.modem(.shift(let f))): fig = f
        case .engine(.rig(let r)): rig = r
        case .engine(.error(let err)): note("\(err)")
        case .engine(.pttTimeout): note("PTT časovač vypnul vysílání")
        case .error(let m): note(m)
        case .qsoChanged(let q):
            let callChanged = q.call != qso.call
            qso = q
            if callChanged { Task { await self.refreshPrevious() } }
        case .qsoLogged(let r): logRecords.insert(r, at: 0); Task { await self.refreshPrevious() }
        case .contestSerial(let n):
            settings.contest.nextSerial = n
            do { try settingsStore.save(settings) } catch { note("Nastavení nelze uložit: \(error)") }
        case .qsoUpdated, .qsoDeleted: Task { await self.refreshLog() }
        case .paramsChanged(let p):
            params = p
            if case .double(let m)? = p["mark"] { mark = m }
            if case .double(let sh)? = p["shift"] { space = mark + sh }
            // uložit jen parametry, které uživatel mění (stejné klíče jako dosud v nastavení + změněné)
            var r = settings.rtty
            for (k, v) in p where r[k] != nil || AppDefaults.rtty[k] != v { r[k] = v }
            if r != settings.rtty { settings.rtty = r; try? settingsStore.save(settings) }
        default: break
        }
    }

    public func appendRx(_ s: String, echo: Bool) {
        if var last = rxRuns.last, last.echo == echo {
            last.text += s; rxRuns[rxRuns.count - 1] = last
        } else {
            rxRuns.append(RxRun(id: nextRunId, text: s, echo: echo)); nextRunId += 1
        }
        rxCharCount += s.count
        rxAppendedTotal += s.count
        while rxCharCount > Self.rxLimit, !rxRuns.isEmpty {
            let over = rxCharCount - Self.rxLimit
            if rxRuns[0].text.count <= over {
                let n = rxRuns[0].text.count
                rxCharCount -= n; rxTrimmedTotal += n; rxRuns.removeFirst()
            } else {
                rxRuns[0].text.removeFirst(over); rxCharCount -= over; rxTrimmedTotal += over
            }
        }
    }

    /// Posledních `n` znaků jako úseky (text, echo) – pro doplnění konce zobrazení.
    public func rxTail(_ n: Int) -> [RxRun] {
        var need = max(0, n)
        var out: [RxRun] = []
        for r in rxRuns.reversed() where need > 0 {
            let take = min(need, r.text.count)
            out.append(RxRun(id: r.id, text: String(r.text.suffix(take)), echo: r.echo))
            need -= take
        }
        return out.reversed()
    }

    public var rxPlainText: String { rxRuns.map(\.text).joined() }
    public func clearRx() { rxTrimmedTotal += rxCharCount; rxRuns.removeAll(); rxCharCount = 0 }

    private func refreshPrevious() async {
        guard let log = app?.log, !qso.call.isEmpty else { previousQSOs = []; return }
        previousQSOs = await log.previous(call: qso.call)
    }

    static let stampFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HH:mm:ss"; return f
    }()

    // MARK: Přehrání WAV do příjmu (MMTTY „Play“)

    public private(set) var wavPlaying = false
    private var wavTask: Task<Void, Never>?
    private var wavToken = UUID()
    /// Max. délka souboru (vzorky po převzorkování na 11025 Hz ≈ 2 h).
    nonisolated static let wavMaxSamples = 11025 * 7200

    public enum WAVError: Error, LocalizedError {
        case tooLong
        public var errorDescription: String? { "Soubor je delší než 2 hodiny." }
    }

    /// Přehraje WAV (libovolná frekvence, převzorkuje se na 11025 Hz) místo vstupu zvukovky (MMTTY „Play“).
    /// `speed` 1 = reálný čas, 2–10 = rychleji, 0 = co nejrychleji. Během TX se pozastaví.
    public func playWAV(_ url: URL, speed: Double = 1) async throws {
        await stopWAV()
        guard let engine = app?.engine else { return }
        let samples = try await Task.detached(priority: .userInitiated) { () throws -> [Float] in
            let (raw, rate) = try WaveFile.read(from: url)
            guard Double(raw.count) / Double(max(1, rate)) * 11025 <= Double(AppModel.wavMaxSamples) else { throw WAVError.tooLong }
            return rate == 11025 ? raw : try SampleRateConverter(from: Double(rate), to: 11025).process(raw)
        }.value
        await engine.startPlayback(samples, speed: speed)
        wavPlaying = true
        let token = UUID(); wavToken = token
        wavTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                if await engine.playbackRemaining == 0 { break }
            }
            if let self, self.wavToken == token { self.wavPlaying = false }
        }
    }

    public func stopWAV() async {
        wavTask?.cancel(); wavTask = nil
        wavToken = UUID()
        wavPlaying = false
        await app?.engine.stopPlayback()
    }

    /// Země DXCC aktuální značky v QSO okně (nil = neznámá).
    public var dxcc: CountryInfo? { qso.call.isEmpty ? nil : app?.country(for: qso.call) }

    /// Log (volitelně za období) ve formátu Cabrillo s hlavičkou z nastavení stanice a závodu.
    public func cabrilloText(from: Date? = nil, to: Date? = nil, contestOnly: Bool = false) async -> String {
        await app?.cabrillo(from: from, to: to, contestOnly: contestOnly) ?? ""
    }

    private func refreshLog() async {
        guard let log = app?.log else { return }
        logRecords = await log.query()
    }

    private func refreshParams() async {
        guard let app else { return }
        params = await app.modemParams()
        descriptors = await app.engine.parameterDescriptors()
        if case .double(let m)? = params["mark"] { mark = m }
        if case .double(let sh)? = params["shift"] { space = mark + sh }
    }

    // MARK: Akce

    private func run(_ what: String, _ f: () async throws -> Void) async {
        do { try await f() } catch { note("\(what): \(error)") }
    }

    public func toggleTx() async {
        guard let app else { return }
        if state == .rx { await run("TX") { try await app.tx() } } else { await app.rx() }
    }

    public func rxNow() async { await app?.rxNow() }
    public func tune() async { guard let app else { return }; await run("Tune") { try await app.tune() } }
    public func runMacro(_ i: Int) async { guard let app else { return }; await run("Makro F\(i + 1)") { try await app.runMacro(index: i) } }
    public func stopMacro() async { await app?.stopMacroRepeat() }
    public func runMessage(_ i: Int) async {
        guard let app else { return }
        let name = settings.messages.indices.contains(i) ? settings.messages[i].name : "\(i + 1)"
        await run("Zpráva \(name)") { try await app.runMessage(index: i) }
    }

    /// Odešle z editoru část podle režimu (znak = vše, slovo = do poslední mezery, řádek = do posledního konce řádku).
    public func sendDraft(mode: SendMode) async {
        guard let app else { return }
        if txDraft.unicodeScalars.contains("\r") { txDraft = txDraft.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") }
        var cut = txDraft.endIndex
        switch mode {
        case .char: break
        case .word: cut = txDraft.lastIndex(where: { $0 == " " || $0 == "\n" }).map { txDraft.index(after: $0) } ?? txDraft.startIndex
        case .line: cut = txDraft.lastIndex(of: "\n").map { txDraft.index(after: $0) } ?? txDraft.startIndex
        }
        let part = String(txDraft[..<cut])
        guard !part.isEmpty else { return }
        txDraft = String(txDraft[cut...])
        let out = part.replacingOccurrences(of: "\n", with: "\r\n")
        lastSentForTesting = out
        await app.send(text: out)
    }

    public func param(_ id: String) -> ParameterValue? { params[id] }

    public func setParam(_ id: String, _ v: ParameterValue) async {
        guard let app else { return }
        await run("Parametr \(id)") { try await app.setModemParam(id, v) }
        await refreshParams()
        settings.rtty[id] = v
        try? settingsStore.save(settings)
    }

    /// Zdroj nominální a skutečné frekvence zařízení (UID, vstup?) – v testech náhrada.
    public var clockRates: (String?, Bool) -> (nominal: Double, actual: Double)? = { uid, input in
        ClockCalibration.rates(deviceUID: uid, input: input)
    }

    /// Změří odchylku hodin vstupního a výstupního zařízení (ppm) – náhrada ClockAdj z MMTTY.
    /// Zařízení musí běžet (aplikace přijímá); vzorkuje se 2× za sekundu, výsledkem je medián.
    public func measureClock(seconds: Double) async -> (rx: Double?, tx: Double?) {
        var rx: [Double] = [], tx: [Double] = [], nomRx = 0.0, nomTx = 0.0
        let steps = max(1, Int(seconds / 0.5))
        for i in 0..<steps {
            if let r = clockRates(settings.audio.inputUID, true) { nomRx = r.nominal; rx.append(r.actual) }
            if let r = clockRates(settings.audio.outputUID, false) { nomTx = r.nominal; tx.append(r.actual) }
            if i < steps - 1 { try? await Task.sleep(for: .milliseconds(500)) }
        }
        return (ClockCalibration.ppm(actual: rx, nominal: nomRx), ClockCalibration.ppm(actual: tx, nominal: nomTx))
    }

    /// Pravé tlačítko ve spektru: zářez (notch) jako MMTTY.
    public func notchClick(hz: Double) async {
        guard let app else { return }
        await app.notchClick(hz: hz)
        await refreshParams()
    }

    /// Kmitočty aktivních zářezů pro vykreslení (prázdné, když je LMS/notch vypnutý).
    public var notchMarkers: [Double] {
        guard params["lms"] == .bool(true), params["lmsType"] == .string("notch") else { return [] }
        var r: [Double] = []
        if case .int(let n)? = params["notchFreq"], n > 0 { r.append(Double(n)) }
        if params["twoNotch"] == .bool(true), case .int(let n)? = params["notch2Freq"], n > 0 { r.append(Double(n)) }
        return r
    }

    public func tune(toMarkHz hz: Double) async {
        await setParam("mark", .double((hz * 10).rounded() / 10))
    }

    public func setQSOField(_ name: String, _ value: String) async {
        guard let app else { return }
        await run("QSO") { try await app.setQSOField(name, value) }
        qso = await app.qso
        if name == "call" { await refreshPrevious() }
    }

    public func insertWord(_ w: String) async {
        let word = w.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "/"))))
        let kind = WordClassifier.classify(word)
        // závod: po zadání značky jdou čísla a výměna do přijatých polí (MMTTY TMmttyWd::PBoxRxMouseDown)
        // PED: každé kliknuté slovo je značka protistanice
        if settings.contest.enabled, settings.contest.format == .ped {
            if !word.isEmpty { await setQSOField("call", String(word.uppercased().prefix(16))) }
            return
        }
        if settings.contest.enabled, !qso.call.isEmpty, kind != .call {
            for (field, v) in WordClassifier.contestUpdate(word, format: settings.contest.format,
                                                           serialMode: settings.contest.exchange.isEmpty, current: qso) {
                await setQSOField(field, v)
            }
            return
        }
        switch kind {
        case .call: await setQSOField("call", word)
        case .rst: await setQSOField("rstRcvd", word.uppercased())
        case .name: await setQSOField("name", word.uppercased())
        case .other: break
        }
    }

    public func logQSO() async { guard let app else { return }; await run("Log") { _ = try await app.logQSO() } }
    public func clearQSO() async { await app?.clearQSO(); if let app { qso = await app.qso } }
    public func updateLog(_ r: QSORecord) async { guard let app else { return }; await run("Log") { try await app.updateQSO(r) } }
    public func deleteLog(_ id: UUID) async { guard let app else { return }; await run("Log") { try await app.deleteQSO(id) } }
    public func dismissMessages() { messages.removeAll() }

    public func saveMacros(_ m: [Macro]) async {
        var s = settings; s.macros = m; settings = s
        await app?.setMacros(m)
        do { try settingsStore.save(s) } catch { note("Makra nelze uložit: \(error)") }
    }

    public func saveMessages(_ m: [Macro]) async {
        var s = settings; s.messages = m; settings = s
        await app?.setMessages(m)
        do { try settingsStore.save(s) } catch { note("Zprávy nelze uložit: \(error)") }
    }

    public func profiles() -> [Profile?] { profileStore.load() }
    public func loadProfile(_ slot: Int) async {
        guard let app else { return }
        await run("Profil") { try await app.loadProfile(slot) }
        await refreshParams()
        settings.rtty = params
        try? settingsStore.save(settings)
    }
    public func saveProfile(_ slot: Int, name: String) async {
        guard let app else { return }
        await run("Profil") { try await app.saveProfile(slot, name: name) }
        profileNames = profileStore.load().map { $0?.name }
    }

    /// Tlačítko HAM: standardní shift 170 Hz.
    public func hamShift() async { await setParam("shift", .double(170)) }

    /// Kolečko myši ve vodopádu: squelch level po krocích 16 (MMTTY 0–1024).
    public func adjustSquelch(steps: Int) async {
        guard case .double(let v)? = param("squelchLevel") else { return }
        // cíl se počítá synchronně (rychlé události kolečka se sčítají) a zapisuje postupně
        let target = min(1024, max(0, (sqTarget ?? v) + Double(steps) * 16))
        sqTarget = target
        let prev = sqChain
        let t = Task { @MainActor in
            await prev?.value
            if let latest = self.sqTarget { await self.setParam("squelchLevel", .double(latest)) }
        }
        sqChain = t
        await t.value
        if sqChain == t { sqTarget = nil; sqChain = nil }
    }

    public func setXYScope(_ on: Bool) async {
        xyEnabled = on
        if !on { xyPoints = [] }
        await app?.engine.setXYScope(on)
    }

    public func setDemodScope(_ on: Bool) async {
        demodScopeEnabled = on
        if !on { demodScope = nil }
        await app?.engine.setDemodScope(on)
    }

    /// Jedno načtení dávky scope (volá smyčka spektra; pro testy ručně). Zmrazený scope se nepřepisuje.
    public func pollDemodScope() async {
        guard demodScopeEnabled, !scopeFrozen, let d = await app?.engine.demodScope() else { return }
        demodScope = d
    }

    /// Jedno načtení XY bodů (volá smyčka spektra; pro testy ručně).
    public func pollXY() async {
        guard xyEnabled, let pts = await app?.engine.xyScope() else { return }
        xyPoints = pts
    }
}
