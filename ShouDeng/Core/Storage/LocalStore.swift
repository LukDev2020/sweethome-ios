import Foundation

// MARK: - Local Store
//
// JSON file-based persistence for app state that must survive app restarts.
// Bridges the gap between in-memory AppCoordinator state and the server.
//
// Stores: current user profile, guardian list, protected persons,
//         active SOS event, safe zones, timeline entries.
//
// Each entity type gets its own JSON file in Documents/store/.

final class LocalStore {

    static let shared = LocalStore()

    private let storeDir: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "com.shoudeng.localstore", qos: .utility)

    /// Explore Mode: in-memory files while a demo runs; the real store on disk
    /// is neither read nor written. Accessed on `queue` only.
    private var overlay: [String: Data]?

    /// A store that is always in memory (Explore Mode's own coordinator) — late
    /// writes after a demo ends can never reach the real store on disk.
    private let alwaysInMemory: Bool

    func beginOverlay() { queue.sync { overlay = [:] } }
    func endOverlay() { queue.sync { if !alwaysInMemory { overlay = nil } } }

    static func inMemory() -> LocalStore { LocalStore(inMemory: true) }

    private init(inMemory: Bool = false) {
        alwaysInMemory = inMemory
        overlay = inMemory ? [:] : nil
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeDir = docs.appendingPathComponent("store", isDirectory: true)

        if !inMemory {
            try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        }

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Generic Save/Load

    private func save<T: Encodable>(_ value: T, filename: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let url = self.storeDir.appendingPathComponent(filename)
            guard let data = try? self.encoder.encode(value) else { return }
            if self.overlay != nil {
                self.overlay?[filename] = data
                return
            }
            // Readable while locked: a lock-screen / BLE SOS saves the active event
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private func load<T: Decodable>(filename: String) -> T? {
        queue.sync {
            if let overlay {
                return overlay[filename].flatMap { try? decoder.decode(T.self, from: $0) }
            }
            let url = storeDir.appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }

    private func remove(filename: String) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.overlay != nil {
                self.overlay?[filename] = nil
                return
            }
            let url = self.storeDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Current User

    func saveCurrentUser(_ user: User) {
        save(user, filename: "current_user.json")
    }

    func loadCurrentUser() -> User? {
        load(filename: "current_user.json")
    }

    // MARK: - User Role

    func saveUserRole(_ role: UserRole) {
        save(role, filename: "user_role.json")
    }

    func loadUserRole() -> UserRole? {
        load(filename: "user_role.json")
    }

    // MARK: - Guardians (for protected person)

    func saveGuardians(_ guardians: [Guardian]) {
        save(guardians, filename: "guardians.json")
    }

    func loadGuardians() -> [Guardian] {
        load(filename: "guardians.json") ?? []
    }

    // MARK: - Protected Persons (for guardian)

    func saveProtectedPersons(_ persons: [ProtectedPerson]) {
        save(persons, filename: "protected_persons.json")
    }

    func loadProtectedPersons() -> [ProtectedPerson] {
        load(filename: "protected_persons.json") ?? []
    }

    // MARK: - Active SOS

    func saveActiveSOSEvent(_ event: SOSEvent?) {
        if let event {
            save(event, filename: "active_sos.json")
        } else {
            remove(filename: "active_sos.json")
        }
    }

    func loadActiveSOSEvent() -> SOSEvent? {
        load(filename: "active_sos.json")
    }

    // MARK: - Safe Zones

    func saveSafeZones(_ zones: [SafeZone]) {
        save(zones, filename: "safe_zones.json")
    }

    func loadSafeZones() -> [SafeZone] {
        load(filename: "safe_zones.json") ?? []
    }

    // MARK: - Timeline

    func saveTimeline(_ entries: [TimelineEntry]) {
        save(entries, filename: "timeline.json")
    }

    func loadTimeline() -> [TimelineEntry] {
        load(filename: "timeline.json") ?? []
    }

    // MARK: - Family Posts

    func saveFamilyPosts(_ posts: [FamilyPost]) {
        save(posts, filename: "family_posts.json")
    }

    func loadFamilyPosts() -> [FamilyPost] {
        load(filename: "family_posts.json") ?? []
    }

    // MARK: - Family photos waiting to be uploaded

    /// Raw file for a photo of an unsent family post (name from `FamilyPostDelivery`).
    /// Written synchronously so it exists before the post that refers to it.
    func saveFamilyMedia(_ data: Data, name: String) {
        queue.sync {
            if overlay != nil {
                overlay?[Self.familyMediaFile(name)] = data
                return
            }
            let url = storeDir.appendingPathComponent(Self.familyMediaFile(name))
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func loadFamilyMedia(name: String) -> Data? {
        queue.sync {
            if let overlay { return overlay[Self.familyMediaFile(name)] }
            return try? Data(contentsOf: storeDir.appendingPathComponent(Self.familyMediaFile(name)))
        }
    }

    func deleteFamilyMedia(name: String) {
        remove(filename: Self.familyMediaFile(name))
    }

    /// Flat, sanitized file name (a name can never point outside the store).
    private static func familyMediaFile(_ name: String) -> String {
        "family_media_" + name.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
    }

    // MARK: - Clear All

    func clearAll() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.overlay != nil {
                self.overlay = [:]
                return
            }
            let files = (try? FileManager.default.contentsOfDirectory(at: self.storeDir, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
