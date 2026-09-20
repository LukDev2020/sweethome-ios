import Foundation

// MARK: - Offline Queue
//
// Persist-and-forward queue for operations that must eventually reach the server.
// Critical for a safety app: heartbeats, location reports, and SOS events
// must not be lost when the device is offline.
//
// Uses an append-only JSONL file on disk so items survive app termination.

final class OfflineQueue {

    struct Item: Codable {
        let id: String
        let method: String
        let path: String
        let body: Data?
        let createdAt: Date

        init(method: String, path: String, body: Data?) {
            self.id = UUID().uuidString
            self.method = method
            self.path = path
            self.body = body
            self.createdAt = Date()
        }
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.shoudeng.offlinequeue", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("offline_queue.jsonl")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Enqueue

    func enqueue(_ item: Item) {
        queue.async { [weak self] in
            guard let self else { return }

            // M6 fix: deduplicate by path + method (skip if identical pending request exists)
            if let existingData = try? Data(contentsOf: self.fileURL),
               let existingText = String(data: existingData, encoding: .utf8) {
                let lines = existingText.split(separator: "\n")
                for line in lines {
                    if let lineData = line.data(using: .utf8),
                       let existing = try? self.decoder.decode(Item.self, from: lineData),
                       existing.method == item.method && existing.path == item.path && existing.body == item.body {
                        return // Duplicate, skip
                    }
                }
            }

            guard var data = try? self.encoder.encode(item) else { return }
            data.append(contentsOf: "\n".utf8)

            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                guard let handle = try? FileHandle(forWritingTo: self.fileURL) else { return }
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: self.fileURL, options: [.atomic, .completeFileProtection])
            }
        }
    }

    // MARK: - Peek All (returns items without clearing)

    func peekAll() -> [Item] {
        var items: [Item] = []
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else { return }

            items = text
                .split(separator: "\n")
                .compactMap { line in
                    guard let lineData = line.data(using: .utf8) else { return nil }
                    return try? decoder.decode(Item.self, from: lineData)
                }
        }
        return items
    }

    // MARK: - Remove Processed Items

    func removeItems(withIds ids: Set<String>) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let data = try? Data(contentsOf: self.fileURL),
                  let text = String(data: data, encoding: .utf8) else { return }

            let remaining = text
                .split(separator: "\n")
                .filter { line in
                    guard let lineData = line.data(using: .utf8),
                          let item = try? self.decoder.decode(Item.self, from: lineData) else { return true }
                    return !ids.contains(item.id)
                }
                .joined(separator: "\n")

            let output = remaining.isEmpty ? "" : remaining + "\n"
            try? output.write(to: self.fileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Dequeue All (returns items and clears the file)
    // Kept for backward compat but prefer peekAll + removeItems

    func dequeueAll() -> [Item] {
        var items: [Item] = []
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else { return }

            items = text
                .split(separator: "\n")
                .compactMap { line in
                    guard let lineData = line.data(using: .utf8) else { return nil }
                    return try? decoder.decode(Item.self, from: lineData)
                }

            // Clear the file
            try? "".write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return items
    }

    // MARK: - Clear All (used on logout to prevent cross-user data leak)

    func clearAll() {
        queue.async { [weak self] in
            guard let self else { return }
            try? "".write(to: self.fileURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Pending Count

    var pendingCount: Int {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else { return 0 }
            return text.split(separator: "\n").count
        }
    }
}
