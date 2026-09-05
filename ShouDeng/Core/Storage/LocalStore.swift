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

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        storeDir = docs.appendingPathComponent("store", isDirectory: true)

        try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)

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
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load<T: Decodable>(filename: String) -> T? {
        queue.sync {
            let url = storeDir.appendingPathComponent(filename)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(T.self, from: data)
        }
    }

    private func remove(filename: String) {
        queue.async { [weak self] in
            guard let self else { return }
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

    // MARK: - Clear All

    func clearAll() {
        queue.async { [weak self] in
            guard let self else { return }
            let files = (try? FileManager.default.contentsOfDirectory(at: self.storeDir, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
