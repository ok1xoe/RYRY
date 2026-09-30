// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation

/// A radio model in hamlib (`rigctld -l`).
public struct HamlibModel: Sendable, Equatable, Hashable, Identifiable {
    public var id: Int
    public var manufacturer: String
    public var model: String
    public var title: String { "\(manufacturer) \(model)" }
    public init(id: Int, manufacturer: String, model: String) { self.id = id; self.manufacturer = manufacturer; self.model = model }
}

/// hamlib started by the app itself: `rigctld` with the model, port and speed from Settings
/// on a local TCP port; it is controlled through HamlibClient and terminated on disconnect.
public final class ManagedHamlibRig: Rig, @unchecked Sendable {
    public let name: String
    let binary: String, model: Int, serialPort: String, baud: Int, tcpPort: UInt16
    let startTimeout: Duration
    private let client: HamlibClient
    private let lock = NSLock()
    private var process: Process?
    private var stderrText = ""
    private var failedAt: ContinuousClock.Instant?
    /// After an explicit disconnect() rigctld is not started again (until a connect() arrives).
    private var closedByOwner = false
    /// A start in progress – concurrent requests (poll, PTT, test) wait for it and do not start another rigctld.
    private var starting: Task<Void, Error>?
    /// How many times rigctld has been started (for tests).
    public private(set) var startCount = 0
    /// After a failed start rigctld is not started again sooner than after this time (rig polling keeps running).
    static let retryAfter: Duration = .seconds(10)

    public init(binary: String, model: Int, serialPort: String, baud: Int, tcpPort: UInt16 = 4534,
                startTimeout: Duration = .seconds(5)) {
        self.binary = binary; self.model = model; self.serialPort = serialPort; self.baud = baud
        self.tcpPort = tcpPort; self.startTimeout = startTimeout
        client = HamlibClient(host: "127.0.0.1", port: tcpPort)
        name = "hamlib #\(model) \(serialPort)"
    }

    deinit { process?.terminate() }

    /// rigctld from Homebrew (both Apple Silicon and Intel) or from PATH.
    public static func findRigctld(extra: [String] = []) -> String? {
        var c = extra + ["/opt/homebrew/bin/rigctld", "/usr/local/bin/rigctld"]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            c += path.split(separator: ":").map { "\($0)/rigctld" }
        }
        return c.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func arguments(model: Int, serialPort: String, baud: Int, tcpPort: UInt16) -> [String] {
        var a = ["-m", "\(model)"]
        if !serialPort.isEmpty { a += ["-r", serialPort] }
        if baud > 0 { a += ["-s", "\(baud)"] }
        return a + ["-T", "127.0.0.1", "-t", "\(tcpPort)"]
    }

