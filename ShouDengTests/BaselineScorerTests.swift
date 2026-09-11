import XCTest
@testable import ShouDeng

final class BaselineScorerTests: XCTestCase {

    private var scorer: BaselineScorer!

    override func setUp() {
        super.setUp()
        scorer = BaselineScorer()
    }

    override func tearDown() {
        scorer = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeLocation(lat: Double = 40.0, lng: Double = 116.0) -> Location {
        Location(
            latitude: lat,
            longitude: lng,
            accuracy: 10,
            altitude: nil,
            speed: nil,
            timestamp: Date(),
            address: nil,
            isInSafeZone: nil,
            safeZoneName: nil
        )
    }

    // MARK: - Config Defaults

    func testDefaultWeightsSumToOne() {
        let config = BaselineScorer.Config()
        let sum = config.weightCheckInOvertime
            + config.weightPhoneInactivity
            + config.weightLocationAnomaly
            + config.weightBatteryAnomaly
            + config.weightRegionalRisk
        XCTAssertEqual(sum, 1.0, accuracy: 0.001)
    }

    func testDefaultThresholds() {
        let config = BaselineScorer.Config()
        XCTAssertEqual(config.yellowThreshold, 0.45, accuracy: 0.01)
        XCTAssertEqual(config.redThreshold, 0.70, accuracy: 0.01)
        XCTAssertLessThan(config.yellowThreshold, config.redThreshold)
    }

    func testDefaultBaselineRequires14Days() {
        let config = BaselineScorer.Config()
        XCTAssertEqual(config.baselineDaysRequired, 14)
    }

    // MARK: - Grid Cell

    func testGridCellCreation() {
        let cell = BaselineScorer.GridCell(latitude: 40.1234, longitude: 116.5678)
        XCTAssertEqual(cell.latBucket, 40123)
        XCTAssertEqual(cell.lngBucket, 116568)
    }

    func testGridCellEquality() {
        let a = BaselineScorer.GridCell(latitude: 40.0001, longitude: 116.0001)
        let b = BaselineScorer.GridCell(latitude: 40.0001, longitude: 116.0001)
        XCTAssertEqual(a, b)
    }

    func testGridCellDifferentLocations() {
        let a = BaselineScorer.GridCell(latitude: 40.0, longitude: 116.0)
        let b = BaselineScorer.GridCell(latitude: 40.002, longitude: 116.0)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Time Slot

    func testTimeSlotMorning() {
        XCTAssertEqual(BaselineScorer.TimeSlot.from(hour: 9), .morning)
        XCTAssertEqual(BaselineScorer.TimeSlot.from(hour: 11), .morning)
    }

    func testTimeSlotAfternoon() {
        XCTAssertEqual(BaselineScorer.TimeSlot.from(hour: 12), .afternoon)
        XCTAssertEqual(BaselineScorer.TimeSlot.from(hour: 16), .afternoon)
    }

    func testTimeSlotEvening() {
        XCTAssertEqual(BaselineScorer.TimeSlot.from(hour: 17), .evening)
        XCTAssertEqual(BaselineScorer.TimeSlot.from(hour: 20), .evening)
    }

    func testTimeSlotEarlyMorning() {
        XCTAssertEqual(BaselineScorer.TimeSlot.from(hour: 5), .earlyMorning)
        XCTAssertEqual(BaselineScorer.TimeSlot.from(hour: 7), .earlyMorning)
    }

    func testTimeSlotNight() {
        XCTAssertEqual(BaselineScorer.TimeSlot.from(hour: 21), .night)
        XCTAssertEqual(BaselineScorer.TimeSlot.from(hour: 23), .night)
    }

    func testTimeSlotLateNight() {
        XCTAssertEqual(BaselineScorer.TimeSlot.from(hour: 1), .lateNight)
        XCTAssertEqual(BaselineScorer.TimeSlot.from(hour: 4), .lateNight)
    }

    // MARK: - Fallback Score (no baseline)

    func testFallbackScoreWithNoBaseline() {
        let score = scorer.computeRiskScore(
            personId: "unknown-person",
            lastCheckIn: Date().addingTimeInterval(-25 * 3600), // 25 hours ago
            lastHeartbeat: Date().addingTimeInterval(-9 * 3600), // 9 hours ago
            currentLocation: makeLocation(),
            batteryLevel: 0.5,
            batteryState: .unplugged,
            regionRiskLevel: 0,
            timeZone: .current
        )

        XCTAssertFalse(score.baselineReady)
        XCTAssertGreaterThan(score.totalScore, 0)
        XCTAssertFalse(score.humanReadableReasons.isEmpty)
    }

    func testFallbackScoreRecentCheckInIsLow() {
        let score = scorer.computeRiskScore(
            personId: "unknown-person",
            lastCheckIn: Date().addingTimeInterval(-60), // 1 minute ago
            lastHeartbeat: Date().addingTimeInterval(-60),
            currentLocation: makeLocation(),
            batteryLevel: 0.9,
            batteryState: .charging,
            regionRiskLevel: 0,
            timeZone: .current
        )

        XCTAssertFalse(score.baselineReady)
        XCTAssertLessThan(score.totalScore, 0.45) // Should not trigger yellow
    }

    func testFallbackScoreNoCheckInEverIsNonZero() {
        let score = scorer.computeRiskScore(
            personId: "unknown-person",
            lastCheckIn: nil,
            lastHeartbeat: nil,
            currentLocation: nil,
            batteryLevel: nil,
            batteryState: .unknown,
            regionRiskLevel: 0,
            timeZone: .current
        )

        XCTAssertGreaterThan(score.totalScore, 0)
        XCTAssertFalse(score.humanReadableReasons.isEmpty)
    }

    // MARK: - Risk Score Levels

    func testRiskScoreLevels() {
        // Verify AlertLevel enum values
        let levels: [AlertLevel] = [.info, .reminder, .warning, .critical]
        XCTAssertEqual(levels.count, 4)
    }

    func testRiskScoreIsYellowProperty() {
        let score = BaselineScorer.RiskScore(
            totalScore: 0.5,
            level: .warning,
            factors: [],
            humanReadableReasons: ["test"],
            computedAt: Date(),
            baselineReady: false
        )
        XCTAssertTrue(score.isYellow)
        XCTAssertFalse(score.isRed)
    }

    func testRiskScoreIsRedProperty() {
        let score = BaselineScorer.RiskScore(
            totalScore: 0.8,
            level: .critical,
            factors: [],
            humanReadableReasons: ["test"],
            computedAt: Date(),
            baselineReady: false
        )
        XCTAssertTrue(score.isRed)
        XCTAssertTrue(score.isYellow) // Red is always also yellow
    }

    // MARK: - Baseline Building

    func testBuildBaselineWithSufficientData() {
        let personId = "person-baseline"
        let now = Date()

        // Generate 14 days of check-ins
        var checkIns: [CheckInEvent] = []
        for day in 0..<14 {
            let timestamp = now.addingTimeInterval(-Double(day) * 86400)
            checkIns.append(CheckInEvent(
                id: "ci-\(day)",
                userId: personId,
                timestamp: timestamp,
                location: makeLocation(),
                note: nil
            ))
        }

        // Generate heartbeats
        var heartbeats: [HeartbeatSignal] = []
        for i in 0..<50 {
            heartbeats.append(HeartbeatSignal(
                userId: personId,
                timestamp: now.addingTimeInterval(-Double(i) * 3600),
                source: .appForeground,
                batteryLevel: 0.7,
                batteryState: .unplugged,
                location: nil
            ))
        }

        // Generate locations
        var locations: [Location] = []
        for i in 0..<30 {
            locations.append(Location(
                latitude: 40.0 + Double(i) * 0.0001,
                longitude: 116.0,
                accuracy: 10,
                altitude: nil,
                speed: nil,
                timestamp: now.addingTimeInterval(-Double(i) * 3600),
                address: nil,
                isInSafeZone: nil,
                safeZoneName: nil
            ))
        }

        let baseline = scorer.buildBaseline(
            personId: personId,
            checkIns: checkIns,
            heartbeats: heartbeats,
            locations: locations,
            timeZone: .current
        )

        XCTAssertEqual(baseline.personId, personId)
        XCTAssertGreaterThan(baseline.dataPoints, 0)
        XCTAssertGreaterThan(baseline.averageCheckInGap, 0)
        XCTAssertFalse(baseline.activeHours.isEmpty)
    }

    // MARK: - Risk Score With Baseline

    func testScoreWithBaselineReturnsAllFiveFactors() {
        let personId = "person-factors"
        let now = Date()

        // Build a minimal baseline
        var checkIns: [CheckInEvent] = []
        for day in 0..<15 {
            checkIns.append(CheckInEvent(
                id: "ci-\(day)",
                userId: personId,
                timestamp: now.addingTimeInterval(-Double(day) * 86400),
                location: makeLocation(),
                note: nil
            ))
        }

        var heartbeats: [HeartbeatSignal] = []
        for i in 0..<30 {
            heartbeats.append(HeartbeatSignal(
                userId: personId,
                timestamp: now.addingTimeInterval(-Double(i) * 3600),
                source: .appForeground,
                batteryLevel: 0.7,
                batteryState: .unplugged,
                location: nil
            ))
        }

        _ = scorer.buildBaseline(
            personId: personId,
            checkIns: checkIns,
            heartbeats: heartbeats,
            locations: [],
            timeZone: .current
        )

        let score = scorer.computeRiskScore(
            personId: personId,
            lastCheckIn: now.addingTimeInterval(-7200),
            lastHeartbeat: now.addingTimeInterval(-3600),
            currentLocation: makeLocation(),
            batteryLevel: 0.5,
            batteryState: .unplugged,
            regionRiskLevel: 0.2,
            timeZone: .current
        )

        XCTAssertTrue(score.baselineReady)
        XCTAssertEqual(score.factors.count, 5)

        let factorNames = Set(score.factors.map { $0.name })
        XCTAssertTrue(factorNames.contains("check_in_overtime"))
        XCTAssertTrue(factorNames.contains("phone_inactivity"))
        XCTAssertTrue(factorNames.contains("location_anomaly"))
        XCTAssertTrue(factorNames.contains("battery_anomaly"))
        XCTAssertTrue(factorNames.contains("regional_risk"))
    }
}
