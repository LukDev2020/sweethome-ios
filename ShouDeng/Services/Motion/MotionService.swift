import Foundation
import CoreMotion

// MARK: - Motion Service
//
// Bridges CoreMotion hardware to the FallDetector algorithm.
// Handles the iOS background constraints:
//   - Foreground: full 50Hz accelerometer pipeline
//   - Background: piggyback on location wake-ups for brief sensor bursts
//   - Watch: delegate to watchOS companion for continuous monitoring

final class MotionService {

    // MARK: - State

    enum ServiceState {
        case stopped
        case foreground         // Full 50Hz pipeline
        case backgroundBurst    // Brief sensor read during location wake-up
        case watchDelegated     // Watch is handling fall detection
    }

    // MARK: - Properties

    private let motionManager = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    private let fallDetector: FallDetector
    private let operationQueue: OperationQueue

    private(set) var state: ServiceState = .stopped
    private(set) var isAccelerometerAvailable: Bool = false
    private(set) var isDeviceMotionAvailable: Bool = false
    private(set) var currentActivity: CMMotionActivity?

    // Callbacks
    var onFallCandidate: (() -> Void)?
    var onFallConfirmed: (() -> Void)?
    var onActivityChange: ((CMMotionActivity) -> Void)?

    // MARK: - Init

    init(fallDetectorConfig: FallDetector.Config = .youngAdult) {
        self.fallDetector = FallDetector(config: fallDetectorConfig)

        self.operationQueue = OperationQueue()
        operationQueue.name = "com.shoudeng.motion"
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .userInteractive

        isAccelerometerAvailable = motionManager.isAccelerometerAvailable
        isDeviceMotionAvailable = motionManager.isDeviceMotionAvailable

        setupFallDetectorCallbacks()
    }

    // MARK: - Setup

    private func setupFallDetectorCallbacks() {
        fallDetector.onCandidateFall = { [weak self] _ in
            DispatchQueue.main.async {
                self?.onFallCandidate?()
            }
        }

        fallDetector.onConfirmedFall = { [weak self] in
            DispatchQueue.main.async {
                self?.onFallConfirmed?()
            }
        }

        fallDetector.onStateChange = { [weak self] oldState, newState in
            // Log state transitions for debugging and calibration
            #if DEBUG
            print("[MotionService] Fall detector: \(oldState) → \(newState)")
            #endif
            _ = self  // Silence unused warning
        }
    }

    // MARK: - Start Foreground Monitoring

    /// Full 50Hz pipeline — call when app is in foreground
    func startForegroundMonitoring() {
        guard isDeviceMotionAvailable else {
            print("[MotionService] Device motion not available")
            return
        }

        // Use DeviceMotion (not raw accelerometer) because it separates
        // gravity from user acceleration — needed for orientation detection
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0  // 50Hz

        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: operationQueue
        ) { [weak self] motion, error in
            guard let motion, error == nil else { return }

            // Feed the four-stage fall detection pipeline
            self?.fallDetector.feed(
                acceleration: CMAcceleration(
                    x: motion.userAcceleration.x + motion.gravity.x,
                    y: motion.userAcceleration.y + motion.gravity.y,
                    z: motion.userAcceleration.z + motion.gravity.z
                ),
                gravity: motion.gravity,
                userAcceleration: motion.userAcceleration,
                timestamp: motion.timestamp
            )
        }

        // Also start activity recognition — helps classify false alarms
        startActivityRecognition()

        state = .foreground
    }

    /// Stop foreground monitoring (app going to background)
    func stopForegroundMonitoring() {
        motionManager.stopDeviceMotionUpdates()
        state = .stopped
    }

    // MARK: - Background Burst

    /// Brief sensor read during a background location wake-up.
    /// Can't run the full pipeline, but can check for prolonged stillness
    /// as a proxy for "person might be unconscious."
    func performBackgroundBurst(completion: @escaping (BackgroundBurstResult) -> Void) {
        guard isDeviceMotionAvailable else {
            completion(.unavailable)
            return
        }

        state = .backgroundBurst

        var samples: [(svm: Double, timestamp: TimeInterval)] = []
        let burstDuration: TimeInterval = 3.0  // 3 seconds of data
        let startTime = Date()

        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0

        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: operationQueue
        ) { [weak self] motion, error in
            guard let motion, error == nil else { return }

            let ax = motion.userAcceleration.x + motion.gravity.x
            let ay = motion.userAcceleration.y + motion.gravity.y
            let az = motion.userAcceleration.z + motion.gravity.z
            let svm = sqrt(ax * ax + ay * ay + az * az)

            samples.append((svm: svm, timestamp: motion.timestamp))

            // After burst duration, analyze
            if Date().timeIntervalSince(startTime) >= burstDuration {
                self?.motionManager.stopDeviceMotionUpdates()
                self?.state = .stopped

                let result = self?.analyzeBurst(samples) ?? .normal
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
    }

    enum BackgroundBurstResult {
        case normal                   // Person seems active
        case prolongedStillness       // Very low variance — might be unconscious
        case unavailable              // Sensors not available
    }

    private func analyzeBurst(_ samples: [(svm: Double, timestamp: TimeInterval)]) -> BackgroundBurstResult {
        guard samples.count > 10 else { return .unavailable }

        let mean = samples.reduce(0) { $0 + $1.svm } / Double(samples.count)
        let variance = samples.reduce(0) { $0 + ($1.svm - mean) * ($1.svm - mean) } / Double(samples.count - 1)

        // Very low variance = no movement at all
        if variance < 0.02 {
            return .prolongedStillness
        }

        return .normal
    }

    // MARK: - Activity Recognition

    private func startActivityRecognition() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }

        activityManager.startActivityUpdates(to: operationQueue) { [weak self] activity in
            guard let activity else { return }
            self?.currentActivity = activity

            DispatchQueue.main.async {
                self?.onActivityChange?(activity)
            }
        }
    }

    // MARK: - User Actions

    /// User tapped "I'm fine" during fall confirmation dialog
    func userDismissedFallAlert() {
        fallDetector.userDismissed()

        // Short delay, then reset to monitoring
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.fallDetector.reset()
        }
    }

    // MARK: - Metrics

    var fallDetectorMetrics: FallDetector.Metrics {
        fallDetector.metrics
    }

    var fallDetectorState: FallDetector.State {
        fallDetector.state
    }
}
