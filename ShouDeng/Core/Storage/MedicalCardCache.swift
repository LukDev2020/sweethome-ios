import Foundation

// MARK: - Medical Card Cache
//
// Single on-device copy of the user's emergency medical card, read by the
// lock-screen Live Activity, the widget, the emergency text card and claim
// materials. (MedicalCardView had moved the card to an encrypted file and
// deleted the UserDefaults key those readers used, so the lock screen always
// showed no medical info.)
//
// Protection is `.completeUntilFirstUserAuthentication`: the Live Activity /
// widget refresh can run while the phone is locked. Excluded from backups.
// Removed on logout so the next user never inherits it.

enum MedicalCardCache {

    private static let legacyDefaultsKey = "medical_card_cache"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Overridable for Explore Mode / tests (nil = in-memory only).
    static var fileURL: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("medical_card_cache.enc")

    private static var memoryCopy: MedicalCardData?
    private static let lock = NSLock()

    static func save(_ card: MedicalCardData) {
        lock.withLock {
            guard let url = fileURL else {
                memoryCopy = card
                return
            }
            guard let data = try? encoder.encode(card) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var resourceURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? resourceURL.setResourceValues(values)
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        }
    }

    static func load() -> MedicalCardData? {
        // One-time migration from the legacy UserDefaults copy
        if fileURL != nil,
           let legacy = UserDefaults.standard.data(forKey: legacyDefaultsKey),
           let card = try? decoder.decode(MedicalCardData.self, from: legacy) {
            save(card)
            return card
        }
        return lock.withLock {
            guard let url = fileURL else { return memoryCopy }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(MedicalCardData.self, from: data)
        }
    }

    static func clear() {
        lock.withLock {
            memoryCopy = nil
            if let url = fileURL { try? FileManager.default.removeItem(at: url) }
            UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        }
    }
}
