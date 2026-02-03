import Foundation
import Security

enum KeychainHelper {

    // MARK: - Core Operations with Enhanced Security

    /// Save data to keychain with secure accessibility (device-only, available after first unlock)
    static func save(_ data: Data, service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Load data from keychain
    static func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Delete item from keychain
    static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Convenience Methods

    static func saveString(_ string: String, service: String, account: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(data, service: service, account: account)
    }

    static func loadString(service: String, account: String) -> String? {
        guard let data = load(service: service, account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Simple Key-Based API

    /// Save data with a simple key (uses key as both service and account)
    static func save(key: String, data: Data) -> Bool {
        return save(data, service: key, account: key)
    }

    /// Load data with a simple key
    static func load(key: String) -> Data? {
        return load(service: key, account: key)
    }

    /// Delete data with a simple key
    @discardableResult
    static func delete(key: String) -> Bool {
        return delete(service: key, account: key)
    }
}
