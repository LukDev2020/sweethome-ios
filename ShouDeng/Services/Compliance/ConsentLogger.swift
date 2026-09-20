import Foundation
import UIKit

// MARK: - Consent Logger
//
// Append-only consent record store. Every "我明白了" tap,
// every permission toggle, every disclosure acknowledgment
// gets recorded with full context for legal evidence.
//
// From PDF section 5:
//   consent_log { user_id, timestamp, consent_key,
//     copy_version, locale, action, device_id, app_version }
//   版本号一项不可省略。

final class ConsentLogger {

    // MARK: - Record

    struct ConsentRecord: Codable {
        let userId: String
        let timestamp: Date
        let item: String           // consent key, e.g. "onboard.not_emergency"
        let copyVersion: String    // e.g. "v1.1"
        let action: String         // "granted", "denied", "revoked"
        let appVersion: String
        let locale: String
        let deviceId: String
    }

    // MARK: - Singleton

    static let shared = ConsentLogger()

    // MARK: - Storage

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let queue = DispatchQueue(label: "com.shoudeng.consent", qos: .utility)

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("consent_log.jsonl")
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Log

    func log(
        userId: String,
        item: String,
        copyVersion: String,
        action: String = "granted"
    ) {
        let record = ConsentRecord(
            userId: userId,
            timestamp: Date(),
            item: item,
            copyVersion: copyVersion,
            action: action,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            locale: Locale.current.identifier,
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        )

        queue.async { [weak self] in
            self?.appendRecord(record)
        }
    }

    // MARK: - Convenience

    func logOnboardingScreen(_ screenId: String) {
        log(
            userId: currentUserId,
            item: screenId,
            copyVersion: DisclaimerCopy.Onboarding.version
        )
    }

    func logFeatureDisclosure(_ feature: DisclaimerCopy.FeatureDisclosure, granted: Bool = true) {
        log(
            userId: currentUserId,
            item: feature.consentKey,
            copyVersion: feature.version,
            action: granted ? "granted" : "denied"
        )
    }

    func logSOSFirstUse() {
        log(
            userId: currentUserId,
            item: "sos.first_use",
            copyVersion: DisclaimerCopy.FeatureDisclosure.sos.version
        )
    }

    func logDegradation(_ warningId: String) {
        log(
            userId: currentUserId,
            item: "degrade.\(warningId)",
            copyVersion: "v1.1"
        )
    }

    // MARK: - Read (for debug / export)

    func allRecords() -> [ConsentRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return text
            .split(separator: "\n")
            .compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(ConsentRecord.self, from: lineData)
            }
    }

    // MARK: - Private

    private func appendRecord(_ record: ConsentRecord) {
        guard var data = try? encoder.encode(record) else { return }
        data.append(contentsOf: "\n".utf8)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private var currentUserId: String {
        UserDefaults.standard.string(forKey: "currentUserId") ?? UIDevice.current.identifierForVendor?.uuidString ?? "unknown_device"
    }
}
