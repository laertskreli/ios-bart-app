import Foundation
import CryptoKit
import Security

/// Manages device authentication using HMAC-SHA256
/// Generates and stores a device secret on first launch, then uses it to create
/// authentication headers with timestamp-based HMAC signatures.
class DeviceAuthManager {
    nonisolated(unsafe) static let shared = DeviceAuthManager()

    private let keychainKey = "com.bart.device-secret"
    private let deviceIdKey = "com.bart.device-id"

    private init() {}

    // MARK: - Device Secret Management

    /// Get or generate the device secret (32 bytes)
    /// Stored securely in Keychain, persists across app launches
    func getOrCreateDeviceSecret() -> Data {
        // Try to load existing secret
        if let existingSecret = KeychainHelper.load(key: keychainKey) {
            return existingSecret
        }

        // Generate new 32-byte secret using secure random
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        guard status == errSecSuccess else {
            // Fallback to CryptoKit if SecRandomCopyBytes fails
            let key = SymmetricKey(size: .bits256)
            let secretData = key.withUnsafeBytes { Data($0) }
            _ = KeychainHelper.save(key: keychainKey, data: secretData)
            #if DEBUG
            print("🔐 Generated new device secret (CryptoKit fallback)")
            #endif
            return secretData
        }

        let secretData = Data(bytes)
        _ = KeychainHelper.save(key: keychainKey, data: secretData)
        #if DEBUG
        print("🔐 Generated new device secret (SecRandomCopyBytes)")
        #endif
        return secretData
    }

    /// Get the device ID (derived from secret or stored separately)
    func getDeviceId() -> String {
        // Try to load existing device ID
        if let existingId = KeychainHelper.loadString(service: deviceIdKey, account: deviceIdKey) {
            return existingId
        }

        // Generate a device ID based on the secret hash
        let secret = getOrCreateDeviceSecret()
        let hash = SHA256.hash(data: secret)
        let deviceId = hash.prefix(16).map { String(format: "%02x", $0) }.joined()

        _ = KeychainHelper.saveString(deviceId, service: deviceIdKey, account: deviceIdKey)
        #if DEBUG
        print("🆔 Generated device ID: \(deviceId)")
        #endif
        return deviceId
    }

    // MARK: - HMAC-SHA256 Authentication

    /// Generate HMAC-SHA256 signature for the given timestamp
    /// - Parameter timestamp: Unix timestamp in milliseconds
    /// - Returns: Base64-encoded HMAC signature
    func generateHMAC(timestamp: Int64) -> String {
        let secret = getOrCreateDeviceSecret()
        let symmetricKey = SymmetricKey(data: secret)

        // Create message from timestamp
        let message = String(timestamp)
        let messageData = Data(message.utf8)

        // Generate HMAC-SHA256
        let hmac = HMAC<SHA256>.authenticationCode(for: messageData, using: symmetricKey)
        let hmacData = Data(hmac)

        return hmacData.base64EncodedString()
    }

    /// Generate authentication header components
    /// - Returns: Tuple containing deviceId, timestamp (ms), and HMAC signature
    func getAuthHeader() -> (deviceId: String, timestamp: Int64, hmac: String) {
        let deviceId = getDeviceId()
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let hmac = generateHMAC(timestamp: timestamp)

        return (deviceId: deviceId, timestamp: timestamp, hmac: hmac)
    }

    /// Verify an HMAC signature (useful for testing or server verification)
    /// - Parameters:
    ///   - hmac: The HMAC to verify (base64 encoded)
    ///   - timestamp: The timestamp that was signed
    /// - Returns: true if the HMAC is valid
    func verifyHMAC(_ hmac: String, timestamp: Int64) -> Bool {
        let expectedHmac = generateHMAC(timestamp: timestamp)
        return hmac == expectedHmac
    }

    // MARK: - Reset

    /// Delete all device authentication data (for testing/reset)
    func reset() {
        KeychainHelper.delete(key: keychainKey)
        KeychainHelper.delete(key: deviceIdKey)
        #if DEBUG
        print("🗑️ Device auth data reset")
        #endif
    }

    /// Check if device secret exists
    func hasDeviceSecret() -> Bool {
        return KeychainHelper.load(key: keychainKey) != nil
    }
}
