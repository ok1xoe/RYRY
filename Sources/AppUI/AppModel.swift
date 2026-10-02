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

/// A channel of the multi-channel decoder in the GUI: the mark frequency (tracks AFC) and the last ~80 characters.
public struct DecoderChannel: Equatable, Sendable, Identifiable {
    public let id: Int
    public var mark: Double
    public var text: String
    public init(id: Int, mark: Double, text: String = "") { self.id = id; self.mark = mark; self.text = text }
}

public extension AppSettings {
    /// Configuration of the RTTY core (needs a new modem, i.e. an Engine restart).
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

/// The default modem parameters (used to decide what to store in the settings).
enum AppDefaults {
    static let rtty: [String: ParameterValue] = {
        guard let m = try? RTTYModem() else { return [:] }
        var d: [String: ParameterValue] = [:]
        for p in m.parameters { d[p.id] = p.defaultValue }
        return d
    }()
}

/// State and actions for the GUI. All the logic lives in AppController/Engine; this is only the wiring and the derived state.
@MainActor @Observable
public final class AppModel {
    public static let rxLimit = 200_000

    public typealias EngineFactory = @MainActor (AppSettings, Rig) -> Engine

    private let settingsStore: SettingsStore
    private let profileStore: ProfileStore
    private let engineFactory: EngineFactory
    private let spectrumFPS: Double

    public private(set) var settings: AppSettings {
        didSet {
            if multiplierKey != multiplierKeyApplied { refreshMultipliers() }
            if oldValue.contest.enabled != settings.contest.enabled || oldValue.contest.start != settings.contest.start
                || oldValue.contest.selectedPreset != settings.contest.selectedPreset {
                rebuildLogIndex()                                              // dupes: contest turned on/off, a different start or different rules
            }
        }
    }
    public private(set) var state: EngineState = .stopped
    public private(set) var rxRuns: [RxRun] = []
    public private(set) var rxCharCount = 0
    /// Absolute counters for the incremental display (what was appended at the end / what was trimmed from the front).
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
    public internal(set) var rig: RigStatus? { didSet { if currentBand != Self.band(oldValue, qso) { refreshNewMultiplier() } } }
    public private(set) var qso = QSOFields() { didSet { refreshNewMultiplier() } }
    public private(set) var previousQSOs: [QSORecord] = []
    /// A change of log recomputes the multipliers from scratch; logging a single QSO only adds to them (`addLoggedRecord`).
    public private(set) var logRecords: [QSORecord] = [] { didSet { if !logRecordsIncremental { refreshMultipliers() } } }
    private var logRecordsIncremental = false
    /// The log index for callsign highlighting, watching and the band map (see RxAlerts.swift, AppModel+Alerts.swift).
    public internal(set) var logIndex = LogIndex()
    /// The contest start `logIndex` was built with (dupes).
    var logIndexSince: Date?
    /// The "in the log / on the band" index for the Spots window (maintained together with `logIndex`, not on every redraw).
    public internal(set) var spotLogIndex = SpotLogIndex()
    /// Occurrences of callsigns in the receive text (confirming "needed" against noise) and the previous received word (DE/CQ before a call).
    var rxCallSightings = RxCallSightings()
    var rxPrevWord = ""
    /// A summary of the alerts from spots (a burst after connecting to the cluster becomes a single line).
    var neededPending: [String] = []
    var neededLastLine: Date?
    var neededFlushTask: Task<Void, Never>?
    /// An increment means a state change that affects callsign styling (log, band, settings) - the receive window restyles the end of the text.
    public internal(set) var highlightVersion = 0
    var highlightBand: String?
    public var alertSink: AlertSink
    let alertClock: () -> Date
    var alertThrottle = AlertThrottle()
    var rxScanner = RxWordScanner()
    public private(set) var messages: [String] = []
    public private(set) var apiStatus = ""
    /// A discreet piece of information for the QSO panel: "callbook: QRZ.com" or an error (empty = nothing).
    public private(set) var callbookStatus = ""
    /// Call history: the number of calls loaded and the loading status (empty = nothing to report).
    public private(set) var callHistoryCount = 0
    public private(set) var callHistoryStatus = ""
    private var callHistory: CallHistory?
    private var callHistoryPath = ""
    private var callHistoryTask: Task<Void, Never>?
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
    /// The demodulator scope (the "Scope" window): the last batch, source 0–3, freeze (a single-shot capture).
    public private(set) var demodScope: DemodScope?
    public private(set) var demodScopeEnabled = false
    public var scopeSource = 2
    public var scopeFrozen = false
    /// Uploading to the online services (replaceable in tests).
    public var uploader = UploadCoordinator()
    /// Access to the log folder outside the sandbox container (the app installs the real open panel at launch).
    public var folderAccess = FolderAccess(prompt: NoFolderPrompt())
    public private(set) var uploadsRunning: Set<UploadTarget> = []
    private var sqTarget: Double?
    private var sqChain: Task<Void, Never>?
    var lastSentForTesting = ""
    /// The column of the transmitted text within the current line (for wrapping during TX); 0 after switching to RX.
    public private(set) var txSentColumn = 0
    private let logger = Logger(subsystem: "cz.ok1xoe.mmtty4mac", category: "app")
    static var micWaitMessage: String { L("Čekám na povolení přístupu k mikrofonu (systémový dialog)…") }
    public var waterfallFromHz: Double { settings.display.fromHz }
    public var waterfallToHz: Double { settings.display.toHz }

    /// Display (range, gain, font, timestamps) - no restart, saved immediately.
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
    /// Spots from the DX cluster and RBN (the networking runs off the main thread, and only when the user enabled it).
    public let spotFeed = SpotFeed()
    /// The most recently hand-sent DX cluster commands (newest last; at most 30) - the up arrow in the Spots window.
    public internal(set) var clusterHistory: [String] = []
    /// The message about the last cluster command (an error); nil = all good.
    public internal(set) var clusterMessage: String?
    private var fldigi: FldigiXMLRPCServer?
    private var json: JSONRPCServer?
    private var eventTask: Task<Void, Never>?
    private var spectrumTask: Task<Void, Never>?
    /// start/stop/applySettings run one after another (otherwise orphaned engines with an open PTT port would appear).
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
                callbookDelay: Duration = .milliseconds(800),
                alertSink: AlertSink = NullAlertSink(), alertClock: @escaping () -> Date = { Date() }) {
        self.alertSink = alertSink; self.alertClock = alertClock
        self.secrets = secrets; self.callbookFetcher = callbookFetcher; self.callbookDelay = callbookDelay
        self.settingsStore = settingsStore; self.profileStore = profileStore
        self.engineFactory = engineFactory ?? AppModel.realEngine
        self.spectrumFPS = spectrumFPS
        let (s, w) = settingsStore.load()
        settings = s
        messages = w
        syncDisplay()
        spotFeed.filter = s.spots.filter          // the feed only mirrors the filter from the settings (source of truth `settings.spots.filter`)
        spotFeed.onNewSpot = { [weak self] spot in self?.checkSpotNeeded(spot) }
    }

    /// The microphone permission status; on the first run it asks for it (asynchronously).
    nonisolated static func microphoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    public static func makeRig(_ r: RigSettings) -> Rig { RigFactory.make(r) }

    public static let realEngine: EngineFactory = { s, rig in
        // RTTYModem at 11025 Hz (± 2 % clock correction) cannot fail
        Engine(modem: try! RTTYModem(config: s.modemConfig()), rig: rig, audio: CoreAudioBackend(), config: s.engineConfig(),
               auxModemFactory: auxModemFactory(s))
    }

