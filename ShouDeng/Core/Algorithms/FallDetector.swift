import Foundation
import CoreMotion
import simd

// MARK: - Fall Detection: Four-Stage Sequential Pipeline
//
// Stage 1: Free-fall  — SVM drops below 0.6g for > 100ms
// Stage 2: Impact     — SVM spikes above threshold within 500ms of free-fall end
// Stage 3: Orientation — gravity vector rotates > 60 degrees
// Stage 4: Stillness  — SVM variance stays below threshold for 15 seconds
//
// ALL FOUR must occur in sequence. Any break resets to monitoring.
// If all four pass → 60-second on-device confirmation dialog.
// User taps "I'm fine" → cancel. Timeout → escalate to SOS.
//
// References: SisFall, UMAFall, FallAllD datasets for threshold calibration.

final class FallDetector {

    // MARK: - Configuration

    struct Config {
        // Stage 1: Free-fall
        var freeFallThresholdG: Double = 0.6
        var freeFallMinDurationMs: Double = 100

        // Stage 2: Impact
        var impactThresholdG: Double = 2.5
        var impactWindowAfterFreeFallMs: Double = 500

        // Stage 3: Orientation change
        var orientationChangeMinDegrees: Double = 60
        var orientationSampleWindowSec: Double = 2.0

        // Stage 4: Prolonged stillness
        var stillnessMaxVariance: Double = 0.05
        var stillnessDurationSec: Double = 15.0

        // Confirmation
        var confirmationTimeoutSec: Double = 60.0

        // Sampling
        var sampleRateHz: Double = 50.0

        static let youngAdult = Config()

        static let elderly = Config(
            freeFallThresholdG: 0.65,
            impactThresholdG: 2.0,
            orientationChangeMinDegrees: 50,
            stillnessMaxVariance: 0.06,
            stillnessDurationSec: 10.0
        )

        static let phoneInPocket = Config(
            impactThresholdG: 3.0,
            orientationChangeMinDegrees: 45
        )
    }

    // MARK: - State Machine

    enum State: Equatable {
        case monitoring
        case freeFallDetected(startTime: TimeInterval)
        case impactDetected(impactTime: TimeInterval)
        case orientationChanged(changeTime: TimeInterval)
        case waitingStillness(since: TimeInterval)
        case candidateFall(detectedAt: TimeInterval)
        case confirmationPending(expiresAt: TimeInterval)
        case confirmed                // User didn't respond — escalate
        case cancelled                // User tapped "I'm fine"
    }

    // MARK: - Ring Buffer for Sensor Data

    struct SensorSample {
        let timestamp: TimeInterval   // CMAbsoluteTime
        let svm: Double               // sqrt(ax² + ay² + az²)
        let gravity: simd_double3     // Device gravity vector from CMDeviceMotion
        let userAccel: simd_double3   // User acceleration (minus gravity)
    }

    private var buffer: [SensorSample] = []
    private let bufferCapacity: Int    // ~5 seconds worth

    // MARK: - State

    private(set) var state: State = .monitoring
    private(set) var config: Config
    private var gravityBeforeFall: simd_double3 = .zero
    private var freeFallEndTime: TimeInterval = 0

    // Stats
    private(set) var totalSamplesProcessed: Int = 0
    private(set) var falseAlarmCount: Int = 0
    private(set) var detectionCount: Int = 0

    // Callbacks
    var onStateChange: ((State, State) -> Void)?
    var onCandidateFall: ((TimeInterval) -> Void)?
    var onConfirmedFall: (() -> Void)?

    // MARK: - Init

    init(config: Config = .youngAdult) {
        self.config = config
        self.bufferCapacity = Int(config.sampleRateHz * 5)  // 5 seconds
        self.buffer.reserveCapacity(bufferCapacity)
    }

    // MARK: - Feed Sensor Data

