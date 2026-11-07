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
    private let mlFallClassifier: MLFallClassifier
    private let operationQueue: OperationQueue

    private(set) var state: ServiceState = .stopped
    private(set) var isAccelerometerAvailable: Bool = false
    private(set) var isDeviceMotionAvailable: Bool = false
    private(set) var currentActivity: CMMotionActivity?

    // Callbacks
    /// All four stages passed: ask "Are you OK?" (the countdown is the coordinator's)
    var onFallCandidate: ((FallDetector.FallMetrics) -> Void)?
    var onActivityChange: ((CMMotionActivity) -> Void)?

    // MARK: - Init

    init(fallDetectorConfig: FallDetector.Config = .youngAdult,
         mlClassifierConfig: MLFallClassifier.Config = MLFallClassifier.Config()) {
        self.fallDetector = FallDetector(config: fallDetectorConfig)
        self.mlFallClassifier = MLFallClassifier(config: mlClassifierConfig)

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
        fallDetector.onCandidateFall = { [weak self] metrics in
            DispatchQueue.main.async {
                self?.onFallCandidate?(metrics)
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
        guard !ExploreMode.blocks("motion") else { return }
        guard state != .foreground else { return }
        guard isDeviceMotionAvailable else {
            #if DEBUG
            print("[MotionService] Device motion not available")
            #endif
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

            let totalAccel = CMAcceleration(
                x: motion.userAcceleration.x + motion.gravity.x,
                y: motion.userAcceleration.y + motion.gravity.y,
                z: motion.userAcceleration.z + motion.gravity.z
            )

            // Feed the four-stage fall detection pipeline
            self?.fallDetector.feed(
                acceleration: totalAccel,
                gravity: motion.gravity,
                userAcceleration: motion.userAcceleration,
                timestamp: motion.timestamp
            )

            // Feed the ML classifier in parallel (shadow mode until model is available)
            self?.mlFallClassifier.feed(
                acceleration: totalAccel,
                rotationRate: motion.rotationRate,
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
        // The burst shares the device-motion stream with the foreground fall
        // pipeline; stopping it here would silently switch fall detection off.
        guard state != .foreground else {
            completion(.normal)
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

    // MARK: - Outcome

    /// The person answered "I'm OK", or the SOS went out: the detector watches again.
    /// (It used to stay "confirmed" after an SOS, so a second fall went unnoticed.)
    func resolveFall(dismissed: Bool) {
        operationQueue.addOperation { [fallDetector] in
            fallDetector.resolve(dismissed: dismissed)
        }
    }

    /// Replays a recorded movement through the real detector, on the sensor queue —
    /// the whole chain runs as for a real fall ("Test fall detection", Explore Mode,
    /// the simulator, which has no motion sensors).
    func simulateFall(_ trace: FallSensorTrace = .forwardFall()) {
        operationQueue.addOperation { [fallDetector] in
            fallDetector.reset()
            fallDetector.feed(trace)
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
