import Foundation
import Combine

// MARK: - Disguise Mode Service
//
// Allows the protected person to hide the ShouDeng app behind a convincing
// decoy interface (calculator, weather, notes). A secret gesture or code
// reveals the real app and optionally fires a silent SOS.
//
// Security notes:
//   - All disguise settings stored in Keychain under a neutral service name
//     ("com.shoudeng.prefs") — not UserDefaults, which an attacker can inspect.
//   - The service name itself is intentionally generic to avoid tipping off
//     an adversary who browses Keychain entries.
//   - No logging of disguise state changes to analytics or crash reporters.

// MARK: - Disguise Type

enum DisguiseType: String, CaseIterable {
    case none       = "none"
    case calculator = "calculator"
    case weather    = "weather"
    case notes      = "notes"

    var displayName: String {
        switch self {
        case .none:       return "None (show real app)"
        case .calculator: return "Calculator"
        case .weather:    return "Weather"
        case .notes:      return "Notes"
        }
    }

    /// SF Symbol representing this disguise on the settings screen.
    var iconName: String {
        switch self {
        case .none:       return "shield"
        case .calculator: return "plus.slash.minus"
        case .weather:    return "cloud.sun"
        case .notes:      return "note.text"
        }
    }
}

// MARK: - Secret Gesture Type

enum SecretGesture: String {
    /// Calculator: user types a trigger code followed by "=" (e.g. "911=", "999=", or duress="")
    case calculatorCode
    /// Weather: triple-tap on the temperature display area
    case weatherTripleTap
    /// Notes: user types a configurable secret phrase into the note body
    case notesPhrase
}

// MARK: - Disguise Mode Service

final class DisguiseModeService: ObservableObject {

    static let shared = DisguiseModeService()
    private init() {
        loadFromKeychain()
    }

    // MARK: - Published State

    @Published private(set) var isDisguiseActive: Bool = false
    @Published private(set) var currentDisguise: DisguiseType = .none
    @Published private(set) var secretGesture: SecretGesture = .calculatorCode

    // MARK: - Keychain Keys
    // Stored under a neutral service name to avoid detection.

    private let keychainService = "com.shoudeng.prefs"

    private enum PrefKey: String {
        case disguiseType       = "pref_dt"
        case notesSecretPhrase  = "pref_nsp"
        case sosTriggerEnabled  = "pref_ste"
    }

    // MARK: - Configuration (persisted in Keychain)

    /// The disguise currently configured by the user (may be .none).
    private(set) var configuredDisguise: DisguiseType = .none {
        didSet { saveToKeychain() }
    }

    /// Secret phrase for the Notes disguise (default: "help me").
    private(set) var notesSecretPhrase: String = "help me" {
        didSet { saveToKeychain() }
    }

    /// When true, detecting the secret gesture also fires a silent SOS.
    private(set) var silentSOSOnReveal: Bool = true {
        didSet { saveToKeychain() }
    }

    // MARK: - Coordinator Reference
    // Weak to avoid retain cycle; set once by AppCoordinator during startup.

    private weak var coordinator: AnyObject?

    func configure(coordinator: AnyObject) {
        self.coordinator = coordinator
    }

    // MARK: - Keychain Persistence

    private func saveToKeychain() {
        keychainWrite(configuredDisguise.rawValue, for: PrefKey.disguiseType)
        keychainWrite(notesSecretPhrase,           for: PrefKey.notesSecretPhrase)
        keychainWrite(silentSOSOnReveal ? "1" : "0", for: PrefKey.sosTriggerEnabled)
    }

    private func loadFromKeychain() {
        if let raw = keychainRead(PrefKey.disguiseType),
           let type = DisguiseType(rawValue: raw) {
            configuredDisguise = type
        }
        if let phrase = keychainRead(PrefKey.notesSecretPhrase), !phrase.isEmpty {
            notesSecretPhrase = phrase
        }
        if let flag = keychainRead(PrefKey.sosTriggerEnabled) {
            silentSOSOnReveal = (flag == "1")
        }
    }