    /// Called at 50Hz from CMMotionManager. This is the hot path.
    func feed(acceleration: CMAcceleration, gravity: CMAcceleration,
              userAcceleration: CMAcceleration, timestamp: TimeInterval) {

        let ax = acceleration.x, ay = acceleration.y, az = acceleration.z
        let svm = sqrt(ax * ax + ay * ay + az * az)

        let gravVec = simd_double3(gravity.x, gravity.y, gravity.z)
        let userVec = simd_double3(userAcceleration.x, userAcceleration.y, userAcceleration.z)

        let sample = SensorSample(
            timestamp: timestamp,
            svm: svm,
            gravity: gravVec,
            userAccel: userVec
        )

        // Ring buffer
        buffer.append(sample)
        if buffer.count > bufferCapacity {
            buffer.removeFirst(buffer.count - bufferCapacity)
        }

        totalSamplesProcessed += 1

        // Run state machine
        evaluate(sample: sample)
    }

    // MARK: - State Machine Evaluation

    private func evaluate(sample: SensorSample) {
        let t = sample.timestamp
        let svm = sample.svm

        switch state {

        // ──────────────────────────────────────────────────
        // MONITORING: Looking for free-fall onset
        // ──────────────────────────────────────────────────
        case .monitoring:
            if svm < config.freeFallThresholdG {
                // Potential free-fall start — check if it persists
                let windowStart = t - (config.freeFallMinDurationMs / 1000.0)
                let recentSamples = samplesInWindow(from: windowStart, to: t)

                let allBelowThreshold = recentSamples.allSatisfy {
                    $0.svm < config.freeFallThresholdG
                }

                if allBelowThreshold && recentSamples.count >= Int(config.sampleRateHz * config.freeFallMinDurationMs / 1000.0) {
                    // Capture gravity vector BEFORE the fall for orientation comparison
                    gravityBeforeFall = averageGravity(
                        before: recentSamples.first?.timestamp ?? t,
                        windowSec: config.orientationSampleWindowSec
                    )
                    transition(to: .freeFallDetected(startTime: t))
                }
            }

        // ──────────────────────────────────────────────────
        // FREE-FALL DETECTED: Looking for impact spike
        // ──────────────────────────────────────────────────
        case .freeFallDetected(let startTime):
            let elapsed = (t - startTime) * 1000  // ms

            if elapsed > config.impactWindowAfterFreeFallMs {
                // Too much time passed without impact — not a fall
                transition(to: .monitoring)
                return
            }

            if svm >= config.freeFallThresholdG {
                freeFallEndTime = t  // Free-fall ended
            }

            if svm > config.impactThresholdG {
                transition(to: .impactDetected(impactTime: t))
            }

        // ──────────────────────────────────────────────────
        // IMPACT DETECTED: Check orientation change
        // ──────────────────────────────────────────────────
        case .impactDetected(let impactTime):
            let elapsed = t - impactTime

            // Wait for post-impact settle period (2 seconds)
            if elapsed < config.orientationSampleWindowSec {
                return
            }

            // Compare gravity vector before fall vs after impact
            let gravityAfterFall = averageGravity(
                before: t,
                windowSec: config.orientationSampleWindowSec
            )

            let angleDegrees = angleBetween(gravityBeforeFall, gravityAfterFall)

            if angleDegrees > config.orientationChangeMinDegrees {
                transition(to: .orientationChanged(changeTime: t))
            } else {
                // Orientation didn't change enough — person probably caught themselves
                transition(to: .monitoring)
            }

        // ──────────────────────────────────────────────────
        // ORIENTATION CHANGED: Wait for prolonged stillness
        // ──────────────────────────────────────────────────
        case .orientationChanged(let changeTime):
            transition(to: .waitingStillness(since: changeTime))

        case .waitingStillness(let since):
            let elapsed = t - since

            if elapsed >= config.stillnessDurationSec {
                // Check variance over the stillness window
                let variance = svmVariance(
                    from: since,
                    to: t
                )

                if variance < config.stillnessMaxVariance {
                    // ALL FOUR STAGES PASSED — candidate fall
                    detectionCount += 1
                    transition(to: .candidateFall(detectedAt: t))
                    onCandidateFall?(t)
                } else {
                    // Person is moving — they got up, not a fall
                    transition(to: .monitoring)
                }
            } else {
                // Still waiting — but check if person started moving (early exit)
                let recentVariance = svmVariance(
                    from: max(since, t - 2.0),
                    to: t
                )
                if recentVariance > config.stillnessMaxVariance * 3 {
                    // Significant movement detected — person recovered
                    transition(to: .monitoring)
                }
            }

        // ──────────────────────────────────────────────────
        // CANDIDATE FALL: Waiting for user confirmation
        // ──────────────────────────────────────────────────
        case .candidateFall(let detectedAt):
            let expires = detectedAt + config.confirmationTimeoutSec
            transition(to: .confirmationPending(expiresAt: expires))

        case .confirmationPending(let expiresAt):
            if t >= expiresAt {
                // User didn't respond in 60 seconds — confirm fall
                transition(to: .confirmed)
                onConfirmedFall?()
            }
            // Otherwise keep waiting — UI handles the countdown

        case .confirmed, .cancelled:
            break  // Terminal states, call reset() to start over
        }
    }

