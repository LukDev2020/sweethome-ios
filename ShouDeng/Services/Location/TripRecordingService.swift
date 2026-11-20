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
    /// The whole trip so far, on this phone (the live track line and the PDF report)
    @Published private(set) var livePoints: [TripPoint] = []
    /// m/s, from the latest fix
    @Published private(set) var currentSpeed: Double = 0
    /// The trip that just ended, kept so its report can still be exported
    @Published private(set) var lastFinishedTrip: FinishedTrip?
    /// Recorded on this phone only (no server): simulator runs
    @Published private(set) var isLocalOnly = false

    struct FinishedTrip {
        let points: [TripPoint]
        let start: Date
        let end: Date
    }

    /// A fix older than the recording by more than this is a cached position
    static let staleFixTolerance: TimeInterval = 5

    /// Hours at ~1 fix / 15 m: keep the line drawable, thin the oldest half when full
    static let maxLivePoints = 20_000

    private var pointBuffer: [TripPoint] = []
    private var lastPoint: CLLocation?
    private var uploadTimer: Timer?
    private var elapsedTimer: Timer?
    private var apiClient: APIClient?

    private let bufferFlushSize = 30
    /// The server keeps at most 100 points per request (routes/trip.ts)
    private let maxPointsPerRequest = 100
    /// Offline for hours: keep the newest points, never grow without bound
    private let maxBufferedPoints = 5_000
    private let uploadIntervalSec: TimeInterval = 30
    private let maxRecordingHours: TimeInterval = 12 * 3600
    private var isFlushing = false
    private var autoStopAttempted = false

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
        guard !ExploreMode.blocks("location") else { return }
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
        livePoints = []
        currentSpeed = 0
        isLocalOnly = false

        // Persist state
        UserDefaults.standard.set(true, forKey: activeKey)
        UserDefaults.standard.set(response.tripId, forKey: tripIdKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: startTimeKey)

        startTimers()
    }

    /// Records on this phone only — nothing is sent (simulator testing of the
    /// live track and the PDF report without an account).
    @MainActor
    func startLocalRecording() {
        guard !isRecording else { return }
        currentTripId = "local-\(UUID().uuidString)"
        recordingStartTime = Date()
        isRecording = true
        isLocalOnly = true
        pointCount = 0
        totalDistance = 0
        pointBuffer = []
        lastPoint = nil
        livePoints = []
        currentSpeed = 0
        startTimers()
    }

    // MARK: - Stop Recording

    @MainActor
    func stopRecording() async throws -> TripEndResponse? {
        if isLocalOnly, isRecording, let tripId = currentTripId {
            let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
            let response = TripEndResponse(tripId: tripId, totalDistanceMeters: totalDistance,
                                           pointCount: pointCount, durationSeconds: duration)
            clearState()
            return response
        }
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
        if isLocalOnly { clearState(); lastFinishedTrip = nil; return }
        guard let api = apiClient, let tripId = currentTripId else { return }
        let _: [String: Bool]? = try? await api.post(
            "/v1/trip/\(tripId)/cancel",
            body: EmptyBody()
        )
        clearState()
    }

    // MARK: - Add Point (called from location callback)

    func addPoint(_ location: CLLocation) {
        // The buffer is only touched on the main thread (flushes run there too)
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.addPoint(location) }
            return
        }
        guard isRecording else { return }
        // When GPS starts, the phone first hands over its last known position, which
        // can be minutes old and somewhere else: it isn't part of this trip
        if let start = recordingStartTime, location.timestamp < start.addingTimeInterval(-Self.staleFixTolerance) {
            return
        }

        let point = TripPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            // Negative vertical accuracy: the phone has no altitude (don't record 0 m)
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            speed: location.speed >= 0 ? location.speed : nil,
            timestamp: location.timestamp,
            activityType: nil
        )

        // Calculate distance
        if let last = lastPoint {
            totalDistance += location.distance(from: last)
        }
        if location.speed >= 0 {
            currentSpeed = location.speed
        } else if let last = lastPoint {
            let dt = location.timestamp.timeIntervalSince(last.timestamp)
            currentSpeed = dt > 0 ? location.distance(from: last) / dt : currentSpeed
        }
        lastPoint = location

        livePoints.append(point)
        if livePoints.count > Self.maxLivePoints {
            livePoints = Self.thinned(livePoints)
        }

        pointBuffer.append(point)
        if pointBuffer.count > maxBufferedPoints {
            pointBuffer.removeFirst(pointBuffer.count - maxBufferedPoints)
        }
        pointCount += 1

        if pointBuffer.count >= bufferFlushSize {
            Task { @MainActor in await self.flushBuffer() }
        }
    }

    // MARK: - Buffer Flush

    /// Sends buffered points, oldest first, at most 100 per request (what the
    /// server stores). A failed batch goes back to the front and stops the run.
    @MainActor
    private func flushBuffer() async {
        guard !isLocalOnly else { pointBuffer = []; return }
        guard !isFlushing, let api = apiClient, let tripId = currentTripId else { return }
        isFlushing = true
        defer { isFlushing = false }
        while !pointBuffer.isEmpty, currentTripId == tripId {
            let batch = Array(pointBuffer.prefix(maxPointsPerRequest))
            pointBuffer.removeFirst(batch.count)
            do {
                // { success, added } — decoded loosely; only the status matters
                let _: SuccessResponse = try await api.post(
                    "/v1/trip/\(tripId)/points",
                    body: ["points": batch]
                )
            } catch {
                if currentTripId == tripId { pointBuffer.insert(contentsOf: batch, at: 0) }
                #if DEBUG
                print("[TripRecording] flush failed: \(error)")
                #endif
                return
            }
        }
    }

    // MARK: - Timers

    private func startTimers() {
        stopTimers()
        autoStopAttempted = false
        uploadTimer = Timer.scheduledTimer(withTimeInterval: uploadIntervalSec, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.flushBuffer() }
        }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            let elapsed = Date().timeIntervalSince(start)
            self.elapsedSeconds = elapsed
            // Auto-stop after max hours — once; if the server can't be reached the
            // trip is closed locally instead of retrying every second
            if elapsed >= self.maxRecordingHours, !self.autoStopAttempted {
                self.autoStopAttempted = true
                Task { @MainActor in
                    if (try? await self.stopRecording()) == nil { self.clearState() }
                }
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
        if isRecording, let start = recordingStartTime, !livePoints.isEmpty {
            lastFinishedTrip = FinishedTrip(points: livePoints, start: start, end: Date())
        }
        livePoints = []
        currentSpeed = 0
        isLocalOnly = false
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

    /// Signing out: forget the trip on this phone (it belongs to that account)
    @MainActor
    func resetForSignOut() {
        clearState()
        lastFinishedTrip = nil
    }

    /// Every other point of the older half (the recent line stays detailed)
    static func thinned(_ points: [TripPoint]) -> [TripPoint] {
        let half = points.count / 2
        let older = stride(from: 0, to: half, by: 2).map { points[$0] }
        return older + points[half...]
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
            Task { @MainActor in await self.reloadLivePoints(tripId: tripId) }
        }
    }

    /// After a relaunch the line so far is on the server: fetch it back
    @MainActor
    private func reloadLivePoints(tripId: String) async {
        guard let api = apiClient else { return }
        guard let detail: TripDetailResponse = try? await api.get("/v1/trip/\(tripId)"),
              currentTripId == tripId else { return }
        let newest = detail.points.last?.timestamp ?? .distantPast
        livePoints = detail.points + livePoints.filter { $0.timestamp > newest }
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
