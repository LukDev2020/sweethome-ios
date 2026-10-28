import Foundation
import CoreLocation
import Combine

/// Manages trip recording lifecycle. Protected person starts/stops recording;
/// points are buffered locally and uploaded in batches to the backend.
final class TripRecordingService: ObservableObject {

    @Published var isRecording = false
    @Published var currentTripId: String?
    @Published var recordingStartTime: Date?
    @Published var pointCount: Int = 0
    @Published var totalDistance: Double = 0
    @Published var elapsedSeconds: TimeInterval = 0

    private var pointBuffer: [TripPoint] = []
    private var lastPoint: CLLocation?
    private var uploadTimer: Timer?
    private var elapsedTimer: Timer?
    private var apiClient: APIClient?

    private let bufferFlushSize = 30
    private let uploadIntervalSec: TimeInterval = 30
    private let maxRecordingHours: TimeInterval = 12 * 3600

    // Persistence keys
    private let activeKey = "trip_recording_active"
    private let tripIdKey = "trip_recording_id"
    private let startTimeKey = "trip_recording_start"

    func configure(apiClient: APIClient) {
        self.apiClient = apiClient
        restoreState()
    }

    // MARK: - Start Recording

    @MainActor
    func startRecording() async throws {
        guard let api = apiClient else { return }
        guard !isRecording else { return }

        let response: TripStartResponse = try await api.post(
            "/v1/trip/start",
            body: EmptyBody()
        )

        currentTripId = response.tripId
        recordingStartTime = Date()
        isRecording = true
        pointCount = 0
        totalDistance = 0
        pointBuffer = []
        lastPoint = nil

        // Persist state
        UserDefaults.standard.set(true, forKey: activeKey)
        UserDefaults.standard.set(response.tripId, forKey: tripIdKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: startTimeKey)

        startTimers()
    }

    // MARK: - Stop Recording

    @MainActor
    func stopRecording() async throws -> TripEndResponse? {
        guard let api = apiClient, let tripId = currentTripId else { return nil }
        guard isRecording else { return nil }

        // Flush remaining points
        await flushBuffer()

        let response: TripEndResponse = try await api.post(
            "/v1/trip/\(tripId)/end",
            body: EmptyBody()
        )

        clearState()
        return response
    }

    // MARK: - Cancel Recording

    @MainActor
    func cancelRecording() async {
        guard let api = apiClient, let tripId = currentTripId else { return }
        let _: [String: Bool]? = try? await api.post(
            "/v1/trip/\(tripId)/cancel",
            body: EmptyBody()
        )
        clearState()
    }

    // MARK: - Add Point (called from location callback)

    func addPoint(_ location: CLLocation) {
        guard isRecording else { return }

        let point = TripPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            altitude: location.altitude,
            speed: location.speed >= 0 ? location.speed : nil,
            timestamp: location.timestamp,
            activityType: nil
        )

        // Calculate distance
        if let last = lastPoint {
            totalDistance += location.distance(from: last)
        }
        lastPoint = location

        pointBuffer.append(point)
        DispatchQueue.main.async {
            self.pointCount += 1
        }

        if pointBuffer.count >= bufferFlushSize {
            Task { await flushBuffer() }
        }
    }

    // MARK: - Buffer Flush

    private func flushBuffer() async {
        guard let api = apiClient, let tripId = currentTripId else { return }
        guard !pointBuffer.isEmpty else { return }

        let batch = pointBuffer
        pointBuffer = []

        do {
            let _: [String: Bool] = try await api.post(
                "/v1/trip/\(tripId)/points",
                body: ["points": batch]
            )
        } catch {
            // Re-add failed points to buffer
            pointBuffer.insert(contentsOf: batch, at: 0)
            #if DEBUG
            print("[TripRecording] flush failed: \(error)")
            #endif
        }
    }

    // MARK: - Timers

    private func startTimers() {
        uploadTimer = Timer.scheduledTimer(withTimeInterval: uploadIntervalSec, repeats: true) { [weak self] _ in
            Task { await self?.flushBuffer() }
        }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            let elapsed = Date().timeIntervalSince(start)
            DispatchQueue.main.async { self.elapsedSeconds = elapsed }
            // Auto-stop after max hours
            if elapsed >= self.maxRecordingHours {
                Task { @MainActor in try? await self.stopRecording() }
            }
        }
    }

    private func stopTimers() {
        uploadTimer?.invalidate()
        uploadTimer = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    @MainActor
    private func clearState() {
        isRecording = false
        currentTripId = nil
        recordingStartTime = nil
        pointCount = 0
        totalDistance = 0
        elapsedSeconds = 0
        pointBuffer = []
        lastPoint = nil
        stopTimers()

        UserDefaults.standard.removeObject(forKey: activeKey)
        UserDefaults.standard.removeObject(forKey: tripIdKey)
        UserDefaults.standard.removeObject(forKey: startTimeKey)
    }

    private func restoreState() {
        guard UserDefaults.standard.bool(forKey: activeKey),
              let tripId = UserDefaults.standard.string(forKey: tripIdKey) else { return }
        let startTs = UserDefaults.standard.double(forKey: startTimeKey)
        guard startTs > 0 else { return }
        let start = Date(timeIntervalSince1970: startTs)
        // Don't restore if over max hours
        guard Date().timeIntervalSince(start) < maxRecordingHours else {
            Task { @MainActor in clearState() }
            return
        }
        DispatchQueue.main.async {
            self.isRecording = true
            self.currentTripId = tripId
            self.recordingStartTime = start
            self.elapsedSeconds = Date().timeIntervalSince(start)
            self.startTimers()
        }
    }

    /// Format elapsed time as HH:MM:SS
    var elapsedFormatted: String {
        let h = Int(elapsedSeconds) / 3600
        let m = (Int(elapsedSeconds) % 3600) / 60
        let s = Int(elapsedSeconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// Format distance as km or m
    var distanceFormatted: String {
        if totalDistance >= 1000 {
            return String(format: "%.1f km", totalDistance / 1000)
        }
        return String(format: "%.0f m", totalDistance)
    }
}
