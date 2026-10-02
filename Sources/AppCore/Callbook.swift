// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Localization
import Settings

/// Result of a callbook lookup.
public struct CallbookEntry: Equatable, Sendable {
    public var call: String, name: String, qth: String, grid: String, country: String
    public init(call: String, name: String, qth: String, grid: String, country: String) {
        self.call = call; self.name = name; self.qth = qth; self.grid = grid; self.country = country
    }
}

public enum CallbookError: Error, Equatable, Sendable, LocalizedError {
    case login(String), sessionExpired, service(String), network(String), invalidResponse
    public var errorDescription: String? {
        switch self {
        case .login(let m): return m.isEmpty ? L("chybné přihlášení") : L("chybné přihlášení: %@", m)
        case .sessionExpired: return L("vypršela relace")
        case .service(let m): return m
        case .network(let m): return L("síť: %@", m)
        case .invalidResponse: return L("neplatná odpověď")
        }
    }
}

/// Network for the callbook (a mock in tests).
public typealias HTTPFetcher = @Sendable (URL) async throws -> Data

public protocol CallbookService: Sendable {
    /// The displayed name of the service ("QRZ.com").
    var name: String { get }
    /// nil = the call was not found.
    func lookup(_ call: String) async throws -> CallbookEntry?
}

public enum CallbookFactory {
    public static func make(_ kind: CallbookKind, username: String, password: String,
                            fetcher: @escaping HTTPFetcher) -> (any CallbookService)? {
        switch kind {
        case .none: return nil
        case .qrz: return QRZCallbook(username: username, password: password, fetcher: fetcher)
        case .hamqth: return HamQTHCallbook(username: username, password: password, fetcher: fetcher)
        }
    }

    /// The real network: HTTPS with a time limit, only a 200 response.
    public static let liveFetcher: HTTPFetcher = { url in
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10; cfg.timeoutIntervalForResource = 15
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (d, r) = try await session.data(from: url)
            if let h = r as? HTTPURLResponse, h.statusCode != 200 { throw CallbookError.network("HTTP \(h.statusCode)") }
            return d
        } catch let e as CallbookError { throw e } catch is CancellationError { throw CancellationError() } catch {
            throw CallbookError.network(error.localizedDescription)
        }
    }
}

// MARK: XML

/// Flattening of XML to "leaf → text" (names in lower case, without namespaces); enough for callbook responses.
enum FlatXML {
    static func parse(_ data: Data) throws -> [String: String] {
        let d = Delegate()
        let p = XMLParser(data: data)
        p.delegate = d
        guard p.parse(), !d.values.isEmpty else { throw CallbookError.invalidResponse }
        return d.values
    }
    private final class Delegate: NSObject, XMLParserDelegate {
        var values: [String: String] = [:]
        private var stack: [String] = [], text = ""
        func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            stack.append(e.lowercased()); text = ""
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
        func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let k = stack.last, values[k] == nil { values[k] = t }
            stack.removeLast(); text = ""
        }
    }
}

/// Percent-encoding of a parameter value (only unreserved characters stay).
func callbookEncode(_ s: String) -> String {
    s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? s
}

private func normalize(_ call: String) -> String { call.trimmingCharacters(in: .whitespaces).uppercased() }

/// Shared session: a single login even with concurrent queries.
private actor SessionHolder {
    private var value: String?
    private var pending: Task<String, Error>?
    func get(login: @escaping @Sendable () async throws -> String) async throws -> String {
        if let v = value { return v }
        if let t = pending { return try await t.value }
        let t = Task { try await login() }
        pending = t
        defer { pending = nil }
        let v = try await t.value
        value = v
        return v
    }
    func invalidate() { value = nil }
}

// MARK: QRZ.com

public struct QRZCallbook: CallbookService {
    public let name = "QRZ.com"
    private let username: String, password: String, fetcher: HTTPFetcher
    private let session = SessionHolder()
    static let base = "https://xmldata.qrz.com/xml/current/"

    public init(username: String, password: String, fetcher: @escaping HTTPFetcher) {
        self.username = username; self.password = password; self.fetcher = fetcher
    }

    private func fetch(_ s: String) async throws -> [String: String] {
        guard let url = URL(string: s) else { throw CallbookError.invalidResponse }
        return try FlatXML.parse(try await fetcher(url))
    }

    private func login() async throws -> String {
        let r = try await fetch("\(Self.base)?username=\(callbookEncode(username));password=\(callbookEncode(password));agent=RYRY")
        if let e = r["error"] { throw CallbookError.login(e.trimmingCharacters(in: .whitespaces)) }
        guard let k = r["key"] else { throw CallbookError.invalidResponse }
        return k
    }

