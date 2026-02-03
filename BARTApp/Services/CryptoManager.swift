import Foundation
import CryptoKit

/// Encryption utilities for secure payload encryption using Curve25519 key agreement
/// and AES-GCM authenticated encryption.
class CryptoManager {
    static let shared = CryptoManager()

    private init() {}

    // MARK: - Key Generation

    /// Generate a new Curve25519 key pair for key agreement
    /// - Returns: Tuple containing the private key and the public key as Data
    func generateKeyPair() -> (privateKey: Curve25519.KeyAgreement.PrivateKey, publicKey: Data) {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation
        return (privateKey, publicKey)
    }

    // MARK: - Key Agreement

    /// Derive a shared secret from a private key and peer's public key
    /// - Parameters:
    ///   - privateKey: Our private key
    ///   - peerPublicKey: The peer's public key as Data (32 bytes)
    /// - Returns: A SymmetricKey derived from the shared secret
    /// - Throws: CryptoError if key derivation fails
    func deriveSharedSecret(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Data
    ) throws -> SymmetricKey {
        // Convert peer public key data to CryptoKit public key
        let peerKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)

        // Perform ECDH key agreement
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerKey)

        // Derive a 256-bit symmetric key using HKDF
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("BART-E2E-Salt".utf8),
            sharedInfo: Data("BART-E2E-Encryption".utf8),
            outputByteCount: 32
        )

        return symmetricKey
    }

    // MARK: - AES-GCM Encryption

    /// Encrypt plaintext using AES-GCM with a symmetric key
    /// - Parameters:
    ///   - plaintext: The data to encrypt
    ///   - key: The symmetric key for encryption
    /// - Returns: Tuple containing the nonce (12 bytes) and ciphertext (includes auth tag)
    /// - Throws: CryptoError if encryption fails
    func encrypt(plaintext: Data, key: SymmetricKey) throws -> (nonce: Data, ciphertext: Data) {
        // Generate a random 12-byte nonce
        let nonce = AES.GCM.Nonce()

        // Encrypt using AES-GCM (256-bit key, includes 16-byte auth tag)
        let sealedBox = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

        // Return nonce and combined ciphertext+tag
        guard let combined = sealedBox.combined else {
            throw CryptoError.encryptionFailed
        }

        // The nonce is the first 12 bytes of combined, but we return it separately for clarity
        let nonceData = Data(nonce)

        // Combined format: nonce (12) + ciphertext + tag (16)
        // We return just ciphertext+tag (without the nonce prefix)
        let ciphertextWithTag = combined.dropFirst(12)

        return (nonce: nonceData, ciphertext: Data(ciphertextWithTag))
    }

    /// Decrypt ciphertext using AES-GCM with a symmetric key
    /// - Parameters:
    ///   - nonce: The nonce used during encryption (12 bytes)
    ///   - ciphertext: The encrypted data (includes auth tag)
    ///   - key: The symmetric key for decryption
    /// - Returns: The decrypted plaintext, or nil if decryption fails
    func decrypt(nonce: Data, ciphertext: Data, key: SymmetricKey) -> Data? {
        do {
            // Validate nonce length
            guard nonce.count == 12 else {
                throw CryptoError.decryptionFailed
            }

            // Reconstruct the sealed box from nonce + ciphertext
            let combined = nonce + ciphertext
            let sealedBox = try AES.GCM.SealedBox(combined: combined)

            // Decrypt and verify authentication tag
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            return decrypted
        } catch {
            #if DEBUG
            print("❌ Decryption failed: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Convenience Methods

    /// Encrypt a string to base64-encoded components
    /// - Parameters:
    ///   - string: The string to encrypt
    ///   - key: The symmetric key
    /// - Returns: Tuple with base64-encoded nonce and ciphertext
    func encryptString(_ string: String, key: SymmetricKey) throws -> (nonce: String, ciphertext: String) {
        let plaintext = Data(string.utf8)
        let (nonce, ciphertext) = try encrypt(plaintext: plaintext, key: key)
        return (nonce.base64EncodedString(), ciphertext.base64EncodedString())
    }

    /// Decrypt base64-encoded components to a string
    /// - Parameters:
    ///   - nonce: Base64-encoded nonce
    ///   - ciphertext: Base64-encoded ciphertext
    ///   - key: The symmetric key
    /// - Returns: The decrypted string, or nil if decryption fails
    func decryptString(nonce: String, ciphertext: String, key: SymmetricKey) -> String? {
        guard let nonceData = Data(base64Encoded: nonce),
              let ciphertextData = Data(base64Encoded: ciphertext),
              let decrypted = decrypt(nonce: nonceData, ciphertext: ciphertextData, key: key) else {
            return nil
        }
        return String(data: decrypted, encoding: .utf8)
    }

    /// Export public key to base64 string for transmission
    func exportPublicKey(_ publicKey: Data) -> String {
        return publicKey.base64EncodedString()
    }

    /// Import public key from base64 string
    func importPublicKey(_ base64: String) -> Data? {
        return Data(base64Encoded: base64)
    }
}

// MARK: - Errors

enum CryptoError: Error, LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidPublicKey
    case keyDerivationFailed

    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Encryption failed"
        case .decryptionFailed:
            return "Decryption failed"
        case .invalidPublicKey:
            return "Invalid public key format"
        case .keyDerivationFailed:
            return "Key derivation failed"
        }
    }
}