    /// Creates the modems for the second decoder and the channels (the same core configuration as the main one, receive only).
    public static func auxModemFactory(_ s: AppSettings) -> @Sendable () -> (any Modem)? {
        let cfg = s.modemConfig()
        return { try? RTTYModem(config: cfg) }
    }

    func noteForTesting(_ m: String) { note(m) }

    func note(_ m: String) {
        logger.notice("\(m, privacy: .public)")
        messages.append(m)
        if messages.count > 50 { messages.removeFirst(messages.count - 50) }
    }

    // MARK: Start/stop

    public func start() async { await serialized { [weak self] in await self?.startNow() } }

    private func startNow() async {
        guard app == nil else { return }                 // already running
        await ensureLogFolder()                          // first: it may move the log folder (and with it rx/)
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
        syncCallHistory()
        let events = app.events()
        eventTask = Task { [weak self] in
            for await e in events { self?.handle(e) }
        }
        await refreshParams()
        // Ask for microphone permission up front (otherwise starting the audio input waits on the dialog).
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            note(Self.micWaitMessage)
        }
        let micOK = await Self.microphoneAccess()
        messages.removeAll { $0 == Self.micWaitMessage }       // the dialog is done
        if !micOK {
            note(L("Přístup k mikrofonu zamítnut – povolte ho v Nastavení systému → Soukromí → Mikrofon. Příjem nefunguje."))
        }
        await engine.setAuxDecoders(settings.decoders.auxConfig())
        do { try await app.start() }
        catch EngineError.audio(let m) { note(L("Zvuk nefunguje: %@ – zkontrolujte zařízení a oprávnění k mikrofonu", m)) }
        catch { note(L("Start selhal: %@", "\(error)")) }
        qso = await app.qso                              // e.g. the sent contest number
        await refreshQTCSeries()
        state = await engine.state
        await refreshParams()
        if let log { logRecords = await log.query() }
        rebuildLogIndex()
        backupLogIfDue()
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

    /// Quitting the app: RX immediately (PTT off), then a stop with a timeout - ⌘Q must not hang.
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
        defer { folderAccess.stopAll() }
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

