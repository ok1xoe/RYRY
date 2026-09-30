// Copyright 2026 OK1XOE (mmtty4mac), LGPL v3
import Foundation
import Security

/// Password storage (Keychain). Service = e.g. "qrz", "hamqth"; account = the user name.
public protocol SecretStore: Sendable {
    func password(service: String, account: String) -> String?
    /// An empty password deletes the item.
    func setPassword(_ password: String, service: String, account: String) throws
}

public struct SecretStoreError: Error, Equatable, Sendable { public let status: Int32 }

/// macOS Keychain (`kSecClassGenericPassword`, service `cz.ok1xoe.mmtty4mac.<service>`).
public struct KeychainSecretStore: SecretStore {
    public init() {}
    static func serviceName(_ s: String) -> String { "cz.ok1xoe.mmtty4mac.\(s)" }
    private func query(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.serviceName(service),
         kSecAttrAccount as String: account]
    }
    public func password(service: String, account: String) -> String? {
        var q = query(service, account)
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    public func setPassword(_ password: String, service: String, account: String) throws {
        let q = query(service, account)
        if password.isEmpty {
            let st = SecItemDelete(q as CFDictionary)
            if st != errSecSuccess, st != errSecItemNotFound { throw SecretStoreError(status: st) }
            return
        }
        let data = Data(password.utf8)
        var st = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if st == errSecItemNotFound {
            var add = q; add[kSecValueData as String] = data
            st = SecItemAdd(add as CFDictionary, nil)
        }
        if st != errSecSuccess { throw SecretStoreError(status: st) }
    }
}

/// In-memory implementation (tests).
public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String] = [:]
    public init() {}
    public func password(service: String, account: String) -> String? { lock.withLock { items["\(service)|\(account)"] } }
    public func setPassword(_ password: String, service: String, account: String) throws {
        lock.withLock { items["\(service)|\(account)"] = password.isEmpty ? nil : password }
    }
}
