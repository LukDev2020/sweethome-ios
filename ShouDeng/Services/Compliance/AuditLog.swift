import Foundation
import UIKit

// MARK: - Audit Log
//
// Append-only, timestamped audit log for compliance-critical events.
// Each entry records user ID, event type, version, and device context.

enum AuditLog {

    enum Event: String, Codable {
        case disclaimerAccepted = "disclaimer_accepted"
        case roleSelected = "role_selected"
        case inviteAccepted = "invite_accepted"
        case accountDeleted = "account_deleted"
    }

    struct Entry: Codable {
        let userId: String
        let timestamp: Date
        let event: String
        let version: String
        let appVersion: String
        let locale: String
        let deviceId: String
    }

    private static let queue = DispatchQueue(label: "com.shoudeng.auditlog", qos: .utility)
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("audit_log.jsonl")
    }

    static func record(event: Event, version: String) {
        let entry = Entry(
            userId: currentUserId,
            timestamp: Date(),
            event: event.rawValue,
            version: version,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            locale: Locale.current.identifier,
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        )

        queue.async {
            guard var data = try? encoder.encode(entry) else { return }
            data.append(contentsOf: "\n".utf8)

            let url = fileURL
            if FileManager.default.fileExists(atPath: url.path) {
                guard let handle = try? FileHandle(forWritingTo: url) else { return }
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static var currentUserId: String {
        UserDefaults.standard.string(forKey: "currentUserId")
            ?? UIDevice.current.identifierForVendor?.uuidString
            ?? "unknown_device"
    }
}
