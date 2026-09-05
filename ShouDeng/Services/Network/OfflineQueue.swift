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
            guard var data = try? self.encoder.encode(item) else { return }
            data.append(contentsOf: "\n".utf8)

            if FileManager.default.fileExists(atPath: self.fileURL.path) {
                guard let handle = try? FileHandle(forWritingTo: self.fileURL) else { return }
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: self.fileURL, options: .atomic)
            }
        }
    }

    // MARK: - Dequeue All (returns items and clears the file)

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

    // MARK: - Pending Count

    var pendingCount: Int {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else { return 0 }
            return text.split(separator: "\n").count
        }
    }
}