    // MARK: - Keychain Low-Level

    private func keychainWrite(_ value: String, for key: PrefKey) {
        guard let data = value.data(using: .utf8) else { return }
        keychainDelete(key)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String:   data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func keychainRead(_ key: PrefKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(_ key: PrefKey) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Public Configuration API

    /// Update which disguise type is configured. Persists to Keychain.
    func setDisguiseType(_ type: DisguiseType) {
        configuredDisguise = type
    }

    /// Update the secret phrase for the Notes disguise. Persists to Keychain.
    func setNotesSecretPhrase(_ phrase: String) {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        notesSecretPhrase = trimmed.isEmpty ? "help me" : trimmed
    }

    /// Toggle whether the secret gesture fires a silent SOS in addition to revealing the app.
    func setSilentSOSOnReveal(_ enabled: Bool) {
        silentSOSOnReveal = enabled
    }

    // MARK: - Activate / Deactivate

    /// Switch the app's visible interface to the configured disguise.
    /// Call this at startup if a disguise is configured, or when the user
    /// explicitly enables disguise mode from settings.
    @MainActor
    func activateDisguise(type: DisguiseType) {
        guard type != .none else {
            deactivateDisguise()
            return
        }
        currentDisguise = type
        isDisguiseActive = true

        switch type {
        case .calculator: secretGesture = .calculatorCode
        case .weather:    secretGesture = .weatherTripleTap
        case .notes:      secretGesture = .notesPhrase
        case .none:       break
        }
    }

    /// Reveal the real app. Does NOT fire SOS — use silentSOSTrigger() for that.
    @MainActor
    func deactivateDisguise() {
        isDisguiseActive = false
        currentDisguise = .none
    }

    // MARK: - Secret Gesture Handling

    /// Called by a disguise view when the secret gesture is detected.
    /// Reveals the real app and, if configured, fires a silent SOS.
    @MainActor
    func handleSecretGestureDetected() {
        // Reveal the app first — do this synchronously so the UI responds instantly.
        deactivateDisguise()

        // Optionally fire silent SOS — dispatched asynchronously so it doesn't
        // block the UI transition.
        if silentSOSOnReveal {
            silentSOSTrigger()
        }
    }

    /// Fire a silent SOS via the duressPassword trigger method.
    /// This is identical to the duress code path used at login:
    ///   — looks like normal app usage from the outside
    ///   — silently alerts all guardians
    @MainActor
    func silentSOSTrigger() {
        // We reach into AppCoordinator via protocol erasure to avoid a hard import
        // cycle. AppCoordinator is the single source of truth for SOS.
        guard let coord = coordinator as? SOSTriggerTarget else { return }
        coord.triggerSOS(method: .duressPassword)
    }

    // MARK: - Trigger Code Validation

    /// Returns true if the given calculator input string matches a known secret trigger:
    ///   - "911" or "999" (universal emergency codes)
    ///   - The user's configured duress code (from KeychainHelper)
    /// The caller is responsible for stripping the trailing "=" before passing here.
    func isSecretCalculatorCode(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "911" || trimmed == "999" { return true }

        // Check against stored duress code (may be nil if not set)
        if let duress = KeychainHelper.shared.read(.duressCode),
           !duress.isEmpty,
           trimmed == duress {
            return true
        }
        return false
    }

    /// Returns true if the given text (lowercased, trimmed) matches the configured
    /// notes secret phrase.
    func isSecretNotesPhrase(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains(notesSecretPhrase)
    }
}

// MARK: - SOSTriggerTarget Protocol
//
// Protocol-erases AppCoordinator so DisguiseModeService does not
// need to import the coordinator directly, avoiding circular dependencies.

protocol SOSTriggerTarget: AnyObject {
    func triggerSOS(method: SOSTriggerMethod)
}

// AppCoordinator conforms automatically since it already has
// `func triggerSOS(method: SOSTriggerMethod)`.
extension AppCoordinator: SOSTriggerTarget {}
