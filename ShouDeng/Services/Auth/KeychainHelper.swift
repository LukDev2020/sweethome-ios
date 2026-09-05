import Foundation
import Security

// MARK: - Keychain Helper
//
// Thin wrapper around iOS Keychain Services for secure token storage.
// Stores auth tokens, refresh tokens, and device secrets.

final class KeychainHelper {

    static let shared = KeychainHelper()
    private init() {}

    private let service = "com.shoudeng.auth"

    // MARK: - Keys

    enum Key: String {
        case accessToken
        case refreshToken
        case userId
        case deviceSecret
    }

    // MARK: - CRUD

    func save(_ value: String, for key: Key) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func read(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func deleteAll() {
        for key in [Key.accessToken, .refreshToken, .userId, .deviceSecret] {
            delete(key)
        }
    }
}
