import Foundation
import CryptoKit
import Security

struct DeviceIdentity: Codable {
    let nodeId: String
    let displayName: String
    var pairingToken: String?
    var pairedAt: Date?

    static let storageKey = "com.bart.deviceIdentity"
}

enum PairingState: Equatable {
    case unpaired
    case pendingApproval(code: String, requestId: String)
    case paired(token: String)
    case failed(String)
}

// MARK: - Device Identity Manager with Ed25519 Cryptographic Signing

class DeviceIdentityManager {
    static let shared = DeviceIdentityManager()

    private let keychainTag = "com.openclaw.ed25519key"

    private init() {}

    // Generate Ed25519 key pair
    @discardableResult
    func generateKeyPair() throws -> Curve25519.Signing.PrivateKey {
        // Check if key already exists
        if let existing = try? getPrivateKey() {
            return existing
        }

        // Generate Ed25519 signing key
        let signingKey = Curve25519.Signing.PrivateKey()

        // Store private key in Keychain
        let privateKeyData = signingKey.rawRepresentation

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag,
            kSecValueData as String: privateKeyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        // Delete existing key if any
        SecItemDelete(query as CFDictionary)

        // Add new key
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "DeviceIdentity", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to store key in Keychain"
            ])
        }

        print("🔐 Generated new Ed25519 key pair")
        return signingKey
    }

    // Get private key from Keychain
    private func getPrivateKey() throws -> Curve25519.Signing.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let keyData = result as? Data else {
            throw NSError(domain: "DeviceIdentity", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Private key not found"
            ])
        }

        return try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
    }

    // Get public key in base64url format (raw 32 bytes)
    func getPublicKeyBase64Url() throws -> String {
        let privateKey = try getPrivateKey()
        let publicKey = privateKey.publicKey
        let publicKeyData = publicKey.rawRepresentation
        return base64UrlEncode(publicKeyData)
    }

    // Get device ID (SHA-256 hash of public key)
    func getDeviceId() throws -> String {
        let privateKey = try getPrivateKey()
        let publicKey = privateKey.publicKey
        let publicKeyData = publicKey.rawRepresentation
        let hash = SHA256.hash(data: publicKeyData)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // Sign payload using Ed25519
    func signPayload(_ payload: String) throws -> String {
        let privateKey = try getPrivateKey()
        let payloadData = Data(payload.utf8)
        let signature = try privateKey.signature(for: payloadData)
        return base64UrlEncode(signature)
    }

    // Delete Ed25519 key pair from Keychain (for complete reset)
    func deleteKeyPair() {
        // Delete by account tag
        let query1: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag
        ]
        SecItemDelete(query1 as CFDictionary)
        
        // Also try to clear ALL generic passwords (nuclear option for reset)
        let query2: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword
        ]
        let status = SecItemDelete(query2 as CFDictionary)
        print("🗑️ Cleared all keychain entries (status: \(status))")
    }

    // Check if key pair exists
    func hasKeyPair() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainTag,
            kSecReturnData as String: false
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }

    // Base64url encoding helper
    private func base64UrlEncode(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // Build the payload string that needs to be signed (pipe-delimited format)
    func buildDeviceAuthPayload(
        deviceId: String,
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        signedAtMs: Int,
        token: String?,
        nonce: String?
    ) -> String {
        // Determine version based on nonce presence
        let version = nonce != nil ? "v2" : "v1"

        // Build pipe-delimited payload (EXACT format OpenClaw expects)
        var parts: [String] = [
            version,
            deviceId,
            clientId,
            clientMode,
            role,
            scopes.joined(separator: ","),
            String(signedAtMs),
            token ?? ""
        ]

        // Add nonce for v2
        if version == "v2", let nonce = nonce {
            parts.append(nonce)
        }

        return parts.joined(separator: "|")
    }
}
