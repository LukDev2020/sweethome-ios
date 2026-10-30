import Foundation
import Security

// MARK: - Keychain Helper
//
// Thin wrapper around iOS Keychain Services for secure token storage.
// Stores auth tokens, refresh tokens, and device secrets.

final class KeychainHelper {

    static let shared = KeychainHelper()
    private init() {}

    // MARK: - Explore Mode overlay
    //
    // While a demo session runs, every read/write goes to this in-memory map and
    // the real keychain is never touched; ending the overlay discards it.

    private let overlayLock = NSLock()
    private var overlay: [String: String]?

    func beginOverlay() { overlayLock.withLock { overlay = [:] } }
    func endOverlay() { overlayLock.withLock { overlay = nil } }
    var isOverlayActive: Bool { overlayLock.withLock { overlay != nil } }

    /// nil = no overlay active (use the real keychain)
    private func overlayRead(_ account: String) -> String?? {
        overlayLock.withLock { overlay.map { $0[account] } }
    }

    private func overlayWrite(_ account: String, _ value: String?) -> Bool {
        overlayLock.withLock {
            guard overlay != nil else { return false }
            overlay?[account] = value
            return true
        }
    }

    private let service = "com.shoudeng.auth"

    // MARK: - Keys

    enum Key: String {
        case accessToken
        case refreshToken
        case userId
        case deviceSecret
        case duressCode
    }

    // MARK: - CRUD

    /// Result of a keychain read. `unavailable` (e.g. errSecInteractionNotAllowed
    /// before the first unlock after a reboot) is NOT the same as "no session":
    /// treating it as logged-out would wipe the user's data on a background launch.
    enum ReadResult: Equatable {
        case value(String)
        case notFound
        case unavailable(OSStatus)
    }

    @discardableResult
    func save(_ value: String, for key: Key) -> Bool {
        if overlayWrite("auth." + key.rawValue, value) { return true }
        guard let data = value.data(using: .utf8) else { return false }
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        // Update in place first so a failed add can't leave us with nothing
        let updateStatus = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        var add = match
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            #if DEBUG
            print("[Keychain] save \(key.rawValue) failed: \(status)")
            #endif
        }
        return status == errSecSuccess
    }

    func read(_ key: Key) -> String? {
        if case .value(let v) = readResult(key) { return v }
        return nil
    }

    func readResult(_ key: Key) -> ReadResult {
        if let overlaid = overlayRead("auth." + key.rawValue) {
            return overlaid.map { .value($0) } ?? .notFound
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let s = String(data: data, encoding: .utf8) else { return .notFound }
            return .value(s)
        case errSecItemNotFound:
            return .notFound
        default:
            return .unavailable(status)
        }
    }

    func delete(_ key: Key) {
        if overlayWrite("auth." + key.rawValue, nil) { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Removes the session. The duress code is a device safety setting chosen by
    /// the user and survives logout (otherwise it silently stops working).
    func deleteAll() {
        for key in [Key.accessToken, .refreshToken, .userId, .deviceSecret] {
            delete(key)
        }
    }

    // MARK: - Generic String-Key Access (for safety feature settings)
    // Uses a separate service name to avoid collisions with auth keys.
    // Data stored here is hidden from device backups (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly).

    private let safetyService = "com.shoudeng.prefs"

    func save(_ account: String, value: String) {
        if overlayWrite("prefs." + account, value) { return }
        guard let data = value.data(using: .utf8) else { return }
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: safetyService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: safetyService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            #if DEBUG
            print("[Keychain] save \(account) failed: \(status)")
            #endif
        }
    }

    func read(_ account: String) -> String? {
        if let overlaid = overlayRead("prefs." + account) { return overlaid }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: safetyService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
