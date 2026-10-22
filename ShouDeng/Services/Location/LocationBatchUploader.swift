import Foundation
import CoreLocation

// MARK: - Location Batch Uploader
//
// Offline queue + batch upload for location reports.
// Inspired by ios-background-geolocation: stores location reports
// to disk when offline and uploads them in batches when connectivity
// is restored. Reduces round-trips and handles tunnel/airplane scenarios.
//
// Works alongside the existing OfflineQueue (which handles individual
// fire-and-forget requests). This specifically batches location reports
// for the /v1/location/batch endpoint.

final class LocationBatchUploader {

    // MARK: - Configuration

    struct Config {
        var maxQueueSize: Int = 500          // Max buffered locations before oldest are dropped
        var batchSize: Int = 50              // Reports per batch upload
        var uploadIntervalSec: TimeInterval = 30  // How often to flush
        var maxAgeHours: Double = 48         // Discard reports older than 48h
    }

    // MARK: - Properties

    private let config: Config
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.shoudeng.locationbatch", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var flushTimer: Timer?
    private weak var apiClient: APIClient?
    private var userId: String?

    // MARK: - Models

    struct QueuedReport: Codable {
        let userId: String
        let latitude: Double
        let longitude: Double
        let accuracy: Double
        let altitude: Double?
        let speed: Double?
        let timestamp: Date
        let isInSafeZone: Bool?
        let safeZoneName: String?
        let activityType: String?
        let queuedAt: Date
    }

    struct BatchUploadRequest: Codable {
        let reports: [LocationReportRequest]
    }

    struct BatchUploadResponse: Codable {
        let success: Bool
        let processed: Int
        let errors: Int
    }

    // MARK: - Init

    init(config: Config = Config()) {
        self.config = config
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("location_batch_queue.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Setup

    func configure(apiClient: APIClient, userId: String) {
        self.apiClient = apiClient
        self.userId = userId
        startFlushTimer()
    }

    func stop() {
        flushTimer?.invalidate()
        flushTimer = nil
    }

    // MARK: - Enqueue

    /// Queue a location report for batch upload.
    /// Called from AdaptiveLocationManager when individual report fails or as primary path.
    func enqueue(location: Location, userId: String) {
        queue.async { [weak self] in
            guard let self else { return }

            var reports = self.loadQueue()

            let report = QueuedReport(
                userId: userId,
                latitude: location.latitude,
                longitude: location.longitude,
                accuracy: location.accuracy,
                altitude: location.altitude,
                speed: location.speed,
                timestamp: location.timestamp,
                isInSafeZone: location.isInSafeZone,
                safeZoneName: location.safeZoneName,
                activityType: location.activityType?.rawValue,
                queuedAt: Date()
            )

            reports.append(report)

            // Trim oldest if over max
            if reports.count > self.config.maxQueueSize {
                reports = Array(reports.suffix(self.config.maxQueueSize))
            }

            self.saveQueue(reports)
        }
    }

    // MARK: - Flush

    /// Upload queued reports in batches. Called periodically and on connectivity restore.
    func flush() {
        queue.async { [weak self] in
            guard let self, let apiClient = self.apiClient, let userId = self.userId else { return }

            var reports = self.loadQueue()
            guard !reports.isEmpty else { return }

            // Remove stale reports (older than maxAgeHours)
            let cutoff = Date().addingTimeInterval(-self.config.maxAgeHours * 3600)
            reports.removeAll { $0.queuedAt < cutoff }

            // Take a batch
            let batch = Array(reports.prefix(self.config.batchSize))
            guard !batch.isEmpty else {
                self.saveQueue(reports)
                return
            }

            // Convert to API request format
            let requestReports = batch.map { r in
                LocationReportRequest(
                    userId: r.userId,
                    latitude: r.latitude,
                    longitude: r.longitude,
                    accuracy: r.accuracy,
                    altitude: r.altitude,
                    speed: r.speed,
                    timestamp: r.timestamp,
                    isInSafeZone: r.isInSafeZone,
                    safeZoneName: r.safeZoneName,
                    activityType: r.activityType
                )
            }

            // Fire batch upload (async)
            Task {
                do {
                    let response: BatchUploadResponse = try await apiClient.post(
                        "/v1/location/batch",
                        body: BatchUploadRequest(reports: requestReports)
                    )

                    if response.success {
                        // Remove successfully uploaded reports from queue
                        self.queue.async {
                            var remaining = self.loadQueue()
                            remaining.removeFirst(min(batch.count, remaining.count))
                            self.saveQueue(remaining)

                            #if DEBUG
                            print("[LocationBatch] Uploaded \(response.processed) reports, \(response.errors) errors, \(remaining.count) remaining")
                            #endif
                        }
                    }
                } catch {
                    #if DEBUG
                    print("[LocationBatch] Batch upload failed: \(error) — will retry later")
                    #endif
                }
            }
        }
    }

    /// Number of reports waiting to be uploaded
    var pendingCount: Int {
        queue.sync {
            loadQueue().count
        }
    }

    /// Clear all queued reports (e.g., on logout)
    func clearAll() {
        queue.async { [weak self] in
            guard let self else { return }
            self.saveQueue([])
        }
    }

    // MARK: - Private

    private func startFlushTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushTimer?.invalidate()
            self.flushTimer = Timer.scheduledTimer(
                withTimeInterval: self.config.uploadIntervalSec,
                repeats: true
            ) { [weak self] _ in
                self?.flush()
            }
        }
    }

    private func loadQueue() -> [QueuedReport] {
        guard let data = try? Data(contentsOf: fileURL),
              let reports = try? decoder.decode([QueuedReport].self, from: data) else {
            return []
        }
        return reports
    }

    private func saveQueue(_ reports: [QueuedReport]) {
        guard let data = try? encoder.encode(reports) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
