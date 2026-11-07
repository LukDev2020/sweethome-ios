import XCTest
@testable import ShouDeng

/// Feeds realistic 50 Hz sensor traces through the real FallDetector: falls must reach
/// the "Are you OK?" check, everyday movements must not.
final class FallScenarioTests: XCTestCase {

    private func candidates(_ trace: FallSensorTrace, config: FallDetector.Config = .youngAdult) -> Int {
        let detector = FallDetector(config: config)
        var count = 0
        detector.onCandidateFall = { _ in count += 1 }
        detector.feed(trace)
        return count
    }

    // MARK: Falls → the check appears

    func testForwardFallReachesTheCheck() {
        XCTAssertEqual(candidates(.forwardFall()), 1)
    }

    func testFallDownStairsReachesTheCheck() {
        XCTAssertEqual(candidates(.stairsFall()), 1, "a longer fall (≈0.9 s) must still count")
    }

    func testPhoneLeftOnTheFloorReachesTheCheck() {
        // The phone can't tell this from a fall — the check is what stops the false alarm
        XCTAssertEqual(candidates(.phoneDroppedAndLeft()), 1)
    }

    // MARK: Everyday movement → nothing

    func testGettingUpAfterAFallCancels() {
        XCTAssertEqual(candidates(.fallThenGetUp()), 0)
    }

    func testDroppedPhonePickedUpCancels() {
        XCTAssertEqual(candidates(.phoneDroppedAndPickedUp()), 0)
    }

    func testSittingDownHardIsNotAFall() {
        XCTAssertEqual(candidates(.sitDownHard()), 0)
        XCTAssertEqual(candidates(.sitDownHard(), config: .elderly), 0)
    }

    func testJumpIsNotAFall() {
        XCTAssertEqual(candidates(.jump()), 0)
    }

    func testRunningIsNotAFall() {
        XCTAssertEqual(candidates(.running()), 0)
    }

    // MARK: A slow slump (no real free fall, soft impact) needs the elderly profile

    func testSlowSlumpIsCaughtOnlyByTheElderlyProfile() {
        XCTAssertEqual(candidates(.slowSlump()), 0, "default profile: impact too soft")
        XCTAssertEqual(candidates(.slowSlump(), config: .elderly), 1)
    }

    // MARK: Re-arming

    func testDetectorCatchesASecondFallAfterResolving() {
        let detector = FallDetector()
        var count = 0
        detector.onCandidateFall = { _ in count += 1 }
        detector.feed(.forwardFall())
        detector.feed(.forwardFall(stillFor: 20))
        XCTAssertEqual(count, 1, "paused while waiting for the answer")
        detector.resolve(dismissed: true)
        var again = FallSensorTrace(start: 5_000)
        _ = again.walk(3)
        _ = again.freeFall(0.45)
        _ = again.impact(peak: 3.5, orientation: FallSensorTrace.lyingOnSide)
        _ = again.still(20, noise: 0.006)
        detector.feed(again)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(detector.metrics.falseAlarms, 1)
    }

    func testMetricsDescribeTheFall() {
        var seen: FallDetector.FallMetrics?
        let detector = FallDetector()
        detector.onCandidateFall = { seen = $0 }
        detector.feed(.forwardFall())
        let m = try! XCTUnwrap(seen)
        XCTAssertEqual(m.freeFallMs, 450, accuracy: 60)
        XCTAssertEqual(m.peakImpactG, 3.5, accuracy: 0.3)
        XCTAssertEqual(m.orientationChangeDeg, 90, accuracy: 10)
        XCTAssertLessThan(m.stillnessVariance, 0.001)
    }

    // MARK: Trace sanity

    func testTracesLookLikeTheDatasets() {
        let fall = FallSensorTrace.forwardFall()
        let mags = fall.samples.map { s in
            sqrt(s.acceleration.x * s.acceleration.x + s.acceleration.y * s.acceleration.y + s.acceleration.z * s.acceleration.z)
        }
        XCTAssertLessThan(mags.min()!, 0.3, "free fall goes near 0 g")
        XCTAssertGreaterThan(mags.max()!, 3.0, "impact spike")
        XCTAssertEqual(fall.samples.count, Int((fall.duration * 50).rounded()) + 1)
    }
}
