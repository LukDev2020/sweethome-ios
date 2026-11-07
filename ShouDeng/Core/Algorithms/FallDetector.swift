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
// If all four pass → onCandidateFall(metrics) and the detector waits in
// .awaitingResponse until resolve(). The 60-second "Are you OK?" countdown is the
// coordinator's (wall clock, survives the screen locking) — never this loop's, which
// only runs while sensor samples arrive.
//
// References: SisFall, UMAFall, FallAllD datasets for threshold calibration.
// Verified with synthetic traces (FallSensorTrace, FallScenarioTests).

final class FallDetector {

    // MARK: - Configuration

    struct Config {
        // Stage 1: Free-fall
        var freeFallThresholdG: Double = 0.6
        var freeFallMinDurationMs: Double = 100
        /// Longer than this in "free fall" is not a person falling (thrown, a lift…)
        var freeFallMaxDurationSec: Double = 2.0

        // Stage 2: Impact
        var impactThresholdG: Double = 2.5
        var impactWindowAfterFreeFallMs: Double = 500

        // Stage 3: Orientation change
        var orientationChangeMinDegrees: Double = 60
        var orientationSampleWindowSec: Double = 2.0

        // Stage 4: Prolonged stillness. A person lying still measures < 0.001;
        // walking with the phone in a pocket ≈ 0.045, so the old 0.05 let walking pass.
        var stillnessMaxVariance: Double = 0.01
        var stillnessDurationSec: Double = 15.0

        // Confirmation (the coordinator's countdown)
        var confirmationTimeoutSec: Double = 60.0

        // Sampling
        var sampleRateHz: Double = 50.0

        static let youngAdult = Config()

        static let elderly = Config(
            freeFallThresholdG: 0.65,
            impactThresholdG: 2.0,
            orientationChangeMinDegrees: 50,
            stillnessMaxVariance: 0.012,
            stillnessDurationSec: 10.0
        )

        static let phoneInPocket = Config(
            impactThresholdG: 3.0,
            orientationChangeMinDegrees: 45
        )
    }

    /// What the sensors saw — kept with the detection (guardians, incident reports, tuning).
    struct FallMetrics: Equatable {
        var freeFallMs: Double = 0
        var peakImpactG: Double = 0
        var orientationChangeDeg: Double = 0
        var stillnessVariance: Double = 0
        static let detectorName = "threshold-v2"
    }

    // MARK: - State Machine

    enum State: Equatable {
        case monitoring
        case freeFallDetected(startTime: TimeInterval)
        case impactDetected(impactTime: TimeInterval)
        case waitingStillness(since: TimeInterval)
        /// All four stages passed; paused until resolve() (the person answered, or the SOS went out)
        case awaitingResponse(detectedAt: TimeInterval)
    }

    // MARK: - Ring Buffer for Sensor Data

    struct SensorSample {
        let timestamp: TimeInterval   // CMAbsoluteTime
        let svm: Double               // sqrt(ax² + ay² + az²)
        let gravity: simd_double3     // Device gravity vector from CMDeviceMotion
        let userAccel: simd_double3   // User acceleration (minus gravity)
    }

    private var buffer: [SensorSample] = []
    /// Long enough for the gravity windows before and after the fall
    private let bufferCapacity: Int

    // MARK: - State

    private(set) var state: State = .monitoring
    private(set) var config: Config
    private var gravityBeforeFall: simd_double3 = .zero
    private var freeFallOnset: TimeInterval = 0
    private var freeFallEndTime: TimeInterval?
    private var observed = FallMetrics()
    /// Running variance over the whole stillness window (Welford), not just the buffer
    private var stillCount = 0
    private var stillMean = 0.0
    private var stillM2 = 0.0

    // Stats
    private(set) var totalSamplesProcessed: Int = 0
    private(set) var falseAlarmCount: Int = 0
    private(set) var detectionCount: Int = 0

    // Callbacks
    var onStateChange: ((State, State) -> Void)?
    var onCandidateFall: ((FallMetrics) -> Void)?

    // MARK: - Init

    init(config: Config = .youngAdult) {
        self.config = config
        self.bufferCapacity = Int(config.sampleRateHz * (config.orientationSampleWindowSec * 2 + config.freeFallMaxDurationSec + 1))
        self.buffer.reserveCapacity(bufferCapacity)
    }

    // MARK: - Feed Sensor Data

