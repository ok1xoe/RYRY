// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import APIServer
import AVFoundation
import AppCore
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

public struct RxRun: Equatable, Sendable, Identifiable {
    public let id: Int
    public var text: String
    public var echo: Bool
}

public enum SendMode: String, CaseIterable, Sendable { case char, word, line }

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
    var lastSentForTesting = ""
    private let logger = Logger(subsystem: "cz.ok1xoe.mmtty4mac", category: "app")
    static let micWaitMessage = "Čekám na povolení přístupu k mikrofonu (systémový dialog)…"
    public var waterfallFromHz = 0.0
    public var waterfallToHz = 3000.0

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
        // RTTYModem na 11025 Hz nemůže selhat
        Engine(modem: try! RTTYModem(), rig: rig, audio: CoreAudioBackend(), config: s.engineConfig())
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
        state = await engine.state
        await refreshParams()
        if let log { logRecords = await log.query() }
        profileNames = profileStore.load().map { $0?.name }
        if xyEnabled { await engine.setXYScope(true) }
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
    public func applySettings(_ s: AppSettings) async {
        await serialized { [weak self] in
            guard let self else { return }
            var merged = self.settings
            merged.station = s.station; merged.audio = s.audio; merged.ptt = s.ptt; merged.fsk = s.fsk
            merged.rig = s.rig; merged.api = s.api; merged.log = s.log
            do { try self.settingsStore.save(merged) } catch { self.note("Nastavení nelze uložit: \(error)") }
            if let app = self.app, await app.engine.state != .rx { await app.rxNow() }
            await self.stopNow()
            self.settings = merged
            await self.startNow()
        }
    }

    // MARK: Události

    private func handle(_ e: AppEvent) {
        switch e {
        case .engine(.state(let s)):
            state = s
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
        case .qsoUpdated, .qsoDeleted: Task { await self.refreshLog() }
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
        switch WordClassifier.classify(word) {
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
        let n = min(1024, max(0, v + Double(steps) * 16))
        await setParam("squelchLevel", .double(n))
    }

    public func setXYScope(_ on: Bool) async {
        xyEnabled = on
        if !on { xyPoints = [] }
        await app?.engine.setXYScope(on)
    }

    /// Jedno načtení XY bodů (volá smyčka spektra; pro testy ručně).
    public func pollXY() async {
        guard xyEnabled, let pts = await app?.engine.xyScope() else { return }
        xyPoints = pts
    }
}