    /// Saves the settings and restarts (an Engine is single-use). While transmitting it first switches safely to RX.
    /// The sections from the Settings dialog are merged into the current settings; the modem parameters and the macros
    /// (changed elsewhere, immediately) are not overwritten by the dialog's stale copy.
    /// Applies the settings from the dialog. `baseline` = the state the dialog started from: the contest serial number
    /// and the display also change elsewhere (the log, the quick menu), so only the fields the user changed are taken over.
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
                take(\.callbook); take(\.callHistory); take(\.txWindow); take(\.shortcuts); take(\.log.rxText); take(\.log.rxTimestamps); take(\.log.superCheck); take(\.log.backup); take(\.log.backupKeep); take(\.spots); take(\.display.highlightCalls); take(\.alerts)
                take(\.log.directory); take(\.log.bookmarks)
                m.spots.clusterMacros = cur.spots.clusterMacros   // the dialog does not edit the cluster macros (the Spots window does)
                // the display filter is changed immediately by the "Band filter" / "Mode filter" windows and "RTTY only" - the dialog does not overwrite it
                m.spots.filterBands = cur.spots.filterBands; m.spots.filterModes = cur.spots.filterModes
                m.spots.filterOtherBands = cur.spots.filterOtherBands; m.spots.previousFilterModes = cur.spots.previousFilterModes
                take(\.contest.enabled); take(\.contest.format); take(\.contest.name); take(\.contest.category); take(\.contest.exchange)
                take(\.contest.nextSerial); take(\.contest.start); take(\.contest.preset)
                take(\.decoders.secondEnabled); take(\.decoders.secondDemod); take(\.decoders.channelsEnabled)
                take(\.decoders.maxChannels); take(\.decoders.channelTimeoutS); take(\.decoders.showChannelMarks)
                take(\.esm.enabled); take(\.esm.mode); take(\.esm.runCQ); take(\.esm.runExchange); take(\.esm.runTU)
                take(\.esm.spMyCall); take(\.esm.spExchange); take(\.esm.agn)
                return m
            }
            do { try self.settingsStore.save(merge(self.settings)) } catch { self.note(L("Nastavení nelze uložit: %@", "\(error)")) }
            if let app = self.app, await app.engine.state != .rx { await app.rxNow() }
            await self.stopNow()
            // merge again: a .contestSerial may have arrived while stopping (a macro with %l)
            let merged = merge(self.settings)
            do { try self.settingsStore.save(merged) } catch { self.note(L("Nastavení nelze uložit: %@", "\(error)")) }
            let wasNotifying = self.settings.alerts.wantsNotifications
            self.settings = merged
            if merged.alerts.wantsNotifications, !wasNotifying { self.alertSink.requestNotificationAuthorization() }
            self.highlightVersion &+= 1
            self.syncDisplay()
            if !self.qtcEnabled { self.qtcReceive = nil; self.qtcPendingCache = nil }
            await self.startNow()
        }
    }

    // MARK: Events

    private func handle(_ e: AppEvent) {
        switch e {
        case .engine(.state(let s)):
            let prev = state
            state = s
            if s == .rx { txSentColumn = 0 }
            // MMTTY "Time stamp": the UTC time when switching to TX and back
            if settings.display.timestamps, prev != s {
                if prev == .rx, s != .stopped { appendRx("\r\n[\(Self.stampFmt.string(from: Date())) UTC TX]\r\n", echo: true) }
                else if s == .rx, prev != .stopped { appendRx("\r\n[\(Self.stampFmt.string(from: Date())) UTC RX]\r\n", echo: false) }
            }
            if s == .tx, !txDraft.isEmpty { Task { await self.sendDraft(mode: self.sendMode) } }   // transmit the text in progress right away
        case .engine(.modem(.rxText(let c, let echo))): appendRx(String(c), echo: echo)
        case .engine(.aux(let a)): handleAux(a)
        case .engine(.modem(.signal(let l, let sq))): signalLevel = l; squelchOpen = sq
        case .engine(.modem(.tuning(let t))): mark = t.mark; space = t.space
        case .engine(.modem(.shift(let f))): fig = f
        case .engine(.rig(let r)):
            let bandChanged = Bands.band(forHz: r.frequency) != Bands.band(forHz: rig?.frequency)
            rig = r
            updateHighlightBand()
            if bandChanged, !qso.call.isEmpty { Task { await self.refreshDupe() } }   // QSY to a different band
        case .engine(.error(let err)): note("\(err)")
        case .engine(.pttTimeout): note(L("PTT časovač vypnul vysílání"))
        case .error(let m): note(m)
        case .qsoChanged(let q):
            let callChanged = q.call != qso.call, freqChanged = q.frequency != qso.frequency
            qso = q
            if freqChanged { updateHighlightBand() }
            if q.call.isEmpty { esmProgress = ESM.Progress() }     // a new QSO (Clear, logged)
            if callChanged { updateSuperCheck(); Task { await self.refreshPrevious(); await self.refreshQTC() }; scheduleCallbook() }
            if callChanged || freqChanged { Task { await self.refreshDupe() } }
            if q.frequency != settings.log.manualFrequency {
                settings.log.manualFrequency = q.frequency
                try? settingsStore.save(settings)
            }
        case .qsoLogged(let r):
            addLoggedRecord(r)
            addToLogIndex(r)
            backupLogIfDue()
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
            // store only the parameters the user changes (the keys already in the settings plus the changed ones)
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
                settings.log.rxText = false                      // the menu toggle must not lie
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
        scanRxForAlerts(s, echo: echo)
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

    // MARK: Second decoder and channels

    public static let rx2Limit = 20_000
    public static let channelTextLimit = 80
    /// The second decoder's text and the counters for the incremental display.
    public private(set) var rx2Text = ""
    public private(set) var rx2AppendedTotal = 0
    public private(set) var rx2TrimmedTotal = 0
    /// The channels of the multi-channel decoder (in order of creation).
    public private(set) var decoderChannels: [DecoderChannel] = []

    func handleAux(_ a: AuxEvent) {
        switch a {
        case .secondText(let c): appendRx2(String(c))
        case .channelText(let id, let c):
            guard let i = decoderChannels.firstIndex(where: { $0.id == id }) else { return }   // the channel is already gone
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

    /// A change to the additional decoders' settings - it takes effect immediately (no restart) and is saved.
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

    /// The demodulator the second decoder is currently using (automatically different from the main one).
    public var secondDemodEffective: String {
        let main: String
        if case .string(let m)? = params["demodType"] { main = m } else { main = "iir" }
        return settings.decoders.auxConfig().resolvedSecondDemod(main: main)
    }

    /// "Tune": point the main decoder at the channel's mark.
    public func tuneChannel(_ id: Int) async {
        guard let ch = decoderChannels.first(where: { $0.id == id }) else { return }
        await tune(toMarkHz: ch.mark)
    }

    /// The last `n` characters as runs (text, echo) - to fill in the end of the display.
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

    // MARK: Logging the receive text to a file (MMTTY "Log Rx file")

    private var rxLog: RxTextLog?
    public var rxLogActive: Bool { rxLog != nil }

    /// Opens/closes the log according to the settings (after startup and after a settings change).
    func syncRxLog() {
        let l = settings.log
        guard l.rxText else { rxLog?.close(); rxLog = nil; return }
        if let r = rxLog, r.directory == l.rxDirectory, r.timestamps == l.rxTimestamps { return }
        rxLog?.close()
        rxLog = RxTextLog(directory: l.rxDirectory, timestamps: l.rxTimestamps)
    }

    /// The menu toggle - it is stored in the settings.
    public func setRxTextLog(_ on: Bool) {
        settings.log.rxText = on
        do { try settingsStore.save(settings) } catch { note(L("Nastavení nelze uložit: %@", "\(error)")) }
        syncRxLog()
    }

    /// Saves the contents of the receive window into a file (MMTTY "RxWindow to file").
    public func saveRxText(to url: URL) throws {
        try Data(rxPlainText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "").utf8)
            .write(to: url, options: .atomic)
    }
    public func clearRx() { rxTrimmedTotal += rxCharCount; rxRuns.removeAll(); rxCharCount = 0 }

    // MARK: Dupes and Super Check Partial

    /// The call in the QSO window is a dupe in the contest (same band; the mode only for a custom contest - `DupeCheck`).
    public private(set) var isDupe = false
    /// Suggestions below the Call field: calls containing the entered fragment and calls differing by one character.
    public private(set) var scpPartial: [String] = []
    public private(set) var scpNear: [String] = []
    public private(set) var scpCount = 0
    private var scpMaster: [String] = []
    private var historyCalls: Set<String> = []
    private(set) var superCheck = SuperCheck(calls: [])

    func refreshDupe() async { isDupe = await app?.dupe() ?? false }

    // MARK: Multipliers

    /// The contest multipliers worked (part of the score; recomputed only when the log or the contest changes); nil = no contest / a custom contest.
    public var multipliers: MultiplierTally? { score?.multipliers }
    /// The contest score: QSOs, dupes, points, multipliers and QTC (WAE) per band; nil = no contest / a custom contest.
    public private(set) var score: ScoreTally?
    /// The multiplier rules of the selected contest (including Makrothen, which has none); nil = no contest.
    public private(set) var multiplierRule: MultiplierRule?
    /// The multipliers a QSO with the call in the QSO window would bring (the NEW MULT label).
    public private(set) var newMultiplier = NewMultiplier(hits: [], band: nil)
    private var scoreCalculator: ScoreCalculator?
    private var multiplierKeyApplied: MultiplierKey?

    private struct MultiplierKey: Equatable { var contest: ContestSettings; var call: String; var locator: String }
    private var multiplierKey: MultiplierKey {
        var c = settings.contest; c.nextSerial = 0                     // the QSO number changes neither the multipliers nor the points
        return MultiplierKey(contest: c, call: settings.station.call.uppercased(), locator: ownLocator)
    }
    /// Our own locator for the Makrothen points (Settings → Station, otherwise the contest's sent exchange).
    private var ownLocator: String {
        settings.station.locator.isEmpty ? settings.contest.exchange.uppercased() : settings.station.locator.uppercased()
    }
    var countryDB: CountryDB? { app?.countries ?? CountryDB.shared }
    /// The sent exchange a contest preset needs from my station (URC territory, name + QTH …).
    public func defaultContestExchange(_ p: ContestPreset, station: Station) -> String {
        ContestCatalog.defaultExchange(p, station: station, countries: countryDB)
    }
    /// My own country (cty.dat primary prefix) for the contest rules.
    public func ownCountryPrefix(_ call: String) -> String? { countryDB?.lookup(call)?.primaryPrefix }

    /// The band of the current QSO: the rig when it is online, otherwise the manually entered frequency.
    public var currentBand: String? { Self.band(rig, qso) }
    private static func band(_ rig: RigStatus?, _ qso: QSOFields) -> String? {
        Bands.band(forHz: rig?.online == true ? rig?.frequency : qso.frequency)
    }

    /// The number of full multiplier recomputations (a test: logging a QSO does not recompute the whole log).
    private(set) var multiplierFullRecomputes = 0

    /// A logged QSO: into the log and incrementally into the score and the multipliers (without recomputing the whole log).
    private func addLoggedRecord(_ r: QSORecord) {
        logRecordsIncremental = true
        logRecords.insert(r, at: 0)
        logRecordsIncremental = false
        guard let calc = scoreCalculator, var t = score else { return }
        calc.add(r, to: &t)                                              // the contest window is pinned in the tally
        score = t
        refreshNewMultiplier()
    }

    func refreshMultipliers() {
        multiplierFullRecomputes += 1
        multiplierKeyApplied = multiplierKey
        let db = countryDB
        let own = db?.lookup(settings.station.call)?.primaryPrefix
        guard let rule = MultiplierRule.rule(for: settings.contest, ownCountry: own),
              let sRule = ScoreRule.rule(for: settings.contest) else {
            multiplierRule = nil; score = nil; scoreCalculator = nil; refreshNewMultiplier(); return
        }
        let calc = ScoreCalculator(rule: sRule, multiplierRule: rule, ownCall: settings.station.call, ownLocator: ownLocator) {
            call, wae in db?.lookup(call, wae: wae)
        }
        multiplierRule = rule; scoreCalculator = calc
        score = calc.tally(records: logRecords, qtc: qtcSeries, since: settings.contest.effectiveStart, until: settings.contest.end)
        refreshNewMultiplier()
    }

    private func refreshNewMultiplier() {
        var n = NewMultiplier(hits: [], band: nil)
        if let calc = scoreCalculator?.multipliers, let t = multipliers, !qso.call.isEmpty {
            n = t.newHits(calc.hits(call: qso.call, exchange: qso.exchangeRcvd), band: currentBand)
        }
        if n != newMultiplier { newMultiplier = n }
    }

    /// The MASTER.SCP file - in the settings folder (Application Support/mmtty4mac in the app; the tests have their own folder).
    public var scpURL: URL { settingsStore.url.deletingLastPathComponent().appendingPathComponent("MASTER.SCP") }

    /// Loads MASTER.SCP and the calls from the log (after startup and after switching logs).
    func loadSuperCheck() async {
        let url = scpURL
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

    /// Suggestions for a partially typed call (called while typing, before the field is committed).
    public func superCheckPreview(_ text: String) {
        guard settings.log.superCheck else { scpPartial = []; scpNear = []; return }
        let t = text.trimmingCharacters(in: .whitespaces).uppercased()
        scpPartial = superCheck.partial(t).filter { $0 != t }
        scpNear = superCheck.near(t)
    }

    /// The usual RTTY frequencies of the bands (kHz) for a manual choice without a rig.
    public static let bandPresets: [(String, Double)] = [("160m", 1838), ("80m", 3590), ("40m", 7040), ("30m", 10140),
        ("20m", 14080), ("17m", 18100), ("15m", 21080), ("12m", 24920), ("10m", 28080), ("6m", 50300)]

    /// Downloads the current MASTER.SCP (supercheckpartial.com) - only when the user asks for it.
    public func downloadSuperCheck() async throws -> Int {
        let src = URL(string: "https://www.supercheckpartial.com/MASTER.SCP")!
        let (data, resp) = try await URLSession.shared.data(from: src)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { throw QSOLogError.io(L("MASTER.SCP se nepodařilo stáhnout.")) }
        let calls = SuperCheck.parse(text)
        guard calls.count > 1000 else { throw QSOLogError.io(L("MASTER.SCP se nepodařilo stáhnout.")) }
        try FileManager.default.createDirectory(at: scpURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: scpURL, options: .atomic)
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

    // MARK: Playing a WAV into the receiver (MMTTY "Play")

    public private(set) var wavPlaying = false
    private var wavTask: Task<Void, Never>?
    private var wavToken = UUID()
    /// Maximum file length (samples after resampling to 11025 Hz ≈ 2 h).
    nonisolated static let wavMaxSamples = 11025 * 7200

    public enum WAVError: Error, LocalizedError {
        case tooLong
        public var errorDescription: String? { L("Soubor je delší než 2 hodiny.") }
    }

    /// Plays a WAV file (any sample rate, it is resampled to 11025 Hz) instead of the sound card input (MMTTY "Play").
    /// `speed` 1 = real time, 2–10 = faster, 0 = as fast as possible. It pauses during TX.
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

    /// The playback state for the control bar (pause, position 0…1, length in s).
    public private(set) var wavPaused = false
    public private(set) var wavProgress = 0.0
    public private(set) var wavDuration = 0.0

    public func pauseWAV(_ p: Bool) async {
        guard let engine = app?.engine else { return }
        await engine.setPlaybackPaused(p)
        wavPaused = await engine.playbackPaused
    }

    /// Seek to a fraction 0…1 of the file (0 = rewind to the start).
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

    // MARK: Recording the receive audio into a WAV file (MMTTY "Record WAVE")

    public private(set) var recordingURL: URL?
    public private(set) var recordingSeconds = 0.0
    private var recorder: WaveWriter?
    private var recordTask: Task<Void, Never>?

    /// Records the sound card input (after resampling to 11025 Hz, mono 16 bit) into a file.
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

    /// The QTC status for the station in the QSO window (only in the WAE format).
    public private(set) var qtcStatus: AppController.QTCStatus?
    public var qtcEnabled: Bool { settings.contest.enabled && settings.contest.format == .wae }

    public func refreshQTC() async {
        guard qtcEnabled, let app else { qtcStatus = nil; return }
        qtcStatus = await app.qtcStatus(for: qso.call)
    }

    /// All the stored series (Log window → QTC), newest first.
    public private(set) var qtcSeries: [QTCSeries] = [] {
        didSet { if score != nil { score?.setQTC(qtcSeries) } }   // the QTC points (WAE) within the contest window pinned in the tally
    }
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

    /// The series being received: the n/k header and the rows; `cursor` = the next row and field to fill in (0 time, 1 call, 2 number).
    public struct QTCReceiveDraft: Equatable, Sendable {
        public var number: Int?, count: Int?
        /// Who the series is being received from (the call in the QSO window at "Receive…" - the window may be cleared in the meantime).
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
        // the series may have arrived before the operator opened the receive view: start from the last mention of the other station
        // (e.g. "OK1XOE DE K3LR YES QTC 9/5 QRV?") within the last 3000 received characters
        let back = min(3000, rxAppendedTotal - rxTrimmedTotal)
        let tail = rxTail(back).filter { !$0.echo }.map(\.text).joined()
        let all = rxTail(back).map(\.text).joined()
        if !d.counterpart.isEmpty, tail.uppercased().contains(d.counterpart.uppercased()),
           let r = all.uppercased().range(of: d.counterpart.uppercased(), options: .backwards) {
            qtcRxStart = rxAppendedTotal - all.distance(from: r.lowerBound, to: all.endIndex)
        }
    }

    /// "QRV - receive": opens QTC reception and transmits QRV (the other station then sends the series).
    public func qtcQRVReceive() async {
        if qtcReceive == nil { startQTCReceive() }
        await qtcPhrase(.qrv)
    }
    public func cancelQTCReceive() { qtcReceive = nil }
    /// Manual editing of the series being received (the "n/k" header, a "HHMM CALL NNN" row; empty = delete).
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

    /// Parses the text received since QTC reception started: the n/k header, the "HHMM CALL NNN" rows in order
    /// (an unreadable row leaves an empty slot, so that AGN N asks for the right row) and a repeat "N HHMM CALL NNN …" at position N.
    public func qtcFillFromRx() {
        guard var d = qtcReceive else { return }
        // skip our own transmission (echo), but treat its place as an end of line: after my "AGN 8" the other station
        // often starts without a CR/LF and the text would run into the end of the series ("BKKA8 0803 …")
        let text = rxTail(rxAppendedTotal - qtcRxStart).map { $0.echo ? "\n" : $0.text }.joined()
        var lines: [QTCLine?] = Array(repeating: nil, count: 10)
        var next = 0
        for raw in text.components(separatedBy: CharacterSet(charactersIn: "\r\n")) where !raw.isEmpty {
            var rest = raw
            if raw.uppercased().contains("QTC"), let (n, k) = QTCText.parseHeader(raw) {
                d.number = n; d.count = k
                // a QTC row stuck right after the header (a lost CR/LF)
                let tok = raw.uppercased().split(separator: " ")
                guard let last = tok.lastIndex(where: { $0.contains("/") }) else { continue }
                rest = tok[(last + 1)...].joined(separator: " ")
                if rest.isEmpty { continue }
            }
            if let (idx, l) = QTCText.parseIndexedLine(rest) { lines[idx - 1] = l; continue }
            if let l = QTCText.parseLine(rest) {
                if next < lines.count, !lines.contains(l) { lines[next] = l; next += 1 }
            } else if QTCText.looksLikeLine(rest), next < lines.count {
                next += 1                                                  // a corrupted row: the slot stays empty
            }
        }
        d.lines = lines
        let k = d.count ?? 10
        d.row = min(lines.firstIndex { $0 == nil } ?? k, max(0, k - 1)); d.field = 0
        qtcReceive = d
    }

    /// Clicking a word during QTC reception: the n/k header, then in turn the time, the call and the number.
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

    /// Stores the received series (only the first k rows); returns true on success - only then confirm with R R ALL OK.
    @discardableResult
    public func qtcSaveReceived() async -> Bool {
        guard let app, let d = qtcReceive, let n = d.number else { note(L("QTC: chybí hlavička série (n/k)")); return false }
        let lines = d.lines.prefix(d.count ?? 10).compactMap { $0 }
        var ok = false
        await run("QTC") { try await app.saveReceivedQTC(counterpart: d.counterpart, number: n, declaredCount: d.count, lines: lines); ok = true }
        if ok { qtcReceive = nil; await refreshQTC() }
        return ok
    }

    /// The DXCC entity of the current call in the QSO window (nil = unknown).
    public var dxcc: CountryInfo? { qso.call.isEmpty ? nil : app?.country(for: qso.call) }

    /// The log (optionally for a period) in Cabrillo format, with a header from the station and contest settings.
    public func cabrilloText(from: Date? = nil, to: Date? = nil, contestOnly: Bool = false) async -> String {
        await app?.cabrillo(from: from, to: to, contestOnly: contestOnly) ?? ""
    }

    // MARK: Backups and log statistics

    /// A daily backup (at startup and after logging a QSO, once 24 h have passed since the last one) - in the background.
    /// At most one at a time; a failure is reported only once per session (otherwise the message would repeat after every QSO).
    @discardableResult
    func backupLogIfDue() -> Task<Void, Never>? {
        guard settings.log.backup, !autoBackupRunning else { return nil }
        autoBackupRunning = true
        let loc = logLocation, keep = settings.log.backupKeep
        return Task { [weak self] in
            let failure: String? = await Task.detached {
                guard LogBackup.isDue(loc) else { return nil }
                do { try LogBackup.backup(loc, keep: keep); return nil }
                catch LogBackup.BackupError.nothingToBackup { return nil }
                catch { return "\(error)" }
            }.value
            guard let self else { return }
            self.autoBackupRunning = false
            if let failure, !self.autoBackupFailureReported {
                self.autoBackupFailureReported = true
                self.note(L("Záloha logu selhala: %@", failure))
            }
        }
    }
    @ObservationIgnored private var autoBackupRunning = false
    @ObservationIgnored private var autoBackupFailureReported = false

    /// A manual backup (File menu) - the copying happens off the main thread; returns the backup folder.
    @discardableResult
    public func backupLogNow() async throws -> URL {
        let loc = logLocation, keep = settings.log.backupKeep
        return try await Task.detached { try LogBackup.backup(loc, keep: keep) }.value
    }

    public var backupDirectory: URL { LogBackup.directory(for: logLocation) }

    /// Log statistics; during a contest only since the contest started.
    public var logStats: LogStats { logStats(now: Date()) }
    public func logStats(now: Date) -> LogStats {
        LogStats(records: logRecords, now: now, since: settings.contest.enabled ? settings.contest.effectiveStart : nil)
    }

    // MARK: Log management (new, open, save as)

    public var logLocation: LogLocation {
        LogLocation(directory: URL(fileURLWithPath: settings.log.directory), name: settings.log.name)
    }

    public enum LogFileError: Error, LocalizedError {
        case exists(String), missing(String), noAccess(String)
        public var errorDescription: String? {
            switch self {
            case .noAccess(let n): return L("Bez přístupu ke složce logu „%@“.", n)
            case .exists(let n): return L("Log „%@“ už existuje – otevřete ho přes Otevřít log.", n)
            case .missing(let n): return L("Log „%@“ neexistuje.", n)
            }
        }
    }

    /// The sandbox lets the app into a folder outside its container only after the user chose it once; the bookmark
    /// keeps the access. nil = refused. The user may pick a different folder - the returned one counts.
    private func accessLogFolder(_ path: String, name: String) async -> URL? {
        var b = settings.log.bookmarks
        let u = await folderAccess.acquire(path, bookmarks: &b,
                                           message: L("RYRY potřebuje přístup ke složce s logem „%@“. Vyberte ji prosím.", name))
        if b != settings.log.bookmarks {
            settings.log.bookmarks = b
            do { try settingsStore.save(settings) } catch { note(L("Nastavení nelze uložit: %@", "\(error)")) }
        }
        return u
    }

    /// At start: the configured log folder, or - when the user refuses access - a folder inside the container,
    /// so logging always works and the user is told where the log is.
    private func ensureLogFolder() async {
        let dir: String
        if let u = await accessLogFolder(settings.log.directory, name: settings.log.name) {
            dir = u.path
        } else {
            dir = folderAccess.containerHome + "/Documents/RYRY"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            note(L("Bez přístupu ke složce logu. Log se ukládá do %@.", dir))
        }
        guard FolderBookmarks.key(dir) != FolderBookmarks.key(settings.log.directory) else { return }
        settings.log.directory = dir
        do { try settingsStore.save(settings) } catch { note(L("Nastavení nelze uložit: %@", "\(error)")) }
    }

    /// The log for a chosen file, in a folder the app may use (asks for access when needed).
    private func accessibleLocation(_ file: URL) async throws -> LogLocation {
        let loc = LogLocation(file: file)
        guard let dir = await accessLogFolder(loc.directory.path, name: loc.name) else { throw LogFileError.noAccess(loc.name) }
        return LogLocation(directory: dir, name: loc.name)
    }

    /// Switches to a different log (a restart as after Apply - while transmitting it first switches to RX).
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

    /// A new empty log (the contest serial numbers start from 1).
    public func newLog(file: URL) async throws {
        let loc = try await accessibleLocation(file)
        let fm = FileManager.default
        if fm.fileExists(atPath: loc.jsonlURL.path) || fm.fileExists(atPath: loc.adifURL.path) { throw LogFileError.exists(loc.name) }
        try fm.createDirectory(at: loc.directory, withIntermediateDirectories: true)
        await switchLog(to: loc, resetSerial: true)
    }

    /// Opens an existing log; an ADIF file from another program is converted (the original is kept as .orig). Returns a text for the user.
    @discardableResult
    public func openLog(file: URL) async throws -> String {
        let loc = try await accessibleLocation(file)
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

    /// Saves a copy of the log under a different name and keeps working in that copy.
    public func saveLogAs(file: URL) async throws {
        let dst = try await accessibleLocation(file)
        if let log = app?.log, !(await log.isADIFConsistent()) { try await log.rebuildADIF() }
        try logLocation.copy(to: dst)
        await switchLog(to: dst, resetSerial: false)
    }

    /// A copy of the ADIF log elsewhere (the log stays open).
    public func exportADIF(to url: URL) async throws {
        guard let log = app?.log else { throw QSOLogError.io(L("Log není k dispozici.")) }
        if !(await log.isADIFConsistent()) { try await log.rebuildADIF() }
        let src = logLocation.adifURL
        guard FileManager.default.fileExists(atPath: src.path) else { throw LogFileError.missing(logLocation.name) }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.copyItem(at: src, to: url)
    }

    /// ADIF import (e.g. a log converted from MMTTY); returns a text for the user.
    public func importADIF(_ url: URL) async throws -> String {
        guard let log = app?.log else { throw QSOLogError.io(L("Log není k dispozici.")) }
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let parsed = ADIF.importRecords(text)
        let r = try await log.importRecords(parsed.records)
        await refreshLog()
        return L("Importováno %ld spojení, duplicit %ld, neplatných záznamů %ld.", r.added, r.duplicates, parsed.skipped)
    }

    // MARK: Uploading (LoTW / eQSL / Club Log)

    /// Uploads the QSOs not uploaded yet to the service. A manual call returns a message for the alert; an automatic one (after logging)
    /// runs in the background, reports an error into the status bar (`note`) and returns nil.
    @discardableResult
    public func uploadPending(_ t: UploadTarget, automatic: Bool = false) async -> String? {
        guard let log = app?.log else { return automatic ? nil : L("Log není dostupný.") }
        guard !uploadsRunning.contains(t) else { return automatic ? nil : L("%@: nahrávání už běží.", t.title) }
        uploadsRunning.insert(t); defer { uploadsRunning.remove(t) }
        let coordinator = uploader, cfg = settings
        if t == .lotw {
            do {
                guard let h = try await coordinator.prepareLoTW(settings: cfg, log: log, logName: cfg.log.name) else {
                    return automatic ? nil : L("%@: žádná nenahraná spojení.", t.title)
                }
                // only a file opened in TQSL can have been sent - otherwise there is nothing to confirm
                pendingLoTW = h.openedInTQSL ? h : nil
                return h.openedInTQSL
                    ? L("ADIF pro LoTW je otevřený v TQSL (%@). Podepište a odešlete ho, pak potvrďte v RYRY.", h.file.lastPathComponent)
                    : L("TQSL nenalezen. ADIF pro LoTW je uložený ve Stažených souborech: %@. Nainstalujte TrustedQSL a otevřete ho v něm.", h.file.lastPathComponent)
            } catch {
                return "\(t.title): \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
            }
        }
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

    /// The LoTW file handed to TrustedQSL and waiting for the user's word that TQSL sent it (drives the Log window alert).
    public var pendingLoTW: LoTWHandoff?

    /// true = TQSL sent the QSOs: mark them as uploaded to LoTW; false = leave them for the next time.
    public func confirmLoTW(_ uploaded: Bool) async {
        guard let h = pendingLoTW else { return }
        pendingLoTW = nil
        guard uploaded, let log = app?.log else { return }
        do { try await log.markUploaded(ids: h.ids, target: .lotw) }
        catch { note(L("Nahráno, ale stav se nepodařilo zapsat do logu: %@", "\(error)")) }
        await refreshLog()
    }

    private func refreshLog() async {
        guard let log = app?.log else { return }
        logRecords = await log.query()
        rebuildLogIndex()
    }

    private func refreshParams() async {
        guard let app else { return }
        params = await app.modemParams()
        descriptors = await app.engine.parameterDescriptors()
        if case .double(let m)? = params["mark"] { mark = m }
        if case .double(let sh)? = params["shift"] { space = mark + sh }
    }

    // MARK: Actions

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
    /// Runs a macro; true = sent. The exchange / my own call also counts as sent for ESM.
    @discardableResult
    public func runMacro(_ i: Int) async -> Bool {
        guard let app else { return false }
        var ok = false
        await run(L("Makro F%ld", i + 1)) { try await app.runMacro(index: i); ok = true }
        if ok, !qso.call.isEmpty {
            var p = esmProgress.forCall(qso.call)
            if i == settings.esm.runExchange || i == settings.esm.spExchange { p.exchangeSent = true }
            if i == settings.esm.spMyCall { p.myCallSent = true }
            esmProgress = p
        }
        return ok
    }

    // MARK: ESM (Enter Sends Message)

    /// What has already been sent in the current QSO (the exchange, my own call).
    public private(set) var esmProgress = ESM.Progress()
    /// A request to move the focus in the QSO panel (the field's name); the view clears it once done.
    public var esmFocusField: String?
    var lastESMMacroForTesting: Int?
    var esmSendCountForTesting = 0
    /// esmEnter is currently running - a further Enter (held down, or a fast one) is ignored.
    public private(set) var esmBusy = false

    /// The macro for ESM is missing or empty (whitespace only) - Enter would key the transmitter with no text.
    public func esmMacroIsEmpty(_ i: Int) -> Bool {
        !settings.macros.indices.contains(i) || settings.macros[i].isBlank
    }

    /// ESM is in operation (enabled, with a contest turned on).
    public var esmActive: Bool { settings.esm.enabled && settings.contest.enabled }

    /// What Enter would send right now (for the hint in the QSO panel).
    public var esmStep: ESM.Step {
        guard settings.esm.enabled else { return .none }
        return ESM.step(mode: settings.esm.mode, contest: settings.contest, qso: qso, progress: esmProgress,
                        transmitting: state != .rx)
    }

    /// Switching Run / S&P (the QSO panel, a shortcut) - saved immediately.
    public func setESMMode(_ m: ESMMode) {
        guard settings.esm.mode != m else { return }
        settings.esm.mode = m
        do { try settingsStore.save(settings) } catch { note(L("Nastavení nelze uložit: %@", "\(error)")) }
    }
    public func toggleESMMode() { setESMMode(settings.esm.mode == .run ? .sp : .run) }

    /// Enter in the QSO window: sends the macro according to the mode and the state of the QSO (nothing during TX - the macro would be appended
    /// to the text being transmitted). Returns the field to move the focus to (nil = ESM inactive or TX).
    @discardableResult
    public func esmEnter() async -> String? {
        guard esmActive, !esmBusy, let app, state == .rx else { return nil }
        esmBusy = true                              // before the first await - a second Enter cannot get in here
        defer { esmBusy = false }
        let step = esmStep
        guard let i = ESM.macro(for: step, settings.esm) else {
            return ESM.nextFocus(after: step, qso: qso, contest: settings.contest)
        }
        guard !esmMacroIsEmpty(i) else {
            note(L("Makro %@ je prázdné – nastavte ho v Nastavení → Závod → ESM", settings.binding(for: .macro(i)).display))
            return nil
        }
        let text = settings.macros[i].text
        let logsItself = (step == .tu || step == .exchangeAndLog) && ESM.macroLogs(text)
        let handled = await app.logRequestsHandled
        guard await runMacro(i) else { return nil }
        lastESMMacroForTesting = i
        esmSendCountForTesting += 1
        if ESM.needsExplicitLog(step, macroText: text) {
            await logQSO()                          // the macro is already expanded - the call and the exchange have been sent
        } else if logsItself {
            // %l makes the controller log asynchronously (.logRequested) - wait, so that the old call / exchange
            // does not carry over into the next QSO (the panel's fields only pick up the value after the return)
            let deadline = ContinuousClock.now + .seconds(3)
            while await app.logRequestsHandled == handled, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        if step == .tu || step == .exchangeAndLog {
            qso = await app.qso
            if qso.call.isEmpty { esmProgress = ESM.Progress() }
        }
        return ESM.nextFocus(after: step, qso: qso, contest: settings.contest)
    }
    public func stopMacro() async { await app?.stopMacroRepeat() }
    public func runMessage(_ i: Int) async {
        guard let app else { return }
        let name = settings.messages.indices.contains(i) ? settings.messages[i].name : "\(i + 1)"
        await run(L("Zpráva %@", name)) { try await app.runMessage(index: i) }
    }

    /// Sends a part of the editor's content according to the mode (character = everything, word = up to the last space, line = up to the last line break).
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

    /// Transmits the contents of a text file (MMTTY "Send Text…").
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

    /// The source of a device's nominal and actual sample rate (UID, input?) - replaced in tests.
    public var clockRates: (String?, Bool) -> (nominal: Double, actual: Double)? = { uid, input in
        ClockCalibration.rates(deviceUID: uid, input: input)
    }

    /// Measures the clock deviation of the input and output devices (ppm) - the replacement for MMTTY's ClockAdj.
    /// The devices have to be running (the app is receiving); sampling happens twice a second and the result is the median.
    /// `inputUID`/`outputUID`: the devices selected in the dialog (the default is the stored setting).
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

    /// The right button in the spectrum: a notch, as in MMTTY.
    public func notchClick(hz: Double) async {
        guard let app else { return }
        await app.notchClick(hz: hz)
        await refreshParams()
    }

    /// The frequencies of the active notches for drawing (empty when LMS/notch is off).
    public var notchMarkers: [Double] {
        guard params["lms"] == .bool(true), params["lmsType"] == .string("notch") else { return [] }
        var r: [Double] = []
        if case .int(let n)? = params["notchFreq"], n > 0 { r.append(Double(n)) }
        if params["twoNotch"] == .bool(true), case .int(let n)? = params["notch2Freq"], n > 0 { r.append(Double(n)) }
        return r
    }

    // MARK: Spots (DX cluster, RBN)

    /// The spot configuration from the settings; nil when everything is off.
    func spotFeedConfig() -> SpotFeedConfig? {
        let p = settings.spots
        guard p.clusterEnabled || p.rbnEnabled else { return nil }
        var c = SpotFeedConfig(call: settings.station.call, filter: p.filter, maxAgeMinutes: p.maxAgeMinutes)
        if p.clusterEnabled { c.cluster = SpotEndpoint(host: p.clusterHost, port: UInt16(clamping: p.clusterPort), commands: p.clusterCommands) }
        if p.rbnEnabled { c.rbn = SpotEndpoint(host: p.rbnHost, port: UInt16(clamping: p.rbnPort)) }
        return c
    }

    private func startSpots() {
        guard let c = spotFeedConfig() else { spotFeed.stop(); return }
        if settings.station.call.trimmingCharacters(in: .whitespaces).isEmpty { note(L("Spoty: v nastavení Stanice chybí značka pro přihlášení.")) }
        spotFeed.start(c)
    }

    /// A change to the spot settings from the window - saved immediately. The band and mode filter, the waterfall labels and the cluster macros do not
    /// change the connection (the filter is display only, spots of all bands and modes are stored); other changes (server, enabling…) reconnect.
    public func setSpots(_ change: (inout SpotSettings) -> Void) {
        var p = settings.spots
        change(&p)
        guard p != settings.spots else { return }
        let old = settings.spots
        settings.spots = p
        do { try settingsStore.save(settings) } catch { note(L("Nastavení nelze uložit: %@", "\(error)")) }
        spotFeed.filter = p.filter                                       // the display filter takes effect immediately (both directions)
        guard app != nil else { return }
        var noReconnect = old
        noReconnect.showInWaterfall = p.showInWaterfall; noReconnect.clusterMacros = p.clusterMacros
        noReconnect.filterBands = p.filterBands; noReconnect.filterModes = p.filterModes
        noReconnect.filterOtherBands = p.filterOtherBands; noReconnect.previousFilterModes = p.previousFilterModes
        if noReconnect == p { return }                                   // display only, the connection does not change
        startSpots()
    }

    /// Double-clicking a spot: tunes the rig to the spot's frequency (plus the offset) and puts the call into the QSO window.
    /// Without a rig (or on a rig error) only the call is inserted.
    public func useSpot(_ spot: Spot) async {
        let off = min(max(settings.spots.offsetHz, SpotSettings.offsetRange.lowerBound), SpotSettings.offsetRange.upperBound)
        let hz = spot.frequencyHz + off
        if let app, settings.rig.type != .none {
            // never retune a keyed transmitter (a different band under load, someone else's frequency) - AppController guards this
            do { try await app.setFrequency(hz) }
            catch AppError.transmitting { note(L("Během vysílání se rig nepřelaďuje – spot použijte po přechodu na RX.")) }
            catch AppError.engineStopped { note(Self.engineStoppedMessage) }
            catch { note(L("Rig: frekvenci %@ kHz nelze nastavit: %@", String(format: "%.1f", hz / 1000), "\(error)")) }
        } else {
            await setQSOField("freq", String(format: "%.1f", spot.frequencyHz / 1000))   // without a rig: the spot's frequency goes into the log
        }
        await setQSOField("call", spot.call)
    }

    // MARK: Frequencies and bands (top bar)

    /// The result of entering a frequency.
    public enum TuneOutcome: Equatable, Sendable {
        case rig            // the rig was retuned
        case manual         // without a rig: the manual QSO frequency
        case rejectedTX     // the rig is not retuned while transmitting
        case notRunning     // the engine is not running (audio not started) - the rig is not connected
        case invalid        // invalid input
        case failed         // the rig did not accept the frequency
    }

    static var engineStoppedMessage: String { L("Engine neběží (zvuk nespuštěn?) – rig nelze přeladit.") }

    /// A request to open the frequency entry (a shortcut / the menu); the top bar shows it and clears the request.
    public var showFrequencyEntry = false

    /// Sets the frequency in kHz: with a rig it retunes the rig (in RX only, just like `useSpot`), without a rig it writes the manual QSO frequency.
    @discardableResult
    public func setFrequency(kHz: Double) async -> TuneOutcome {
        guard FrequencyInput.rangeKHz.contains(kHz) else {
            note(L("Neplatná frekvence – zadejte kHz v rozsahu 100 až 500 000."))
            return .invalid
        }
        if let app, settings.rig.type != .none {
            do { try await app.setFrequency(kHz * 1000); return .rig }
            catch AppError.transmitting {
                note(L("Během vysílání se rig nepřelaďuje – frekvenci zadejte po přechodu na RX."))
                return .rejectedTX
            } catch AppError.engineStopped {
                note(Self.engineStoppedMessage)
                return .notRunning
            } catch {
                note(L("Rig: frekvenci %@ kHz nelze nastavit: %@", String(format: "%.1f", kHz), "\(error)"))
                return .failed
            }
        }
        await setQSOField("freq", kHz == kHz.rounded() ? String(Int(kHz)) : String(kHz))
        return .manual
    }

    /// Input from a text field (kHz, both comma and period, optionally "kHz" / "MHz").
    @discardableResult
    public func setFrequency(text: String) async -> TuneOutcome {
        guard let k = FrequencyInput.parseKHz(text) else {
            note(L("Neplatná frekvence „%@“ – zadejte kHz v rozsahu 100 až 500 000.", text))
            return .invalid
        }
        return await setFrequency(kHz: k)
    }

    // MARK: Bearing and distance

    /// Our own position: the locator from Station, otherwise the center of our own call's DXCC entity.
    public var ownPosition: Geo.Position? {
        Geo.position(locator: settings.station.locator, country: app?.country(for: settings.station.call))
    }

    /// Bearing and distance to the other station: the locator from the QSO window, otherwise the center of its call's entity.
    public func beam(call: String, locator: String) -> Geo.Beam? {
        guard let own = ownPosition else { return nil }
        let c = call.trimmingCharacters(in: .whitespaces)
        guard let remote = Geo.position(locator: locator, country: c.isEmpty ? nil : app?.country(for: c)) else { return nil }
        return Geo.beam(own: own, remote: remote)
    }

    public var beamToRemote: Geo.Beam? { beam(call: qso.call, locator: qso.locator) }

    /// Clicking a band map label: the mark goes to the spot's audio position and the call into the QSO window (the rig is not retuned).
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

    // MARK: Call history

    /// Reloads the call history file (after the file on disk was edited).
    public func reloadCallHistory() { callHistoryPath = ""; callHistory = nil; syncCallHistory() }

    /// Hands the loaded history to the controller; for a new file it loads it in the background (tens of thousands of lines must not block the GUI).
    private func syncCallHistory() {
        callHistoryTask?.cancel(); callHistoryTask = nil
        let cfg = settings.callHistory
        guard cfg.enabled, !cfg.path.isEmpty else {
            callHistory = nil; callHistoryPath = ""; callHistoryCount = 0; callHistoryStatus = ""
            if let app { Task { await app.setCallHistory(nil) } }
            return
        }
        if callHistoryPath == cfg.path, let h = callHistory {
            if let app { Task { await app.setCallHistory(h) } }
            return
        }
        guard folderAccess.accessFile(cfg.path, bookmark: cfg.bookmark) != nil else {
            callHistory = nil; callHistoryPath = ""; callHistoryCount = 0
            callHistoryStatus = L("Soubor historie značek vyberte znovu (Nastavení → Závod → Historie značek) – bez toho ho aplikace v sandboxu nesmí číst.")
            if let app { Task { await app.setCallHistory(nil) } }
            return
        }
        let path = cfg.path
        callHistoryStatus = L("Načítám historii značek…")
        callHistoryTask = Task { [weak self] in
            do {
                let h = try await CallHistory.load(url: URL(fileURLWithPath: path))
                guard !Task.isCancelled, let self else { return }
                self.callHistory = h; self.callHistoryPath = path
                self.callHistoryCount = h.count; self.callHistoryStatus = ""
                await self.app?.setCallHistory(h)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.callHistory = nil; self.callHistoryPath = ""; self.callHistoryCount = 0
                self.callHistoryStatus = L("Historii značek nelze načíst: %@", error.localizedDescription)
            }
        }
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

    /// After a short delay it looks up the current call (a further change cancels the query).
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

    /// The "Test" button: logging in and looking up our own call using the values from the dialog (no cache).
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
        if qtcReceive != nil, qtcEnabled { qtcInsertWord(w); return }    // QTC reception takes precedence over the QSO window
        let word = w.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "/"))))
        let kind = WordClassifier.classify(word)
        // contest: once the call is entered, numbers and the exchange go into the received fields (MMTTY TMmttyWd::PBoxRxMouseDown)
        // PED: every clicked word is the other station's call
        if settings.contest.enabled, settings.contest.format == .ped {
            if !word.isEmpty { await setQSOField("call", String(word.uppercased().prefix(16))) }
            return
        }
        if settings.contest.enabled, !qso.call.isEmpty, kind != .call {
            for (field, v) in WordClassifier.contestUpdate(word, format: settings.contest.format,
                                                           serialMode: settings.contest.exchange.isEmpty,
                                                           roundup: settings.contest.isRoundupStateExchange,
                                                           serialOrCode: settings.contest.receivesSerialOrCode, current: qso) {
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

    /// Saves the cluster macros (10 items) - the connection does not change.
    public func saveClusterMacros(_ m: [Macro]) {
        var list = Array(m.prefix(SpotSettings.clusterMacroCount))
        while list.count < SpotSettings.clusterMacroCount { list.append(Macro(name: "", text: "")) }
        settings.spots.clusterMacros = list
        do { try settingsStore.save(settings) } catch { note(L("Makra nelze uložit: %@", "\(error)")) }
    }

    public func saveMessages(_ m: [Macro]) async {
        var s = settings; s.messages = m; settings = s
        await app?.setMessages(m)
        do { try settingsStore.save(s) } catch { note(L("Zprávy nelze uložit: %@", "\(error)")) }
    }

    // MARK: Import from MMTTY

    /// Reads Mmtty.ini (changes nothing); the parameters are validated against the modem's descriptions.
    public func previewMMTTYImport(_ url: URL) throws -> MMTTYImportResult {
        let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size <= MMTTYImport.maxFileSize else { throw MMTTYImportError.tooLarge }
        let data = try Data(contentsOf: url)
        let descs = descriptors.isEmpty ? ((try? RTTYModem())?.parameters ?? []) : descriptors
        return MMTTYImport.parse(data: data, descriptors: descs)
    }

    /// Saves the selected parts of the import the same way the dialogs do: macros/messages (`saveMacros`/`saveMessages`),
    /// parameters (`setParam`), station and shortcuts (`applySettings` - which restarts the audio).
    public enum MMTTYImportError: Error, LocalizedError {
        case tooLarge
        public var errorDescription: String? { L("Soubor je větší než 1 MB – nejde o Mmtty.ini; nic se neimportuje.") }
    }

    /// The import overwrites the macros ESM refers to by index - the preview warns about that (and offers to turn ESM off).
    public func mmttyImportAffectsESM(_ r: MMTTYImportResult, options: MMTTYImportOptions) -> Bool {
        settings.esm.enabled && options.contains(.macros) && r.macros != nil
    }

    /// `disableESM`: turn ESM off after importing the macros (the index-based macro assignment needs checking).
    public func applyMMTTYImport(_ r: MMTTYImportResult, options: MMTTYImportOptions, disableESM: Bool = false) async {
        // neither the parameters nor the macros may change in the middle of a transmission / CQ loop
        await stopMacro()
        await rxNow()                                   // does nothing in RX
        if disableESM, mmttyImportAffectsESM(r, options: options) {
            settings.esm.enabled = false
            do { try settingsStore.save(settings) } catch { note(L("Nastavení nelze uložit: %@", "\(error)")) }
        }
        if options.contains(.macros), let m = r.macros { await saveMacros(m) }
        if options.contains(.messages), let m = r.messages { await saveMessages(m) }
        if options.contains(.modem) {
            // mark before shift: setParam(mark) preserves the shift, setParam(shift) then sets space
            for id in r.rtty.keys.sorted(by: { ($0 == "mark" ? 0 : $0 == "shift" ? 1 : 2, $0) < ($1 == "mark" ? 0 : $1 == "shift" ? 1 : 2, $1) }) {
                guard let v = r.rtty[id] else { continue }
                if app != nil { await setParam(id, v) } else {
                    settings.rtty[id] = v
                    try? settingsStore.save(settings)
                }
            }
        }
        var opts = options; opts.remove([.macros, .messages, .modem])
        if !opts.isEmpty, (opts.contains(.station) && r.station != nil) || (opts.contains(.shortcuts) && !r.shortcuts.isEmpty) {
            let base = settings
            var s = settings
            for w in r.apply(to: &s, options: opts) { note(w) }
            await applySettings(s, baseline: base)
        }
    }

    public func profiles() -> [Profile?] { profileStore.load() }
    public func loadProfile(_ slot: Int) async {
        guard let app else { return }
        var ok = false
        await run(L("Profil")) { try await app.loadProfile(slot); ok = true }
        await refreshParams()
        guard ok else { return }                    // a profile that was not loaded does not change the settings
        settings.rtty = params
        try? settingsStore.save(settings)
    }
    public func saveProfile(_ slot: Int, name: String) async {
        guard let app else { return }
        await run(L("Profil")) { try await app.saveProfile(slot, name: name) }
        profileNames = profileStore.load().map { $0?.name }
    }

    /// The HAM button: the standard 170 Hz shift.
    public func hamShift() async { await setParam("shift", .double(170)) }

    /// The mouse wheel in the waterfall: the squelch level in steps of 16 (MMTTY 0–1024).
    public func adjustSquelch(steps: Int) async {
        guard case .double(let v)? = param("squelchLevel") else { return }
        // the target is computed synchronously (fast wheel events accumulate) and written out gradually
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

    /// A single read of a scope batch (called by the spectrum loop; manually in tests). A frozen scope is not overwritten.
    public func pollDemodScope() async {
        guard demodScopeEnabled, !scopeFrozen, let d = await app?.engine.demodScope() else { return }
        demodScope = d
    }

    /// A single read of the XY points (called by the spectrum loop; manually in tests).
    public func pollXY() async {
        guard xyEnabled, let pts = await app?.engine.xyScope() else { return }
        xyPoints = pts
    }
}
