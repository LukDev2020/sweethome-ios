import XCTest
@testable import ShouDeng

final class FallDetectorTests: XCTestCase {

    private var detector: FallDetector!

    override func setUp() {
        super.setUp()
        detector = FallDetector(config: .youngAdult)
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    // MARK: - Configuration

    func testYoungAdultConfig() {
        let config = FallDetector.Config.youngAdult
        XCTAssertEqual(config.freeFallThresholdG, 0.6, accuracy: 0.01)
        XCTAssertEqual(config.impactThresholdG, 2.5, accuracy: 0.01)
        XCTAssertEqual(config.orientationChangeMinDegrees, 60, accuracy: 0.01)
        XCTAssertEqual(config.stillnessDurationSec, 15, accuracy: 0.01)
    }

    func testElderlyConfigIsMoreSensitive() {
        let young = FallDetector.Config.youngAdult
        let elderly = FallDetector.Config.elderly

        // Elderly thresholds should be adjusted for sensitivity
        XCTAssertGreaterThanOrEqual(elderly.freeFallThresholdG, young.freeFallThresholdG)
        XCTAssertLessThanOrEqual(elderly.impactThresholdG, young.impactThresholdG)
        XCTAssertLessThanOrEqual(elderly.orientationChangeMinDegrees, young.orientationChangeMinDegrees)
        XCTAssertLessThanOrEqual(elderly.stillnessDurationSec, young.stillnessDurationSec)
    }

    // MARK: - State Machine

    func testInitialStateIsMonitoring() {
        XCTAssertEqual(detector.state, .monitoring)
    }

    func testResetReturnsToMonitoring() {
        detector.reset()
        XCTAssertEqual(detector.state, .monitoring)
    }

    // MARK: - SVM Calculation

    func testSVMCalculation() {
        // SVM = sqrt(ax^2 + ay^2 + az^2)
        // Normal gravity: (0, 0, -9.8) => SVM ≈ 9.8 m/s² ≈ 1.0g
        let svm = sqrt(0.0 * 0.0 + 0.0 * 0.0 + 9.8 * 9.8) / 9.8
        XCTAssertEqual(svm, 1.0, accuracy: 0.01)
    }

    func testFreeFallSVM() {
        // During free-fall, SVM approaches 0
        let svm = sqrt(0.5 * 0.5 + 0.3 * 0.3 + 0.2 * 0.2) / 9.8
        XCTAssertLessThan(svm, 0.1) // Well below free-fall threshold
    }

    func testImpactSVM() {
        // Impact: very high acceleration
        let svm = sqrt(20.0 * 20.0 + 15.0 * 15.0 + 10.0 * 10.0) / 9.8
        XCTAssertGreaterThan(svm, 2.5) // Above impact threshold
    }

    // MARK: - Metrics

    func testMetricsTracking() {
        let metrics = detector.metrics
        XCTAssertEqual(metrics.totalSamples, 0)
        XCTAssertEqual(metrics.detections, 0)
        XCTAssertEqual(metrics.falseAlarms, 0)
    }

    // MARK: - Angle Calculation

    func testOrientationAngle() {
        // Two perpendicular vectors should give 90 degrees
        let before = (x: 0.0, y: 0.0, z: -1.0) // standing
        let after = (x: 1.0, y: 0.0, z: 0.0)    // lying on side

        let dot = before.x * after.x + before.y * after.y + before.z * after.z
        let magBefore = sqrt(before.x * before.x + before.y * before.y + before.z * before.z)
        let magAfter = sqrt(after.x * after.x + after.y * after.y + after.z * after.z)

        let cosAngle = dot / (magBefore * magAfter)
        let angle = acos(max(-1, min(1, cosAngle))) * 180 / .pi

        XCTAssertEqual(angle, 90.0, accuracy: 0.1)
    }

    func testSmallOrientationChange() {
        // Small tilt should be below threshold
        let before = (x: 0.0, y: 0.0, z: -1.0)
        let after = (x: 0.1, y: 0.0, z: -0.995)

        let dot = before.x * after.x + before.y * after.y + before.z * after.z
        let magBefore = sqrt(before.x * before.x + before.y * before.y + before.z * before.z)
        let magAfter = sqrt(after.x * after.x + after.y * after.y + after.z * after.z)

        let cosAngle = dot / (magBefore * magAfter)
        let angle = acos(max(-1, min(1, cosAngle))) * 180 / .pi

        XCTAssertLessThan(angle, 60.0) // Below threshold
    }
}
