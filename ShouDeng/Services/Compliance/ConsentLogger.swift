import Foundation

// MARK: - Consent Logger
//
// Append-only consent record store. Every "我明白了" tap,
// every permission toggle, every disclosure acknowledgment
// gets recorded with full context for legal evidence.
//
// Requirements from revised plan:
//   - User ID + timestamp + specific item + copy version
//   - Not just a boolean — full record
//   - Write-once, append-only
//   - Ready for server sync

final class ConsentLogger {

    // MARK: - Record

    struct ConsentRecord: Codable {
        let userId: String
        let timestamp: Date
        let item: String           // e.g. "onboarding_1", "disclosure_sos_v1"
        let copyVersion: String    // e.g. "v1.0"
        let granted: Bool
        let appVersion: String
        let locale: String
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
        granted: Bool = true
    ) {
        let record = ConsentRecord(
            userId: userId,
            timestamp: Date(),
            item: item,
            copyVersion: copyVersion,
            granted: granted,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            locale: Locale.current.identifier
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

    func logFeatureDisclosure(_ feature: DisclaimerCopy.FeatureDisclosure) {
        log(
            userId: currentUserId,
            item: feature.storageKey,
            copyVersion: feature.version
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
        // In production, pull from auth. For now, use device identifier.
        UserDefaults.standard.string(forKey: "currentUserId") ?? "anonymous"
    }
}
