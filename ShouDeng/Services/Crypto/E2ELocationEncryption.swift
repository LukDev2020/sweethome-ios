import Foundation
import CryptoKit

// MARK: - E2E Location Encryption
//
// Encrypts location data end-to-end between protected person and guardian.
// Uses X25519 key agreement + AES-256-GCM symmetric encryption.
// Server stores only encrypted blobs — cannot read location data.
//
// Architecture inspired by TICE (TICESoftware/tice-ios).

final class E2ELocationEncryption {

    // MARK: - Types

    struct EncryptedPayload: Codable {
        let ephemeralPublicKey: String   // Base64-encoded X25519 public key
        let ciphertext: String           // Base64-encoded AES-GCM sealed box
        let nonce: String                // Base64-encoded 12-byte nonce
    }

    struct LocationPayload: Codable {
        let latitude: Double
        let longitude: Double
        let accuracy: Double
        let altitude: Double?
        let speed: Double?
        let timestamp: Date
        let activityType: String?
    }

    // MARK: - Key Management

    private let keyManager: KeyManager

    init(keyManager: KeyManager) {
        self.keyManager = keyManager
    }

    // MARK: - Encrypt

    func encrypt(location: LocationPayload, forRecipientPublicKey recipientKeyData: Data) throws -> EncryptedPayload {
        let recipientKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientKeyData)

        // Generate ephemeral key pair for forward secrecy
        let ephemeralPrivate = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPublic = ephemeralPrivate.publicKey

        // Derive shared secret
        let sharedSecret = try ephemeralPrivate.sharedSecretFromKeyAgreement(with: recipientKey)

        // Derive symmetric key using HKDF
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("shoudeng-location-v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        // Encode location payload
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintext = try encoder.encode(location)

        // Encrypt with AES-GCM
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)

        return EncryptedPayload(
            ephemeralPublicKey: ephemeralPublic.rawRepresentation.base64EncodedString(),
            ciphertext: sealedBox.ciphertext.base64EncodedString() + ":" + sealedBox.tag.base64EncodedString(),
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0) }.base64EncodedString()
        )
    }

    // MARK: - Decrypt

    func decrypt(payload: EncryptedPayload) throws -> LocationPayload {
        guard let ephemeralKeyData = Data(base64Encoded: payload.ephemeralPublicKey),
              let nonceData = Data(base64Encoded: payload.nonce) else {
            throw E2EError.invalidPayload
        }

        let ciphertextParts = payload.ciphertext.split(separator: ":")
        guard ciphertextParts.count == 2,
              let ciphertextData = Data(base64Encoded: String(ciphertextParts[0])),
              let tagData = Data(base64Encoded: String(ciphertextParts[1])) else {
            throw E2EError.invalidPayload
        }

        let ephemeralPublic = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralKeyData)
        let myPrivateKey = try keyManager.getOrCreatePrivateKey()

        // Derive shared secret (same as sender computed)
        let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPublic)

        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("shoudeng-location-v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        // Decrypt
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
        let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LocationPayload.self, from: plaintext)
    }

    // MARK: - Errors

    enum E2EError: Error {
        case invalidPayload
        case keyNotFound
        case decryptionFailed
    }
}
