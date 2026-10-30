import Foundation

// MARK: - Offline Queue
//
// Persist-and-forward queue for operations that must eventually reach the server.
// Critical for a safety app: heartbeats, location reports, and SOS events
// must not be lost when the device is offline.
//
// Uses an append-only JSONL file on disk so items survive app termination.
// The file is protected `.completeUntilFirstUserAuthentication` (not
// `.complete`): SOS can be raised while the phone is locked (lock-screen /
// widget / BLE button) and the write must not silently fail then.

final class OfflineQueue {

    struct Item: Codable {
        let id: String
        let method: String
        let path: String
        let body: Data?
        let createdAt: Date
        /// User whose token may replay this item. Items queued by one account are
        /// never replayed under another account's token.
        var ownerId: String?

        init(method: String, path: String, body: Data?, ownerId: String? = nil) {
            self.id = UUID().uuidString
            self.method = method
            self.path = path
            self.body = body
            self.createdAt = Date()
            self.ownerId = ownerId
        }

        var isSOS: Bool { path.hasPrefix("/v1/sos/") || path.contains("/ble-separation") }
    }

    /// nil = in-memory only (Explore Mode / tests): never touches disk.
    private let fileURL: URL?
    private var memoryLines: [Data] = []
    private let queue = DispatchQueue(label: "com.shoudeng.offlinequeue", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    static let fileProtection = FileProtectionType.completeUntilFirstUserAuthentication

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline_queue.jsonl")
    }

    convenience init() {
        self.init(fileURL: OfflineQueue.defaultFileURL)
    }

    init(fileURL: URL?) {
        self.fileURL = fileURL
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Storage primitives (call on `queue`)

    private func readItems() -> [Item] {
        rawLines().compactMap { try? decoder.decode(Item.self, from: $0) }
    }

    private func rawLines() -> [Data] {
        guard let fileURL else { return memoryLines }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return data.split(separator: UInt8(ascii: "\n")).map { Data($0) }
    }

    private func writeItems(_ items: [Item]) {
        let lines = items.compactMap { try? encoder.encode($0) }
        guard let fileURL else {
            memoryLines = lines
            return
        }
        var out = Data()
        for line in lines {
            out.append(line)
            out.append(UInt8(ascii: "\n"))
        }
        do {
            try out.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            // An atomic write replaces the file: make sure the class (and backup
            // exclusion) survive the rename
            try FileManager.default.setAttributes([.protectionKey: Self.fileProtection], ofItemAtPath: fileURL.path)
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        } catch {
            #if DEBUG
            print("[OfflineQueue] write failed: \(error)")
            #endif
        }
    }

    // MARK: - Enqueue

    /// Persists the item and returns the id of the queued entry. If an identical
    /// request (method + path + body + owner) is already pending, nothing is added
    /// and the EXISTING id is returned — callers must remove by the returned id,
    /// otherwise the earlier copy would linger and replay later.
    @discardableResult
    func enqueue(_ item: Item) -> String {
        queue.sync {
            var items = readItems()
            if let existing = items.first(where: {
                $0.method == item.method && $0.path == item.path && $0.body == item.body && $0.ownerId == item.ownerId
            }) {
                return existing.id
            }
            items.append(item)
            writeItems(items)
            return item.id
        }
    }

    // MARK: - Peek All (returns items without clearing)

    func peekAll() -> [Item] {
        queue.sync { readItems() }
    }

    // MARK: - Remove Processed Items

    func removeItems(withIds ids: Set<String>) {
        guard !ids.isEmpty else { return }
        queue.sync {
            writeItems(readItems().filter { !ids.contains($0.id) })
        }
    }

    /// Remove pending items matching a predicate; returns the removed items.
    @discardableResult
    func removeItems(where shouldRemove: (Item) -> Bool) -> [Item] {
        queue.sync {
            let items = readItems()
            let removed = items.filter(shouldRemove)
            if !removed.isEmpty {
                writeItems(items.filter { !shouldRemove($0) })
            }
            return removed
        }
    }

    // MARK: - Dequeue All (returns items and clears the file)
    // Kept for backward compat but prefer peekAll + removeItems

    func dequeueAll() -> [Item] {
        queue.sync {
            let items = readItems()
            writeItems([])
            return items
        }
    }

    // MARK: - Clear All (used on logout to prevent cross-user data leak)

    func clearAll() {
        queue.sync { writeItems([]) }
    }

    /// Keep only the items matching the predicate (e.g. SOS items across logout).
    func retainOnly(_ keep: (Item) -> Bool) {
        queue.sync { writeItems(readItems().filter(keep)) }
    }

    // MARK: - Pending Count

    var pendingCount: Int {
        queue.sync { readItems().count }
    }
}