    /// Parses `rigctld -l` using the column positions in the header.
    public static func parseModels(_ text: String) -> [HamlibModel] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let header = lines.first(where: { $0.contains("Mfg") && $0.contains("Model") }),
              let mfg = header.range(of: "Mfg"), let mod = header.range(of: "Model"), let ver = header.range(of: "Version")
        else { return [] }
        let cMfg = header.distance(from: header.startIndex, to: mfg.lowerBound)
        let cMod = header.distance(from: header.startIndex, to: mod.lowerBound)
        let cVer = header.distance(from: header.startIndex, to: ver.lowerBound)
        func col(_ s: String, _ a: Int, _ b: Int) -> String {
            let ch = Array(s)
            guard a < ch.count else { return "" }
            return String(ch[a..<min(b, ch.count)]).trimmingCharacters(in: .whitespaces)
        }
        return lines.compactMap { l in
            guard let id = Int(col(l, 0, cMfg)) else { return nil }
            let m = col(l, cMod, cVer)
            return m.isEmpty ? nil : HamlibModel(id: id, manufacturer: col(l, cMfg, cMod), model: m)
        }
    }

    /// The list of models from the installed rigctld (sorted by manufacturer and model).
    public static func availableModels(binary: String) -> [HamlibModel] {
        let p = Process(); p.executableURL = URL(fileURLWithPath: binary); p.arguments = ["-l"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return parseModels(String(decoding: data, as: UTF8.self)).sorted { ($0.manufacturer, $0.model) < ($1.manufacturer, $1.model) }
    }

    public var isRunning: Bool { lock.withLock { process?.isRunning ?? false } }
    public var isIdle: Bool { !isRunning }

    private func startProcess() throws {
        if isRunning { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = Self.arguments(model: model, serialPort: serialPort, baud: baud, tcpPort: tcpPort)
        let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let self else { return }
            self.lock.withLock { self.stderrText = String((self.stderrText + String(decoding: d, as: UTF8.self)).suffix(2000)) }
        }
        do { try p.run() } catch { throw RigError.protocolError("rigctld: \(error.localizedDescription)") }
        lock.withLock { process = p; stderrText = ""; startCount += 1 }
    }

    private func stopProcess() {
        let p = lock.withLock { () -> Process? in let p = process; process = nil; return p }
        guard let p else { return }
        (p.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        guard p.isRunning else { return }
        p.terminate()
        // if rigctld does not react to SIGTERM within 2 s, kill it (otherwise the Engine stop and app exit would hang)
        let deadline = Date().addingTimeInterval(2)
        while p.isRunning, Date() < deadline { usleep(20_000) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL); p.waitUntilExit() }
    }

    public func connect() async throws {
        let t: Task<Void, Error> = lock.withLock {
            closedByOwner = false
            if let s = starting { return s }
            let s = Task { try await self.start() }
            starting = s
            return s
        }
        defer { lock.withLock { if starting == t { starting = nil } } }
        do { try await t.value } catch {
            lock.withLock { failedAt = .now }
            throw error
        }
        lock.withLock { failedAt = nil }
    }

    /// Lazy start on the first request (the Engine does not connect the rig separately).
    private func ensureStarted() async throws {
        if isRunning { return }
        if lock.withLock({ closedByOwner }) { throw RigError.offline }
        if let f = lock.withLock({ failedAt }), ContinuousClock.now - f < Self.retryAfter { throw RigError.offline }
        try await connect()
    }

    private func start() async throws {
        if isRunning { return }
        // the port is already taken (rigctld after an app crash, another program) – do not attach to a foreign process
        if (try? await client.connect()) != nil {
            await client.disconnect()
            throw RigError.protocolError("TCP port \(tcpPort) je obsazený (běží jiný rigctld?) – zvol jiný místní port")
        }
        try startProcess()
        let deadline = ContinuousClock.now + startTimeout
        while true {
            do {
                try await client.connect()
                // rigctld 4.x listens even when the port failed – verify that the radio responds
                do { _ = try await client.frequency() } catch {
                    try? await Task.sleep(for: .milliseconds(200))
                    let msg = lock.withLock { stderrText }.split(separator: "\n").last.map(String.init) ?? ""
                    await client.disconnect(); stopProcess()
                    throw RigError.protocolError(msg.isEmpty ? "rádio neodpovídá (\(error))" : "rigctld: \(msg)")
                }
                guard isRunning else { await client.disconnect(); throw RigError.protocolError("rigctld skončil") }
                return
            } catch let e as RigError where !(e == .offline || e == .timeout) { throw e } catch {
                let alive = isRunning
                if !alive || ContinuousClock.now >= deadline {
                    let msg = lock.withLock { stderrText }.split(separator: "\n").last.map(String.init) ?? ""
                    stopProcess()
                    throw RigError.protocolError(msg.isEmpty ? "rigctld se nespustil" : "rigctld: \(msg)")
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    public func disconnect() async {
        lock.withLock { closedByOwner = true }
        await client.disconnect()
        stopProcess()
    }

    public func frequency() async throws -> Double { try await ensureStarted(); return try await client.frequency() }
    public func setFrequency(_ hz: Double) async throws { try await ensureStarted(); try await client.setFrequency(hz) }
    public func mode() async throws -> String { try await ensureStarted(); return try await client.mode() }
    public func setMode(_ mode: String) async throws { try await ensureStarted(); try await client.setMode(mode) }
    public func setPTT(_ on: Bool) async throws { try await ensureStarted(); try await client.setPTT(on) }
}
