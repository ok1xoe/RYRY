// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Localization
import QSOLog
import Security

// MARK: Errors and result

public enum UploadError: Error, Equatable, Sendable, LocalizedError {
    case notConfigured(String)
    case network(String)
    case authFailed(String)
    case rejected(String)
    case http(Int, String)
    case unexpectedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let s): return L("Nenastaveno: %@", s)
        case .network(let m): return L("Síťová chyba: %@", m)
        case .authFailed(let m): return L("Přihlášení odmítnuto: %@", m)
        case .rejected(let m): return L("Služba záznamy odmítla: %@", m)
        case .http(let c, let m): return L("Chyba serveru %ld: %@", c, m)
        case .unexpectedResponse(let m): return L("Neočekávaná odpověď služby: %@", m)
        }
    }
}

/// The upload result: which QSOs should be marked as uploaded + a message for the user.
public struct UploadOutcome: Sendable, Equatable {
    public var target: UploadTarget
    public var uploadedIDs: [UUID]
    /// QSOs that could not be sent (e.g. a missing frequency/band).
    public var skipped: Int
    public var message: String
    public init(target: UploadTarget, uploadedIDs: [UUID], skipped: Int = 0, message: String) {
        self.target = target; self.uploadedIDs = uploadedIDs; self.skipped = skipped; self.message = message
    }
}

public extension UploadTarget {
    var title: String {
        switch self { case .lotw: return "LoTW"; case .eqsl: return "eQSL"; case .clublog: return "Club Log" }
    }
}

// MARK: Selecting the not yet uploaded

public enum UploadSelection {
    /// QSOs not yet uploaded to the service; the services reject QSOs without a band (frequency) → `missingBand`.
    public static func pending(_ records: [QSORecord], target: UploadTarget) -> (eligible: [QSORecord], missingBand: Int) {
        let open = records.filter { !$0.isUploaded(target) }.sorted { $0.timeOn < $1.timeOn }
        let ok = open.filter { $0.band != nil }
        return (ok, open.count - ok.count)
    }

    /// ADIF with a header (optional extra header fields, e.g. EQSL_USER) and records without the upload flags.
    public static func adif(_ records: [QSORecord], headerFields: String = "") -> String {
        "RYRY upload\n" + ADIF.field("ADIF_VER", ADIF.version) + ADIF.field("PROGRAMID", "RYRY")
            + headerFields + "<EOH>\n" + records.map(ADIF.uploadRecord).joined()
    }
}

// MARK: HTTP

public struct HTTPResult: Sendable { public var status: Int; public var body: Data
    public init(status: Int, body: Data) { self.status = status; self.body = body }
    public var text: String { String(decoding: body, as: UTF8.self) }
}

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResult
}

public struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession
    public init(timeout: TimeInterval = 60) {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout; c.timeoutIntervalForResource = timeout * 2
        session = URLSession(configuration: c)
    }
    public func send(_ request: URLRequest) async throws -> HTTPResult {
        do {
            let (d, r) = try await session.data(for: request)
            return HTTPResult(status: (r as? HTTPURLResponse)?.statusCode ?? 0, body: d)
        } catch { throw UploadError.network(error.localizedDescription) }
    }
}

/// multipart/form-data (RFC 7578).
public struct MultipartBody: Sendable {
    public let boundary: String
    private var data = Data()
    public init(boundary: String = "mmtty4mac-\(UUID().uuidString)") { self.boundary = boundary }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    static func quoted(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    }
    public mutating func addField(_ name: String, _ value: String) {
        data.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(Self.quoted(name))\"\r\n\r\n\(value)\r\n".utf8))
    }
    public mutating func addFile(_ name: String, filename: String, contentType: String = "text/plain", _ content: Data) {
        data.append(Data(("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(Self.quoted(name))\"; filename=\"\(Self.quoted(filename))\"\r\n"
                          + "Content-Type: \(contentType)\r\n\r\n").utf8))
        data.append(content); data.append(Data("\r\n".utf8))
    }
    public var body: Data { data + Data("--\(boundary)--\r\n".utf8) }

    public func request(url: URL) -> URLRequest {
        var r = URLRequest(url: url); r.httpMethod = "POST"
        r.setValue(contentType, forHTTPHeaderField: "Content-Type"); r.httpBody = body
        r.setValue("RYRY", forHTTPHeaderField: "User-Agent")
        return r
    }
}

/// application/x-www-form-urlencoded.
public enum FormBody {
    public static func request(url: URL, _ fields: [(String, String)]) -> URLRequest {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        var r = URLRequest(url: url); r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.setValue("RYRY", forHTTPHeaderField: "User-Agent")
        r.httpBody = Data(fields.map { enc($0.0) + "=" + enc($0.1) }.joined(separator: "&").utf8)
        return r
    }
}

// MARK: Keychain

public protocol UploadSecretStore: Sendable {
    func get(service: String, account: String) -> String?
    func set(_ value: String?, service: String, account: String) throws
}

public enum SecretServices {
    public static let prefix = "cz.ok1xoe.mmtty4mac."
    public static let eqsl = prefix + "eqsl"
    public static let clublog = prefix + "clublog"
    public static let clublogAPIKey = prefix + "clublog-apikey"
    public static let account = "password"
}

public struct UploadKeychainStore: UploadSecretStore {
    public init() {}
    public func get(service: String, account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    public func set(_ value: String?, service: String, account: String) throws {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        guard let value, !value.isEmpty else {
            let st = SecItemDelete(base as CFDictionary)
            if st != errSecSuccess && st != errSecItemNotFound { throw UploadError.notConfigured(L("Klíčenka (chyba %ld)", Int(st))) }
            return
        }
        let data = Data(value.utf8)
        let st = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if st == errSecItemNotFound {
            var add = base; add[kSecValueData as String] = data
            let s2 = SecItemAdd(add as CFDictionary, nil)
            if s2 != errSecSuccess { throw UploadError.notConfigured(L("Klíčenka (chyba %ld)", Int(s2))) }
        } else if st != errSecSuccess { throw UploadError.notConfigured(L("Klíčenka (chyba %ld)", Int(st))) }
    }
}

public final class UploadMemoryStore: UploadSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]
    public init() {}
    public func get(service: String, account: String) -> String? { lock.withLock { items[service + "|" + account] } }
    public func set(_ value: String?, service: String, account: String) throws {
        lock.withLock { items[service + "|" + account] = (value?.isEmpty ?? true) ? nil : value }
    }
}