    // MARK: - User Actions

    /// User tapped "I'm fine" during confirmation countdown
    func userDismissed() {
        falseAlarmCount += 1
        transition(to: .cancelled)
    }

    /// Reset to monitoring after a detection cycle completes
    func reset() {
        transition(to: .monitoring)
    }

    // MARK: - Helpers

    private func transition(to newState: State) {
        let old = state
        state = newState
        if old != newState {
            onStateChange?(old, newState)
        }
    }

    private func samplesInWindow(from start: TimeInterval, to end: TimeInterval) -> [SensorSample] {
        buffer.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    /// Average gravity vector over a time window ending at `before`
    private func averageGravity(before: TimeInterval, windowSec: Double) -> simd_double3 {
        let windowStart = before - windowSec
        let samples = samplesInWindow(from: windowStart, to: before)

        guard !samples.isEmpty else { return simd_double3(0, 0, -1) }

        var sum = simd_double3.zero
        for s in samples {
            sum += s.gravity
        }
        return sum / Double(samples.count)
    }

    /// Angle in degrees between two vectors
    private func angleBetween(_ a: simd_double3, _ b: simd_double3) -> Double {
        let normA = simd_normalize(a)
        let normB = simd_normalize(b)
        let dot = simd_clamp(simd_dot(normA, normB), -1.0, 1.0)
        return acos(dot) * 180.0 / .pi
    }

    /// Variance of SVM values in a time window
    private func svmVariance(from start: TimeInterval, to end: TimeInterval) -> Double {
        let samples = samplesInWindow(from: start, to: end)
        guard samples.count > 1 else { return 0 }

        let mean = samples.reduce(0.0) { $0 + $1.svm } / Double(samples.count)
        let sumSquaredDiff = samples.reduce(0.0) { $0 + ($1.svm - mean) * ($1.svm - mean) }
        return sumSquaredDiff / Double(samples.count - 1)
    }
}

// MARK: - Fall Detection Metrics (for calibration dashboard)

extension FallDetector {
    struct Metrics {
        let totalSamples: Int
        let detections: Int
        let falseAlarms: Int
        let falseAlarmRate: Double      // Per week estimate
        let currentState: State

        var precision: Double {
            guard detections > 0 else { return 0 }
            return Double(detections - falseAlarms) / Double(detections)
        }
    }

    var metrics: Metrics {
        Metrics(
            totalSamples: totalSamplesProcessed,
            detections: detectionCount,
            falseAlarms: falseAlarmCount,
            falseAlarmRate: 0,  // Computed from time-windowed data server-side
            currentState: state
        )
    }
}