    public func lookup(_ call: String) async throws -> CallbookEntry? {
        let c = normalize(call)
        for attempt in 0..<2 {
            let key = try await session.get { try await self.login() }
            let r = try await fetch("\(Self.base)?s=\(callbookEncode(key));callsign=\(callbookEncode(c))")
            if let e = r["error"] {
                let l = e.lowercased()
                if l.contains("not found") { return nil }
                if l.contains("timeout") || l.contains("session") || l.contains("invalid key") {
                    await session.invalidate()
                    if attempt == 0 { continue }
                    throw CallbookError.sessionExpired
                }
                throw CallbookError.service(e.trimmingCharacters(in: .whitespaces))
            }
            guard r["call"] != nil || r["name"] != nil || r["fname"] != nil else { return nil }
            return CallbookEntry(call: (r["call"] ?? c).uppercased(),
                                 name: [r["fname"], r["name"]].compactMap { $0 }.joined(separator: " "),
                                 qth: r["addr2"] ?? "", grid: (r["grid"] ?? "").uppercased(), country: r["country"] ?? "")
        }
        throw CallbookError.sessionExpired
    }
}

// MARK: HamQTH

public struct HamQTHCallbook: CallbookService {
    public let name = "HamQTH"
    private let username: String, password: String, fetcher: HTTPFetcher
    private let session = SessionHolder()
    static let base = "https://www.hamqth.com/xml.php"

    public init(username: String, password: String, fetcher: @escaping HTTPFetcher) {
        self.username = username; self.password = password; self.fetcher = fetcher
    }

    private func fetch(_ s: String) async throws -> [String: String] {
        guard let url = URL(string: s) else { throw CallbookError.invalidResponse }
        return try FlatXML.parse(try await fetcher(url))
    }

    private func login() async throws -> String {
        let r = try await fetch("\(Self.base)?u=\(callbookEncode(username))&p=\(callbookEncode(password))")
        if let e = r["error"] { throw CallbookError.login(e.trimmingCharacters(in: .whitespaces)) }
        guard let k = r["session_id"] else { throw CallbookError.invalidResponse }
        return k
    }

    public func lookup(_ call: String) async throws -> CallbookEntry? {
        let c = normalize(call)
        for attempt in 0..<2 {
            let id = try await session.get { try await self.login() }
            let r = try await fetch("\(Self.base)?id=\(callbookEncode(id))&callsign=\(callbookEncode(c))&prg=RYRY")
            if let e = r["error"] {
                let l = e.lowercased()
                if l.contains("not found") { return nil }
                if l.contains("session") {
                    await session.invalidate()
                    if attempt == 0 { continue }
                    throw CallbookError.sessionExpired
                }
                throw CallbookError.service(e.trimmingCharacters(in: .whitespaces))
            }
            guard r["callsign"] != nil else { return nil }
            return CallbookEntry(call: (r["callsign"] ?? c).uppercased(), name: r["nick"] ?? r["adr_name"] ?? "",
                                 qth: r["qth"] ?? "", grid: (r["grid"] ?? "").uppercased(), country: r["country"] ?? "")
        }
        throw CallbookError.sessionExpired
    }
}

// MARK: Cache and concurrency limit

private actor Limiter {
    private var free: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ n: Int) { free = max(1, n) }
    func acquire() async {
        if free > 0 { free -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { free += 1 } else { waiters.removeFirst().resume() }
    }
}

/// In-memory cache of the results (including "not found") + a limit of concurrent queries; errors are not cached.
public actor CachingCallbook: CallbookService {
    public nonisolated let name: String
    private let base: any CallbookService
    private let limiter: Limiter
    private var cache: [String: CallbookEntry?] = [:]
    private var inflight: [String: Task<CallbookEntry?, Error>] = [:]
    private let capacity: Int

    public init(_ base: any CallbookService, maxConcurrent: Int = 2, capacity: Int = 500) {
        self.base = base; name = base.name; limiter = Limiter(maxConcurrent); self.capacity = capacity
    }

    public func clear() { cache.removeAll() }

    public func lookup(_ call: String) async throws -> CallbookEntry? {
        let c = normalize(call)
        if let hit = cache[c] { return hit }
        if let t = inflight[c] { return try await t.value }
        let base = self.base, limiter = self.limiter
        let t = Task<CallbookEntry?, Error> {
            await limiter.acquire()
            do { let r = try await base.lookup(c); await limiter.release(); return r }
            catch { await limiter.release(); throw error }
        }
        inflight[c] = t
        defer { inflight[c] = nil }
        let r = try await t.value
        if cache.count >= capacity { cache.removeAll() }
        cache[c] = .some(r)
        return r
    }
}
