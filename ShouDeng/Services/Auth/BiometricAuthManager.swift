import Foundation
import LocalAuthentication
import Security

// MARK: - Biometric Auth Manager
//
// Manages Face ID / Touch ID as a UI-level gate for app access.
// Does NOT replace token-based auth — it protects the already-authenticated
// session from unauthorized physical access.
//
// Pattern:
//   1. After first OTP login, offer to enable biometric login
//   2. On subsequent launches, require biometric before showing app UI
//   3. Background services (heartbeat, location, push) are unaffected
//
// Uses a separate Keychain service ("com.shoudeng.biometric") with
// kSecAccessControlBiometryCurrentSet — if biometrics change (new face
// or fingerprint enrolled), the item is invalidated and the user must
// re-authenticate via OTP.

final class BiometricAuthManager: ObservableObject {

    static let shared = BiometricAuthManager()

    // MARK: - Published State

    @Published var isUnlocked = false

    // MARK: - Constants

    private let biometricService = "com.shoudeng.biometric"
    private let sessionKey = "biometric_session"
    private let enabledKey = "biometricLoginEnabled"
    private let promptShownKey = "biometricPromptShown"

    // MARK: - Computed Properties

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            objectWillChange.send()
        }
    }

    var hasShownPrompt: Bool {
        get { UserDefaults.standard.bool(forKey: promptShownKey) }
        set { UserDefaults.standard.set(newValue, forKey: promptShownKey) }
    }

    var biometricType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    var biometricName: String {
        switch biometricType {
        case .faceID: return "面容ID"
        case .touchID: return "触控ID"
        case .opticID: return "Optic ID"
        case .none: return "生物识别"
        @unknown default: return "生物识别"
        }
    }

    var biometricIconName: String {
        switch biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.fill"
        }
    }

    // MARK: - Init

    private init() {}

    // MARK: - Enable / Disable

    func enable() throws {
        var cfError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &cfError
        ) else {
            throw BiometricError.accessControlFailed
        }

        let sessionValue = UUID().uuidString
        guard let data = sessionValue.data(using: .utf8) else { return }

        // Remove existing item
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: biometricService,
            kSecAttrAccount as String: sessionKey,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Store new biometric-protected item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: biometricService,
            kSecAttrAccount as String: sessionKey,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BiometricError.keychainSaveFailed(status)
        }

        isEnabled = true
    }

    func disable() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: biometricService,
            kSecAttrAccount as String: sessionKey,
        ]
        SecItemDelete(query as CFDictionary)
        isEnabled = false
        isUnlocked = false
    }

    // MARK: - Authenticate

    @MainActor
    func authenticate() async -> BiometricResult {
        guard isEnabled else {
            isUnlocked = true
            return .success
        }

        let context = LAContext()
        context.localizedCancelTitle = "使用验证码"
        context.localizedFallbackTitle = "输入设备密码"

        // Read the biometric-protected Keychain item.
        // iOS auto-presents Face ID / Touch ID for this read.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: biometricService,
            kSecAttrAccount as String: sessionKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            isUnlocked = true
            return .success

        case errSecItemNotFound:
            // Biometrics changed — invalidate and require OTP re-auth
            disable()
            return .biometricsChanged

        case errSecUserCanceled, errSecAuthFailed:
            return .cancelled

        default:
            return .failed
        }
    }

    func skipBiometric() {
        isUnlocked = true
    }

    /// Reset on logout
    func resetUnlockState() {
        isUnlocked = false
    }
}

// MARK: - Result & Error Types

enum BiometricResult {
    case success
    case cancelled
    case biometricsChanged
    case failed
}

enum BiometricError: LocalizedError {
    case accessControlFailed
    case keychainSaveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .accessControlFailed:
            return "无法创建生物识别访问控制"
        case .keychainSaveFailed(let status):
            return "钥匙串保存失败 (\(status))"
        }
    }
}
