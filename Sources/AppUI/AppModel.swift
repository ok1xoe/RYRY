// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import APIServer
import AVFoundation
import AppCore
import DXCC
import AudioIO
import Engine
import Foundation
import Localization
import Keying
import ModemKit
import Observation
import OSLog
import QSOLog
import RigControl
import RTTYModem
import Settings
import Upload
import Spots
import WaveFile

public struct RxRun: Equatable, Sendable, Identifiable {
    public let id: Int
    public var text: String
    public var echo: Bool
}

public enum SendMode: String, CaseIterable, Sendable { case char, word, line }

/// Kanál vícekanálového dekodéru v GUI: kmitočet mark (sleduje AFC) a posledních ~80 znaků.
public struct DecoderChannel: Equatable, Sendable, Identifiable {
    public let id: Int
    public var mark: Double
    public var text: String
    public init(id: Int, mark: Double, text: String = "") { self.id = id; self.mark = mark; self.text = text }
}

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
    public internal(set) var rig: RigStatus?
    public private(set) var qso = QSOFields()
    public private(set) var previousQSOs: [QSORecord] = []
    public private(set) var logRecords: [QSORecord] = []
    public private(set) var messages: [String] = []
    public private(set) var apiStatus = ""
    /// Nenápadná informace pro QSO panel: „callbook: QRZ.com“ nebo chyba (prázdné = nic).
    public private(set) var callbookStatus = ""
    private let secrets: SecretStore
    private let callbookFetcher: HTTPFetcher
    private let callbookDelay: Duration
    private var callbookTask: Task<Void, Never>?
    private var callbookCache: (key: String, service: CachingCallbook)?
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
    /// Nahrávání na online služby (vyměnitelné v testech).
    public var uploader = UploadCoordinator()
    public private(set) var uploadsRunning: Set<UploadTarget> = []
    private var sqTarget: Double?
    private var sqChain: Task<Void, Never>?
    var lastSentForTesting = ""
    /// Sloupec odvysílaného textu v aktuálním řádku (pro zalamování během TX); po přechodu na RX 0.
    public private(set) var txSentColumn = 0
    private let logger = Logger(subsystem: "cz.ok1xoe.mmtty4mac", category: "app")
    static var micWaitMessage: String { L("Čekám na povolení přístupu k mikrofonu (systémový dialog)…") }
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
        do { try settingsStore.save(settings) } catch { note(L("Nastavení nelze uložit: %@", "\(error)")) }
    }

    private func syncDisplay() {
        waterfall.gainDB = settings.display.gainDB
        waterfall.autoGain = settings.display.autoGain
        waterfall.palette = settings.display.palette
        waterfall.decay = settings.display.fftResponse.decay
    }

    public private(set) var app: AppController?
    /// Spoty z DX clusteru a RBN (síť běží mimo hlavní vlákno, jen když je uživatel zapnul).
    public let spotFeed = SpotFeed()
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
                engineFactory: EngineFactory? = nil, spectrumFPS: Double = 15,
                secrets: SecretStore = KeychainSecretStore(), callbookFetcher: @escaping HTTPFetcher = CallbookFactory.liveFetcher,
                callbookDelay: Duration = .milliseconds(800)) {
        self.secrets = secrets; self.callbookFetcher = callbookFetcher; self.callbookDelay = callbookDelay
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

    public static func makeRig(_ r: RigSettings) -> Rig { RigFactory.make(r) }

    public static let realEngine: EngineFactory = { s, rig in
        // RTTYModem na 11025 Hz (± 2 % korekce hodin) nemůže selhat
        Engine(modem: try! RTTYModem(config: s.modemConfig()), rig: rig, audio: CoreAudioBackend(), config: s.engineConfig(),
               auxModemFactory: auxModemFactory(s))
    }

    /// Výroba modemů pro druhý dekodér a kanály (stejná konfigurace jádra jako hlavní, jen příjem).
    public static func auxModemFactory(_ s: AppSettings) -> @Sendable () -> (any Modem)? {
        let cfg = s.modemConfig()
        return { try? RTTYModem(config: cfg) }
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
        syncRxLog()
        let rig = Self.makeRig(settings.rig)
        let engine = engineFactory(settings, rig)
        let log: QSOLogStore?
        let loc = logLocation
        do { log = try QSOLogStore(directory: loc.directory, baseName: loc.name) }
        catch { log = nil; note(L("Log nedostupný: %@", "\(error)")) }
        if let log { for w in await log.warnings { note(w) } }
        let qtc = try? QTCStore(directory: loc.directory, fileName: loc.qtcFileName)
        let app = AppController(settings: settings, engine: engine, log: log, profiles: profileStore, qtc: qtc)
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
            note(L("Přístup k mikrofonu zamítnut – povolte ho v Nastavení systému → Soukromí → Mikrofon. Příjem nefunguje."))
        }
        await engine.setAuxDecoders(settings.decoders.auxConfig())
        do { try await app.start() }
        catch EngineError.audio(let m) { note(L("Zvuk nefunguje: %@ – zkontrolujte zařízení a oprávnění k mikrofonu", m)) }
        catch { note(L("Start selhal: %@", "\(error)")) }
        qso = await app.qso                              // např. odesílané číslo závodu
        await refreshQTCSeries()
        state = await engine.state
        await refreshParams()
        if let log { logRecords = await log.query() }
        await loadSuperCheck()
        await refreshDupe()
        profileNames = profileStore.load().map { $0?.name }
        if xyEnabled { await engine.setXYScope(true) }
        if demodScopeEnabled { await engine.setDemodScope(true) }
        let st = await engine.state
        logger.info("start: stav \(st.rawValue, privacy: .public)")
        await startAPIs(app)
        startSpectrum(engine)
        startSpots()
    }

    private func startAPIs(_ app: AppController) async {
        let host = settings.api.allowRemote ? "0.0.0.0" : "127.0.0.1"
        var parts: [String] = []
        if settings.api.fldigiEnabled {
            let s = FldigiXMLRPCServer(app: app, host: host, port: UInt16(clamping: settings.api.fldigiPort))
            do { let p = try await s.start(); fldigi = s; parts.append("fldigi XML-RPC :\(p)") }
            catch { note(L("fldigi XML-RPC nespuštěno (port %ld obsazen?): %@", Int(settings.api.fldigiPort), "\(error)")) }
        }
        if settings.api.jsonRPCEnabled {
            let s = JSONRPCServer(app: app, host: host, port: UInt16(clamping: settings.api.jsonRPCPort))
            do { let p = try await s.start(); json = s; parts.append("JSON-RPC :\(p)") }
            catch { note(L("JSON-RPC nespuštěno (port %ld obsazen?): %@", Int(settings.api.jsonRPCPort), "\(error)")) }
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
        await stopRecordingWAV()
        spectrumTask?.cancel(); spectrumTask = nil
        spotFeed.stop()
        fldigi?.stop(); json?.stop(); fldigi = nil; json = nil
        await app?.stop()
        await eventTask?.value
        eventTask = nil
        app = nil
        state = .stopped
        decoderChannels = []
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
                m.rig = s.rig; m.api = s.api; m.upload = s.upload
                m.clock = s.clock; m.rttyCore = s.rttyCore
                func take<T: Equatable>(_ kp: WritableKeyPath<AppSettings, T>) { if s[keyPath: kp] != base[keyPath: kp] { m[keyPath: kp] = s[keyPath: kp] } }
                take(\.display.fromHz); take(\.display.toHz); take(\.display.gainDB); take(\.display.autoGain)
                take(\.display.timestamps); take(\.display.fontSize); take(\.display.rxFont)
                take(\.display.rxBackground); take(\.display.rxTextColor); take(\.display.rxEchoColor)
                take(\.display.txBackground); take(\.display.txTextColor); take(\.display.palette)
                take(\.display.fftResponse); take(\.display.xySize); take(\.display.xyQuality); take(\.display.showHints)
                take(\.callbook); take(\.txWindow); take(\.shortcuts); take(\.log.rxText); take(\.log.rxTimestamps); take(\.log.superCheck); take(\.updates.autoCheck); take(\.spots)
                take(\.log.directory)
                take(\.contest.enabled); take(\.contest.format); take(\.contest.name); take(\.contest.category); take(\.contest.exchange)
                take(\.contest.nextSerial); take(\.contest.start); take(\.contest.preset)
                take(\.decoders.secondEnabled); take(\.decoders.secondDemod); take(\.decoders.channelsEnabled)
                take(\.decoders.maxChannels); take(\.decoders.channelTimeoutS); take(\.decoders.showChannelMarks)
                return m
            }
            do { try self.settingsStore.save(merge(self.settings)) } catch { self.note(L("Nastavení nelze uložit: %@", "\(error)")) }
            if let app = self.app, await app.engine.state != .rx { await app.rxNow() }
            await self.stopNow()
            // znovu sloučit: během zastavování mohl přijít .contestSerial (makro s %l)
            let merged = merge(self.settings)
            do { try self.settingsStore.save(merged) } catch { self.note(L("Nastavení nelze uložit: %@", "\(error)")) }
            self.settings = merged
            self.syncDisplay()
            if !self.qtcEnabled { self.qtcReceive = nil; self.qtcPendingCache = nil }
            await self.startNow()
        }
    }

    // MARK: Události

    private func handle(_ e: AppEvent) {
        switch e {
        case .engine(.state(let s)):
            let prev = state
            state = s
            if s == .rx { txSentColumn = 0 }
            // MMTTY „Time stamp“: UTC čas při přepnutí na TX a zpět
            if settings.display.timestamps, prev != s {
                if prev == .rx, s != .stopped { appendRx("\r\n[\(Self.stampFmt.string(from: Date())) UTC TX]\r\n", echo: true) }
                else if s == .rx, prev != .stopped { appendRx("\r\n[\(Self.stampFmt.string(from: Date())) UTC RX]\r\n", echo: false) }
            }
            if s == .tx, !txDraft.isEmpty { Task { await self.sendDraft(mode: self.sendMode) } }   // rozepsaný text hned vysílat
        case .engine(.modem(.rxText(let c, let echo))): appendRx(String(c), echo: echo)
        case .engine(.aux(let a)): handleAux(a)
        case .engine(.modem(.signal(let l, let sq))): signalLevel = l; squelchOpen = sq
        case .engine(.modem(.tuning(let t))): mark = t.mark; space = t.space
        case .engine(.modem(.shift(let f))): fig = f
        case .engine(.rig(let r)):
            let bandChanged = Bands.band(forHz: r.frequency) != Bands.band(forHz: rig?.frequency)
            rig = r
            if bandChanged, !qso.call.isEmpty { Task { await self.refreshDupe() } }   // QSY na jiné pásmo
        case .engine(.error(let err)): note("\(err)")
        case .engine(.pttTimeout): note(L("PTT časovač vypnul vysílání"))
        case .error(let m): note(m)
        case .qsoChanged(let q):
            let callChanged = q.call != qso.call, freqChanged = q.frequency != qso.frequency
            qso = q
            if callChanged { updateSuperCheck(); Task { await self.refreshPrevious(); await self.refreshQTC() }; scheduleCallbook() }
            if callChanged || freqChanged { Task { await self.refreshDupe() } }
            if q.frequency != settings.log.manualFrequency {
                settings.log.manualFrequency = q.frequency
                try? settingsStore.save(settings)
            }
        case .qsoLogged(let r):
            logRecords.insert(r, at: 0)
            if historyCalls.insert(r.call).inserted { rebuildSuperCheck() }
            Task { await self.refreshPrevious(); await self.refreshQTC(); await self.refreshDupe() }
            for t in UploadTarget.allCases where UploadCoordinator.isAuto(t, settings.upload) {
                Task { _ = await self.uploadPending(t, automatic: true) }
            }
        case .qtcChanged: Task { await self.refreshQTC(); await self.refreshQTCSeries() }
        case .contestSerial(let n):
            settings.contest.nextSerial = n
            do { try settingsStore.save(settings) } catch { note(L("Nastavení nelze uložit: %@", "\(error)")) }
        case .qsoUpdated, .qsoDeleted: Task { await self.refreshLog(); await self.refreshQTC() }
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
        if let rxLog {
            do { try rxLog.append(s) } catch {
                self.rxLog = nil
                settings.log.rxText = false                      // přepínač v menu nesmí lhát
                try? settingsStore.save(settings)
                note(L("Záznam příjmu do souboru selhal: %@", "\(error)"))
            }
        }
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

    // MARK: Druhý dekodér a kanály

    public static let rx2Limit = 20_000
    public static let channelTextLimit = 80
    /// Text druhého dekodéru a počitadla pro inkrementální zobrazení.
    public private(set) var rx2Text = ""
    public private(set) var rx2AppendedTotal = 0
    public private(set) var rx2TrimmedTotal = 0
    /// Kanály vícekanálového dekodéru (pořadí vzniku).
    public private(set) var decoderChannels: [DecoderChannel] = []

    func handleAux(_ a: AuxEvent) {
        switch a {
        case .secondText(let c): appendRx2(String(c))
        case .channelText(let id, let c):
            guard let i = decoderChannels.firstIndex(where: { $0.id == id }) else { return }   // kanál už zanikl
            var t = decoderChannels[i].text
            t.append(c)
            if t.count > Self.channelTextLimit { t.removeFirst(t.count - Self.channelTextLimit) }
            decoderChannels[i].text = t
        case .channels(let list):
            let old = Dictionary(uniqueKeysWithValues: decoderChannels.map { ($0.id, $0.text) })
            decoderChannels = list.map { DecoderChannel(id: $0.id, mark: $0.mark, text: old[$0.id] ?? "") }
        }
    }

    public func appendRx2(_ s: String) {
        rx2Text += s
        rx2AppendedTotal += s.count
        if rx2Text.count > Self.rx2Limit {
            let over = rx2Text.count - Self.rx2Limit
            rx2Text.removeFirst(over); rx2TrimmedTotal += over
        }
    }

    public func clearRx2() { rx2TrimmedTotal += rx2Text.count; rx2Text = "" }

    /// Změna nastavení doplňkových dekodérů – hned se projeví (bez restartu) a uloží.
    public func updateDecoders(_ change: (inout DecoderSettings) -> Void) async {
        var d = settings.decoders
        change(&d)
        settings.decoders = d
        do { try settingsStore.save(settings) } catch { note(L("Nastavení nelze uložit: %@", "\(error)")) }
        if !d.channelsEnabled { decoderChannels = [] }
        await app?.engine.setAuxDecoders(d.auxConfig())
    }

    public func setSecondDecoder(_ on: Bool) async { await updateDecoders { $0.secondEnabled = on } }
    public func setChannelDecoding(_ on: Bool) async { await updateDecoders { $0.channelsEnabled = on } }

    /// Demodulátor, který druhý dekodér právě používá (automaticky jiný než hlavní).
    public var secondDemodEffective: String {
        let main: String
        if case .string(let m)? = params["demodType"] { main = m } else { main = "iir" }
        return settings.decoders.auxConfig().resolvedSecondDemod(main: main)
    }

    /// „Naladit“: hlavní dekodér na mark kanálu.
    public func tuneChannel(_ id: Int) async {
        guard let ch = decoderChannels.first(where: { $0.id == id }) else { return }
        await tune(toMarkHz: ch.mark)
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

    // MARK: Záznam příjmu do souboru (MMTTY „Log Rx file“)

    private var rxLog: RxTextLog?
    public var rxLogActive: Bool { rxLog != nil }

    /// Otevře/zavře záznam podle nastavení (po startu a po změně nastavení).
    func syncRxLog() {
        let l = settings.log
        guard l.rxText else { rxLog?.close(); rxLog = nil; return }
        if let r = rxLog, r.directory == l.rxDirectory, r.timestamps == l.rxTimestamps { return }
        rxLog?.close()
        rxLog = RxTextLog(directory: l.rxDirectory, timestamps: l.rxTimestamps)
    }

    /// Přepínač v menu – ukládá se do nastavení.
    public func setRxTextLog(_ on: Bool) {
        settings.log.rxText = on
        do { try settingsStore.save(settings) } catch { note(L("Nastavení nelze uložit: %@", "\(error)")) }
        syncRxLog()
    }

    /// Uloží obsah okna příjmu do souboru (MMTTY „RxWindow to file“).
    public func saveRxText(to url: URL) throws {
        try Data(rxPlainText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "").utf8)
            .write(to: url, options: .atomic)
    }
    public func clearRx() { rxTrimmedTotal += rxCharCount; rxRuns.removeAll(); rxCharCount = 0 }

    // MARK: Duplicita a Super Check Partial

    /// Značka v QSO okně je v závodě duplicita (stejné pásmo a mód).
    public private(set) var isDupe = false
    /// Návrhy pod polem Call: značky obsahující zadanou část a značky lišící se o jeden znak.
    public private(set) var scpPartial: [String] = []
    public private(set) var scpNear: [String] = []
    public private(set) var scpCount = 0
    private var scpMaster: [String] = []
    private var historyCalls: Set<String> = []
    private var superCheck = SuperCheck(calls: [])

    func refreshDupe() async { isDupe = await app?.dupe() ?? false }

    /// Soubor MASTER.SCP (Application Support/mmtty4mac).
    public static var scpURL: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("mmtty4mac/MASTER.SCP")
    }

    /// Načte MASTER.SCP a značky z logu (po startu a po přepnutí logu).
    func loadSuperCheck() async {
        let url = Self.scpURL
        scpMaster = await Task.detached { (try? String(contentsOf: url, encoding: .utf8)).map(SuperCheck.parse) ?? [] }.value
        historyCalls = Set(logRecords.map(\.call))
        rebuildSuperCheck()
    }

    private func rebuildSuperCheck() {
        superCheck = SuperCheck(calls: scpMaster + Array(historyCalls))
        scpCount = superCheck.count
        updateSuperCheck()
    }

    private func updateSuperCheck() { superCheckPreview(qso.call) }

    /// Návrhy pro rozepsanou značku (volá se při psaní, ještě před potvrzením pole).
    public func superCheckPreview(_ text: String) {
        guard settings.log.superCheck else { scpPartial = []; scpNear = []; return }
        let t = text.trimmingCharacters(in: .whitespaces).uppercased()
        scpPartial = superCheck.partial(t).filter { $0 != t }
        scpNear = superCheck.near(t)
    }

    /// Běžné RTTY kmitočty pásem (kHz) pro ruční volbu bez rigu.
    public static let bandPresets: [(String, Double)] = [("160m", 1838), ("80m", 3590), ("40m", 7040), ("30m", 10140),
        ("20m", 14080), ("17m", 18100), ("15m", 21080), ("12m", 24920), ("10m", 28080), ("6m", 50300)]

    /// Stáhne aktuální MASTER.SCP (supercheckpartial.com) – jen na pokyn uživatele.
    public func downloadSuperCheck() async throws -> Int {
        let src = URL(string: "https://www.supercheckpartial.com/MASTER.SCP")!
        let (data, resp) = try await URLSession.shared.data(from: src)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { throw QSOLogError.io(L("MASTER.SCP se nepodařilo stáhnout.")) }
        let calls = SuperCheck.parse(text)
        guard calls.count > 1000 else { throw QSOLogError.io(L("MASTER.SCP se nepodařilo stáhnout.")) }
        try FileManager.default.createDirectory(at: Self.scpURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: Self.scpURL, options: .atomic)
        scpMaster = calls
        rebuildSuperCheck()
        return calls.count
    }

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
        public var errorDescription: String? { L("Soubor je delší než 2 hodiny.") }
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
        wavPlaying = true; wavPaused = false; wavProgress = 0
        wavDuration = Double(samples.count) / 11025
        let token = UUID(); wavToken = token
        wavTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                if await engine.playbackRemaining == 0 { break }
                if let self, self.wavToken == token { await self.updateWAVProgress(engine) }
            }
            if let self, self.wavToken == token { self.wavPlaying = false; self.wavPaused = false; self.wavProgress = 0 }
        }
    }

    public func stopWAV() async {
        wavTask?.cancel(); wavTask = nil
        wavToken = UUID()
        wavPlaying = false; wavPaused = false; wavProgress = 0
        await app?.engine.stopPlayback()
    }

    /// Stav přehrávání pro ovládací lištu (pauza, pozice 0…1, délka v s).
    public private(set) var wavPaused = false
    public private(set) var wavProgress = 0.0
    public private(set) var wavDuration = 0.0

    public func pauseWAV(_ p: Bool) async {
        guard let engine = app?.engine else { return }
        await engine.setPlaybackPaused(p)
        wavPaused = await engine.playbackPaused
    }

    /// Posun na část souboru 0…1 (0 = převinout na začátek).
    public func seekWAV(_ fraction: Double) async {
        guard let engine = app?.engine else { return }
        await engine.seekPlayback(toFraction: fraction)
        await updateWAVProgress(engine)
    }

    private func updateWAVProgress(_ engine: Engine) async {
        let total = await engine.playbackTotal
        guard total > 0 else { return }
        wavProgress = Double(await engine.playbackPosition) / Double(total)
        wavDuration = Double(total) / 11025
    }

    // MARK: Nahrávání příjmu do WAV (MMTTY „Record WAVE“)

    public private(set) var recordingURL: URL?
    public private(set) var recordingSeconds = 0.0
    private var recorder: WaveWriter?
    private var recordTask: Task<Void, Never>?

    /// Nahrává vstup zvukovky (po převzorkování na 11025 Hz, mono 16 bit) do souboru.
    public func startRecordingWAV(to url: URL) async throws {
        await stopRecordingWAV()
        guard let engine = app?.engine else { return }
        let w = try WaveWriter(url: url, sampleRate: 11025)
        recorder = w; recordingURL = url; recordingSeconds = 0
        await engine.setRecording(true)
        recordTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                await self?.flushRecording(engine)
            }
        }
    }

    private func flushRecording(_ engine: Engine) async {
        guard let w = recorder else { return }
        let s = await engine.drainRecording()
        do { try w.append(s) } catch {
            note(L("Nahrávání WAV selhalo: %@", "\(error)"))
            recorder = nil; recordingURL = nil
            recordTask?.cancel(); recordTask = nil
            await engine.setRecording(false)
            try? w.close()
            return
        }
        recordingSeconds = Double(w.sampleCount) / 11025
    }

    public func stopRecordingWAV() async {
        recordTask?.cancel(); recordTask = nil
        guard let w = recorder else { return }
        if let engine = app?.engine {
            await flushRecording(engine)
            await engine.setRecording(false)
        }
        recorder = nil; recordingURL = nil
        do { try w.close() } catch { note(L("Nahrávání WAV selhalo: %@", "\(error)")) }
    }

    // MARK: QTC (WAE DX Contest)

    /// Stav QTC pro stanici v QSO okně (jen ve formátu WAE).
    public private(set) var qtcStatus: AppController.QTCStatus?
    public var qtcEnabled: Bool { settings.contest.enabled && settings.contest.format == .wae }

    public func refreshQTC() async {
        guard qtcEnabled, let app else { qtcStatus = nil; return }
        qtcStatus = await app.qtcStatus(for: qso.call)
    }

    /// Všechny uložené série (okno Log → QTC), nejnovější první.
    public private(set) var qtcSeries: [QTCSeries] = []
    public struct QTCSummary: Equatable, Sendable { public var sent = 0, received = 0, seriesCount = 0; public var points: Int { sent + received } }
    public var qtcSummary: QTCSummary {
        var r = QTCSummary()
        for s in qtcSeries { if s.direction == .sent { r.sent += s.count } else { r.received += s.count } }
        r.seriesCount = qtcSeries.count
        return r
    }
    public func refreshQTCSeries() async {
        qtcSeries = (await app?.qtcStore?.series ?? []).sorted { $0.time > $1.time }
    }
    public func updateQTCSeries(_ s: QTCSeries) async {
        guard let app else { return }
        await run("QTC") { try await app.updateQTCSeries(s) }
        await refreshQTCSeries(); await refreshQTC()
    }
    public func deleteQTCSeries(_ id: UUID) async {
        guard let app else { return }
        await run("QTC") { try await app.deleteQTCSeries(id) }
        await refreshQTCSeries(); await refreshQTC()
    }

    public var qtcPending: QTCSeries? { qtcPendingCache }
    private var qtcPendingCache: QTCSeries?
    public func qtcSend(_ lines: [QTCLine]) async {
        guard let app else { return }
        await run("QTC") { try await app.sendQTC(lines) }
        qtcPendingCache = await app.pendingQTCSeries
    }
    public func qtcRepeat(_ index: Int) async { guard let app else { return }; await run("QTC") { try await app.repeatQTC(index: index) } }
    public func qtcConfirmSent() async {
        guard let app else { return }
        await run("QTC") { try await app.confirmSentQTC() }
        qtcPendingCache = await app.pendingQTCSeries
        await refreshQTC()
    }
    public func qtcCancelSent() async { await app?.cancelSentQTC(); qtcPendingCache = nil }
    public func qtcPhrase(_ p: AppController.QTCPhrase) async { guard let app else { return }; await run("QTC") { try await app.sendQTCPhrase(p) } }

    /// Rozepsaná přijímaná série: hlavička n/k a řádky; `cursor` = další vyplňovaný řádek a pole (0 čas, 1 značka, 2 číslo).
    public struct QTCReceiveDraft: Equatable, Sendable {
        public var number: Int?, count: Int?
        /// Od koho se přijímá (značka v QSO okně při „Přijmout…“ – okno se mezitím může vyčistit).
        public var counterpart = ""
        public var lines: [QTCLine?] = Array(repeating: nil, count: 10)
        public var row = 0, field = 0
        var partial = (time: "", call: "")
        public init() {}
        public static func == (a: Self, b: Self) -> Bool {
            a.number == b.number && a.count == b.count && a.lines == b.lines && a.row == b.row && a.field == b.field
                && a.counterpart == b.counterpart
        }
    }
    public var qtcReceive: QTCReceiveDraft?
    private var qtcRxStart = 0

    public func startQTCReceive() {
        var d = QTCReceiveDraft(); d.counterpart = qso.call
        qtcReceive = d
        qtcRxStart = rxAppendedTotal
        // série mohla přijít dřív, než operátor příjem otevřel: začít od poslední zmínky protistanice
        // (např. „OK1XOE DE K3LR YES QTC 9/5 QRV?“) v posledních 3000 znacích příjmu
        let back = min(3000, rxAppendedTotal - rxTrimmedTotal)
        let tail = rxTail(back).filter { !$0.echo }.map(\.text).joined()
        let all = rxTail(back).map(\.text).joined()
        if !d.counterpart.isEmpty, tail.uppercased().contains(d.counterpart.uppercased()),
           let r = all.uppercased().range(of: d.counterpart.uppercased(), options: .backwards) {
            qtcRxStart = rxAppendedTotal - all.distance(from: r.lowerBound, to: all.endIndex)
        }
    }

    /// „QRV – přijmout“: otevře příjem QTC a odvysílá QRV (protistanice pak posílá sérii).
    public func qtcQRVReceive() async {
        if qtcReceive == nil { startQTCReceive() }
        await qtcPhrase(.qrv)
    }
    public func cancelQTCReceive() { qtcReceive = nil }
    /// Ruční úprava přijímané série (hlavička „n/k“, řádek „HHMM ZNAČKA NNN“; prázdné = smazat).
    public func qtcSetHeader(_ text: String) {
        guard var d = qtcReceive else { return }
        if let (n, k) = QTCText.parseHeader(text) { d.number = n; d.count = k } else if text.isEmpty { d.number = nil; d.count = nil }
        qtcReceive = d
    }
    public func qtcSetLine(_ i: Int, _ text: String) {
        guard var d = qtcReceive, d.lines.indices.contains(i) else { return }
        d.lines[i] = text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : QTCText.parseLine(text)
        qtcReceive = d
    }

    /// Rozebere text přijatý od začátku příjmu QTC: hlavička n/k, řádky „HHMM ZNAČKA NNN“ v pořadí
    /// (nečitelný řádek nechá prázdné místo, aby AGN N žádalo správný řádek) a opakování „N HHMM ZNAČKA NNN …“ na pozici N.
    public func qtcFillFromRx() {
        guard var d = qtcReceive else { return }
        // vlastní vysílání (echo) vynechat, ale jeho místo je konec řádku: protistanice po mém „AGN 8“
        // často začne bez CR/LF a text by se slepil s koncem série („BKKA8 0803 …“)
        let text = rxTail(rxAppendedTotal - qtcRxStart).map { $0.echo ? "\n" : $0.text }.joined()
        var lines: [QTCLine?] = Array(repeating: nil, count: 10)
        var next = 0
        for raw in text.components(separatedBy: CharacterSet(charactersIn: "\r\n")) where !raw.isEmpty {
            var rest = raw
            if raw.uppercased().contains("QTC"), let (n, k) = QTCText.parseHeader(raw) {
                d.number = n; d.count = k
                // řádek QTC přilepený za hlavičkou (ztracené CR/LF)
                let tok = raw.uppercased().split(separator: " ")
                guard let last = tok.lastIndex(where: { $0.contains("/") }) else { continue }
                rest = tok[(last + 1)...].joined(separator: " ")
                if rest.isEmpty { continue }
            }
            if let (idx, l) = QTCText.parseIndexedLine(rest) { lines[idx - 1] = l; continue }
            if let l = QTCText.parseLine(rest) {
                if next < lines.count, !lines.contains(l) { lines[next] = l; next += 1 }
            } else if QTCText.looksLikeLine(rest), next < lines.count {
                next += 1                                                  // poškozený řádek: místo zůstane prázdné
            }
        }
        d.lines = lines
        let k = d.count ?? 10
        d.row = min(lines.firstIndex { $0 == nil } ?? k, max(0, k - 1)); d.field = 0
        qtcReceive = d
    }

    /// Klik na slovo během příjmu QTC: hlavička n/k, pak postupně čas, značka, číslo.
    func qtcInsertWord(_ w: String) {
        guard var d = qtcReceive else { return }
        let u = w.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if u.contains("/"), let (n, k) = QTCText.parseHeader(u), !u.contains(where: \.isLetter) {
            d.number = n; d.count = k; qtcReceive = d; return
        }
        switch d.field {
        case 0:
            guard u.count == 4, let v = Int(u), v / 100 < 24, v % 100 < 60 else { return }
            d.partial.time = u; d.field = 1
        case 1:
            guard u.count >= 3, u.contains(where: \.isLetter), u.contains(where: \.isNumber) else { return }
            d.partial.call = u; d.field = 2
        default:
            guard u.count <= 5, let n = Int(u), d.row < min(d.lines.count, d.count ?? 10) else { return }
            d.lines[d.row] = QTCLine(time: d.partial.time, call: d.partial.call, serial: n)
            d.row += 1; d.field = 0; d.partial = ("", "")
        }
        qtcReceive = d
    }

    /// Uloží přijatou sérii (jen prvních k řádků); vrací true při úspěchu – teprve pak potvrdit R R ALL OK.
    @discardableResult
    public func qtcSaveReceived() async -> Bool {
        guard let app, let d = qtcReceive, let n = d.number else { note(L("QTC: chybí hlavička série (n/k)")); return false }
        let lines = d.lines.prefix(d.count ?? 10).compactMap { $0 }
        var ok = false
        await run("QTC") { try await app.saveReceivedQTC(counterpart: d.counterpart, number: n, declaredCount: d.count, lines: lines); ok = true }
        if ok { qtcReceive = nil; await refreshQTC() }
        return ok
    }

    /// Země DXCC aktuální značky v QSO okně (nil = neznámá).
    public var dxcc: CountryInfo? { qso.call.isEmpty ? nil : app?.country(for: qso.call) }

    /// Log (volitelně za období) ve formátu Cabrillo s hlavičkou z nastavení stanice a závodu.
    public func cabrilloText(from: Date? = nil, to: Date? = nil, contestOnly: Bool = false) async -> String {
        await app?.cabrillo(from: from, to: to, contestOnly: contestOnly) ?? ""
    }

    // MARK: Správa logu (nový, otevřít, uložit jako)

    public var logLocation: LogLocation {
        LogLocation(directory: URL(fileURLWithPath: settings.log.directory), name: settings.log.name)
    }

    public enum LogFileError: Error, LocalizedError {
        case exists(String), missing(String)
        public var errorDescription: String? {
            switch self {
            case .exists(let n): return L("Log „%@“ už existuje – otevřete ho přes Otevřít log.", n)
            case .missing(let n): return L("Log „%@“ neexistuje.", n)
            }
        }
    }

    /// Přepne na jiný log (restart jako po Použít – během vysílání nejdřív RX).
    private func switchLog(to loc: LogLocation, resetSerial: Bool) async {
        await serialized { [weak self] in
            guard let self else { return }
            if let app = self.app, await app.engine.state != .rx { await app.rxNow() }
            await self.stopNow()
            self.settings.log.directory = loc.directory.path
            self.settings.log.name = loc.name
            self.settings.log.remember(loc.displayPath)
            if resetSerial { self.settings.contest.nextSerial = 1 }
            do { try self.settingsStore.save(self.settings) } catch { self.note(L("Nastavení nelze uložit: %@", "\(error)")) }
            self.qtcReceive = nil; self.qtcPendingCache = nil
            await self.startNow()
        }
    }

    /// Nový prázdný log (pořadová čísla závodu začnou od 1).
    public func newLog(file: URL) async throws {
        let loc = LogLocation(file: file)
        let fm = FileManager.default
        if fm.fileExists(atPath: loc.jsonlURL.path) || fm.fileExists(atPath: loc.adifURL.path) { throw LogFileError.exists(loc.name) }
        try fm.createDirectory(at: loc.directory, withIntermediateDirectories: true)
        await switchLog(to: loc, resetSerial: true)
    }

    /// Otevře existující log; ADIF z jiného programu se převede (originál zůstane jako .orig). Vrací text pro uživatele.
    @discardableResult
    public func openLog(file: URL) async throws -> String {
        let loc = LogLocation(file: file)
        let fm = FileManager.default
        guard fm.fileExists(atPath: loc.jsonlURL.path) || fm.fileExists(atPath: loc.adifURL.path)
                || fm.fileExists(atPath: loc.directory.appendingPathComponent(loc.name + ".adif").path)
        else { throw LogFileError.missing(loc.name) }
        guard loc != logLocation else { return L("Log „%@“ je už otevřený.", loc.name) }
        let r = try await loc.prepareForOpen()
        await switchLog(to: loc, resetSerial: false)
        if let b = r.backup {
            return L("Log převeden z ADIF: %ld spojení, přeskočeno %ld. Původní soubor: %@", r.imported, r.skipped, b.lastPathComponent)
        }
        return L("Otevřen log „%@“ (%ld spojení).", loc.name, logRecords.count)
    }

    /// Uloží kopii logu pod jiným názvem a dál pracuje v ní.
    public func saveLogAs(file: URL) async throws {
        let dst = LogLocation(file: file)
        if let log = app?.log, !(await log.isADIFConsistent()) { try await log.rebuildADIF() }
        try logLocation.copy(to: dst)
        await switchLog(to: dst, resetSerial: false)
    }

    /// Kopie ADIF logu jinam (log zůstává otevřený).
    public func exportADIF(to url: URL) async throws {
        guard let log = app?.log else { throw QSOLogError.io(L("Log není k dispozici.")) }
        if !(await log.isADIFConsistent()) { try await log.rebuildADIF() }
        let src = logLocation.adifURL
        guard FileManager.default.fileExists(atPath: src.path) else { throw LogFileError.missing(logLocation.name) }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.copyItem(at: src, to: url)
    }

    /// Import ADIF (např. log převedený z MMTTY); vrací text pro uživatele.
    public func importADIF(_ url: URL) async throws -> String {
        guard let log = app?.log else { throw QSOLogError.io(L("Log není k dispozici.")) }
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let parsed = ADIF.importRecords(text)
        let r = try await log.importRecords(parsed.records)
        await refreshLog()
        return L("Importováno %ld spojení, duplicit %ld, neplatných záznamů %ld.", r.added, r.duplicates, parsed.skipped)
    }

    // MARK: Nahrávání (LoTW / eQSL / Club Log)

    /// Nahraje dosud nenahraná spojení na službu. Ruční volání vrací zprávu pro alert; automatické (po zalogování)
    /// běží na pozadí, chybu hlásí do stavového řádku (`note`) a vrací nil.
    @discardableResult
    public func uploadPending(_ t: UploadTarget, automatic: Bool = false) async -> String? {
        guard let log = app?.log else { return automatic ? nil : L("Log není dostupný.") }
        guard !uploadsRunning.contains(t) else { return automatic ? nil : L("%@: nahrávání už běží.", t.title) }
        uploadsRunning.insert(t); defer { uploadsRunning.remove(t) }
        let coordinator = uploader, cfg = settings
        do {
            let msg = try await coordinator.uploadPending(t, settings: cfg, log: log)
            await refreshLog()
            return automatic ? nil : msg
        } catch {
            await refreshLog()
            let text = "\(t.title): \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
            if automatic { note(text); return nil }
            return text
        }
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
        if state == .rx {
            await run("TX") {
                try await app.tx()
                if settings.txWindow.autoCRLF { lastSentForTesting = "\r\n"; await app.send(text: "\r\n") }
            }
        } else { await app.rx() }
    }

    public func rxNow() async { await app?.rxNow() }
    public func tune() async { guard let app else { return }; await run("Tune") { try await app.tune() } }
    public func runMacro(_ i: Int) async { guard let app else { return }; await run(L("Makro F%ld", i + 1)) { try await app.runMacro(index: i) } }
    public func stopMacro() async { await app?.stopMacroRepeat() }
    public func runMessage(_ i: Int) async {
        guard let app else { return }
        let name = settings.messages.indices.contains(i) ? settings.messages[i].name : "\(i + 1)"
        await run(L("Zpráva %@", name)) { try await app.runMessage(index: i) }
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
        txSentColumn = TxWrap.column(afterSending: out, from: txSentColumn)
        lastSentForTesting = out
        await app.send(text: out)
    }

    /// Vyšle obsah textového souboru (MMTTY „Send Text…“).
    public func sendTextFile(_ url: URL) async {
        guard let app else { return }
        await run(L("Odeslat soubor")) {
            let d = try Data(contentsOf: url)
            try await app.sendFileText(d)
        }
    }

    public func param(_ id: String) -> ParameterValue? { params[id] }

    public func setParam(_ id: String, _ v: ParameterValue) async {
        guard let app else { return }
        await run(L("Parametr %@", id)) { try await app.setModemParam(id, v) }
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
    /// `inputUID`/`outputUID`: zařízení zvolená v dialogu (výchozí = uložené nastavení).
    public func measureClock(seconds: Double, inputUID: String?? = nil, outputUID: String?? = nil) async -> (rx: Double?, tx: Double?) {
        var rx: [Double] = [], tx: [Double] = [], nomRx = 0.0, nomTx = 0.0
        let steps = max(1, Int(seconds / 0.5))
        let inUID = inputUID ?? settings.audio.inputUID, outUID = outputUID ?? settings.audio.outputUID
        for i in 0..<steps {
            if let r = clockRates(inUID, true) { nomRx = r.nominal; rx.append(r.actual) }
            if let r = clockRates(outUID, false) { nomTx = r.nominal; tx.append(r.actual) }
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

    // MARK: Spoty (DX cluster, RBN)

    /// Konfigurace spotů z nastavení; nil, když je vše vypnuto.
    func spotFeedConfig() -> SpotFeedConfig? {
        let p = settings.spots
        guard p.clusterEnabled || p.rbnEnabled else { return nil }
        var c = SpotFeedConfig(call: settings.station.call, rttyOnly: p.rttyOnly, maxAgeMinutes: p.maxAgeMinutes)
        if p.clusterEnabled { c.cluster = SpotEndpoint(host: p.clusterHost, port: UInt16(clamping: p.clusterPort), commands: p.clusterCommands) }
        if p.rbnEnabled { c.rbn = SpotEndpoint(host: p.rbnHost, port: UInt16(clamping: p.rbnPort)) }
        return c
    }

    private func startSpots() {
        guard let c = spotFeedConfig() else { spotFeed.stop(); return }
        if settings.station.call.trimmingCharacters(in: .whitespaces).isEmpty { note(L("Spoty: v nastavení Stanice chybí značka pro přihlášení.")) }
        spotFeed.start(c)
    }

    /// Změna nastavení spotů z okna (filtr RTTY) – hned uloží; spojení se přenastaví.
    public func setSpots(_ change: (inout SpotSettings) -> Void) {
        var p = settings.spots
        change(&p)
        guard p != settings.spots else { return }
        let old = settings.spots
        settings.spots = p
        do { try settingsStore.save(settings) } catch { note(L("Nastavení nelze uložit: %@", "\(error)")) }
        guard app != nil else { return }
        var noReconnect = old; noReconnect.showInWaterfall = p.showInWaterfall
        if noReconnect == p { return }                                   // jen zobrazení štítků, spojení se nemění
        var onlyFilter = old; onlyFilter.rttyOnly = p.rttyOnly; onlyFilter.showInWaterfall = p.showInWaterfall
        if onlyFilter == p, p.rttyOnly { spotFeed.rttyOnly = true }      // jen zúžení zobrazení, spojení se nemění
        else { startSpots() }                                            // rozšíření na všechny módy: nová data ze serveru
    }

    /// Dvojklik na spot: nastaví rig na frekvenci spotu (+ posun) a vloží značku do QSO okna.
    /// Bez rigu (nebo při chybě rigu) se jen vloží značka.
    public func useSpot(_ spot: Spot) async {
        let off = min(max(settings.spots.offsetHz, SpotSettings.offsetRange.lowerBound), SpotSettings.offsetRange.upperBound)
        let hz = spot.frequencyHz + off
        if let app, settings.rig.type != .none {
            if state != .rx {
                // nikdy nepřelaďovat zaklíčovaný vysílač (jiné pásmo pod zátěží, cizí kmitočet)
                note(L("Během vysílání se rig nepřelaďuje – spot použijte po přechodu na RX."))
            } else {
                do { try await app.setFrequency(hz) }
                catch { note(L("Rig: frekvenci %@ kHz nelze nastavit: %@", String(format: "%.1f", hz / 1000), "\(error)")) }
            }
        } else {
            await setQSOField("freq", String(format: "%.1f", spot.frequencyHz / 1000))   // bez rigu: frekvence spotu do logu
        }
        await setQSOField("call", spot.call)
    }

    /// Klik na štítek band map: mark na audio pozici spotu a značka do QSO okna (rig se nepřelaďuje).
    public func bandMapClick(_ marker: BandMapMarker) async {
        await tune(toMarkHz: marker.audioHz)
        await setQSOField("call", marker.spot.call)
    }

    public func tune(toMarkHz hz: Double) async {
        await setParam("mark", .double((hz * 10).rounded() / 10))
    }

    public func setQSOField(_ name: String, _ value: String) async {
        guard let app else { return }
        await run("QSO") { try await app.setQSOField(name, value) }
        qso = await app.qso
        if name == "call" { await refreshPrevious(); scheduleCallbook() }
    }

    // MARK: Callbook

    public func callbookPassword(kind: CallbookKind, username: String) -> String {
        guard kind != .none, !username.isEmpty else { return "" }
        return secrets.password(service: kind.rawValue, account: username) ?? ""
    }

    public func saveCallbookPassword(_ password: String, kind: CallbookKind, username: String) {
        guard kind != .none, !username.isEmpty else { return }
        do { try secrets.setPassword(password, service: kind.rawValue, account: username) }
        catch { note(L("Heslo callbooku nelze uložit do Klíčenky: %@", "\(error)")) }
        callbookCache = nil
    }

    /// Po krátké prodlevě dohledá aktuální značku (další změna dotaz zruší).
    private func scheduleCallbook() {
        callbookTask?.cancel(); callbookTask = nil
        let cb = settings.callbook
        let call = qso.call
        guard !call.isEmpty else { callbookStatus = ""; return }
        guard cb.service != .none, cb.autoLookup else { return }
        callbookTask = Task { [weak self, delay = callbookDelay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.performCallbook(call)
        }
    }

    private func callbookService(_ cb: CallbookSettings) -> CachingCallbook? {
        let pw = callbookPassword(kind: cb.service, username: cb.username)
        guard cb.service != .none, !cb.username.isEmpty, !pw.isEmpty else { return nil }
        let key = "\(cb.service.rawValue)|\(cb.username)|\(pw)"
        if let c = callbookCache, c.key == key { return c.service }
        guard let svc = CallbookFactory.make(cb.service, username: cb.username, password: pw, fetcher: callbookFetcher) else { return nil }
        let c = CachingCallbook(svc)
        callbookCache = (key, c)
        return c
    }

    private func performCallbook(_ call: String) async {
        let cb = settings.callbook
        guard let svc = callbookService(cb) else { callbookStatus = L("callbook: chybí uživatel nebo heslo"); return }
        do {
            let entry = try await svc.lookup(call)
            guard !Task.isCancelled, qso.call == call else { return }
            guard let e = entry else { callbookStatus = L("callbook: %@ · nenalezeno", svc.name); return }
            callbookStatus = L("callbook: %@", svc.name)
            for (field, value) in [("name", e.name), ("qth", e.qth), ("locator", e.grid)] where !value.isEmpty {
                guard qso.call == call else { return }
                if !cb.fillEmptyOnly || (qso.value(field) ?? "").isEmpty { await setQSOField(field, value) }
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, qso.call == call else { return }
            callbookStatus = L("callbook: chyba – %@", error.localizedDescription)
        }
    }

    /// Tlačítko „Vyzkoušet“: přihlášení a vyhledání vlastní značky s hodnotami z dialogu (bez cache).
    public func testCallbook(kind: CallbookKind, username: String, password: String, call: String) async -> String {
        guard let svc = CallbookFactory.make(kind, username: username, password: password, fetcher: callbookFetcher),
              !username.isEmpty, !password.isEmpty else { return L("Vyberte službu a zadejte uživatele a heslo.") }
        guard !call.isEmpty else { return L("Ve Stanici chybí vaše značka.") }
        do {
            guard let e = try await svc.lookup(call) else { return L("Přihlášení v pořádku, značka %@ nenalezena.", call) }
            let parts = [e.name, e.qth, e.grid, e.country].filter { !$0.isEmpty }
            return L("Funguje: %@", ([e.call] + parts).joined(separator: " · "))
        } catch {
            return L("Chyba: %@", error.localizedDescription)
        }
    }

    public func insertWord(_ w: String) async {
        if qtcReceive != nil, qtcEnabled { qtcInsertWord(w); return }    // příjem QTC má přednost před QSO oknem
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
        do { try settingsStore.save(s) } catch { note(L("Makra nelze uložit: %@", "\(error)")) }
    }

    public func saveMessages(_ m: [Macro]) async {
        var s = settings; s.messages = m; settings = s
        await app?.setMessages(m)
        do { try settingsStore.save(s) } catch { note(L("Zprávy nelze uložit: %@", "\(error)")) }
    }

    public func profiles() -> [Profile?] { profileStore.load() }
    public func loadProfile(_ slot: Int) async {
        guard let app else { return }
        var ok = false
        await run(L("Profil")) { try await app.loadProfile(slot); ok = true }
        await refreshParams()
        guard ok else { return }                    // nenačtený profil nastavení nemění
        settings.rtty = params
        try? settingsStore.save(settings)
    }
    public func saveProfile(_ slot: Int, name: String) async {
        guard let app else { return }
        await run(L("Profil")) { try await app.saveProfile(slot, name: name) }
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