    /// Called at 50Hz from CMMotionManager. This is the hot path.
    func feed(acceleration: CMAcceleration, gravity: CMAcceleration,
              userAcceleration: CMAcceleration, timestamp: TimeInterval) {

        let ax = acceleration.x, ay = acceleration.y, az = acceleration.z
        let svm = sqrt(ax * ax + ay * ay + az * az)

        let sample = SensorSample(
            timestamp: timestamp,
            svm: svm,
            gravity: simd_double3(gravity.x, gravity.y, gravity.z),
            userAccel: simd_double3(userAcceleration.x, userAcceleration.y, userAcceleration.z)
        )

        buffer.append(sample)
        if buffer.count > bufferCapacity {
            buffer.removeFirst(buffer.count - bufferCapacity)
        }

        totalSamplesProcessed += 1
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
            guard svm < config.freeFallThresholdG else { return }
            let windowStart = t - (config.freeFallMinDurationMs / 1000.0)
            let recent = samplesInWindow(from: windowStart, to: t)
            let needed = Int(config.sampleRateHz * config.freeFallMinDurationMs / 1000.0)
            guard recent.count >= needed, recent.allSatisfy({ $0.svm < config.freeFallThresholdG }) else { return }
            freeFallOnset = recent.first?.timestamp ?? t
            freeFallEndTime = nil
            observed = FallMetrics()
            // Gravity BEFORE the fall, for the orientation comparison
            gravityBeforeFall = averageGravity(before: freeFallOnset, windowSec: config.orientationSampleWindowSec)
            transition(to: .freeFallDetected(startTime: freeFallOnset))

        // ──────────────────────────────────────────────────
        // FREE-FALL: still falling, or the impact within 500 ms of the fall's end
        // ──────────────────────────────────────────────────
        case .freeFallDetected(let onset):
            if svm < config.freeFallThresholdG {
                freeFallEndTime = nil           // (still) falling
                if t - onset > config.freeFallMaxDurationSec { transition(to: .monitoring) }
                return
            }
            let end = freeFallEndTime ?? t
            freeFallEndTime = end
            if svm > config.impactThresholdG {
                observed.freeFallMs = (end - onset) * 1000
                observed.peakImpactG = svm
                transition(to: .impactDetected(impactTime: t))
            } else if (t - end) * 1000 > config.impactWindowAfterFreeFallMs {
                transition(to: .monitoring)     // no impact: not a fall
            }

        // ──────────────────────────────────────────────────
        // IMPACT: let the body settle, then compare orientation
        // ──────────────────────────────────────────────────
        case .impactDetected(let impactTime):
            if t - impactTime < 0.3 { observed.peakImpactG = max(observed.peakImpactG, svm) }
            guard t - impactTime >= config.orientationSampleWindowSec else { return }
            let gravityAfterFall = averageGravity(before: t, windowSec: config.orientationSampleWindowSec)
            let angle = angleBetween(gravityBeforeFall, gravityAfterFall)
            if angle > config.orientationChangeMinDegrees {
                observed.orientationChangeDeg = angle
                stillCount = 0; stillMean = 0; stillM2 = 0
                transition(to: .waitingStillness(since: t))
            } else {
                // Still upright — they caught themselves, or it was a jump
                transition(to: .monitoring)
            }

        // ──────────────────────────────────────────────────
        // STILLNESS: no movement for the whole window
        // ──────────────────────────────────────────────────
        case .waitingStillness(let since):
            stillCount += 1
            let delta = svm - stillMean
            stillMean += delta / Double(stillCount)
            stillM2 += delta * (svm - stillMean)

            // Moving clearly in the last 2 s — they got up
            if svmVariance(from: max(since, t - 2.0), to: t) > config.stillnessMaxVariance * 3 {
                transition(to: .monitoring)
                return
            }
            guard t - since >= config.stillnessDurationSec else { return }
            let variance = stillCount > 1 ? stillM2 / Double(stillCount - 1) : 0
            if variance < config.stillnessMaxVariance {
                // ALL FOUR STAGES PASSED — ask the person
                observed.stillnessVariance = variance
                detectionCount += 1
                transition(to: .awaitingResponse(detectedAt: t))
                onCandidateFall?(observed)
            } else {
                transition(to: .monitoring)
            }

        case .awaitingResponse:
            break   // paused until resolve()
        }
    }

    // MARK: - Outcome

    /// The person answered ("I'm OK" → dismissed) or the SOS went out: watch again.
    func resolve(dismissed: Bool) {
        if dismissed { falseAlarmCount += 1 }
        buffer.removeAll(keepingCapacity: true)
        transition(to: .monitoring)
    }

    /// Reset to monitoring (tests, restarting the pipeline)
    func reset() {
        buffer.removeAll(keepingCapacity: true)
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
        // Newest samples are at the end: walk back only as far as needed
        var out: [SensorSample] = []
        for s in buffer.reversed() {
            if s.timestamp < start { break }
            if s.timestamp <= end { out.append(s) }
        }
        return out.reversed()
    }

    /// Average gravity vector over a time window ending at `before`
    private func averageGravity(before: TimeInterval, windowSec: Double) -> simd_double3 {
        let samples = samplesInWindow(from: before - windowSec, to: before)
        guard !samples.isEmpty else { return simd_double3(0, 0, -1) }
        return samples.reduce(simd_double3.zero) { $0 + $1.gravity } / Double(samples.count)
    }

    /// Angle in degrees between two vectors
    private func angleBetween(_ a: simd_double3, _ b: simd_double3) -> Double {
        let dot = simd_clamp(simd_dot(simd_normalize(a), simd_normalize(b)), -1.0, 1.0)
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
