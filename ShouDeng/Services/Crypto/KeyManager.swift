import Foundation
import CryptoKit
import Security

// MARK: - E2E Key Manager
//
// Manages X25519 key pairs for E2E location encryption.
// Private key stored in Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly).
// Public key shared with guardians/protected persons during invite accept.

final class KeyManager {

    private let keychainService = "com.shoudeng.e2e"
    private let privateKeyTag = "e2e-private-key"

    // MARK: - Get or Create Key Pair

    func getOrCreatePrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let existing = loadPrivateKey() {
            return existing
        }
        let newKey = Curve25519.KeyAgreement.PrivateKey()
        try savePrivateKey(newKey)
        return newKey
    }

    func getPublicKeyData() throws -> Data {
        let privateKey = try getOrCreatePrivateKey()
        return privateKey.publicKey.rawRepresentation
    }

    func getPublicKeyBase64() throws -> String {
        try getPublicKeyData().base64EncodedString()
    }

    // MARK: - Key Rotation

    func rotateKeys() throws -> Data {
        deletePrivateKey()
        let newKey = Curve25519.KeyAgreement.PrivateKey()
        try savePrivateKey(newKey)
        return newKey.publicKey.rawRepresentation
    }

    // MARK: - Keychain Operations

    private func savePrivateKey(_ key: Curve25519.KeyAgreement.PrivateKey) throws {
        let keyData = key.rawRepresentation

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: privateKeyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        // Delete existing if any
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyManagerError.keychainWriteFailed(status)
        }
    }

    private func loadPrivateKey() -> Curve25519.KeyAgreement.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: privateKeyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    private func deletePrivateKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: privateKeyTag,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Peer Key Cache

    private var peerKeys: [String: Data] = [:]

    func cachePeerPublicKey(userId: String, publicKeyBase64: String) {
        guard let data = Data(base64Encoded: publicKeyBase64) else { return }
        peerKeys[userId] = data
    }

    func getPeerPublicKey(userId: String) -> Data? {
        peerKeys[userId]
    }

    func clearPeerKeys() {
        peerKeys.removeAll()
    }

    // MARK: - Errors

    enum KeyManagerError: Error {
        case keychainWriteFailed(OSStatus)
        case keyNotFound
    }
}
