import XCTest
import CoreLocation
@testable import ShouDeng

final class TrajectoryProcessorTests: XCTestCase {

    private var processor: TrajectoryProcessor!

    override func setUp() {
        super.setUp()
        processor = TrajectoryProcessor()
    }

    override func tearDown() {
        processor = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makePoint(
        lat: Double, lng: Double,
        accuracy: Double = 10,
        speed: Double? = nil,
        secondsFromStart: TimeInterval = 0
    ) -> TrajectoryProcessor.TrajectoryPoint {
        TrajectoryProcessor.TrajectoryPoint(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            accuracy: accuracy,
            timestamp: Date(timeIntervalSinceReferenceDate: secondsFromStart),
            speed: speed,
            altitude: nil
        )
    }

    // MARK: - Layer 1: Filter

    func testFilterRemovesLowAccuracyPoints() {
        let points = [
            makePoint(lat: 40.0, lng: 116.0, accuracy: 10, secondsFromStart: 0),
            makePoint(lat: 40.001, lng: 116.001, accuracy: 200, secondsFromStart: 60),
            makePoint(lat: 40.002, lng: 116.002, accuracy: 15, secondsFromStart: 120),
        ]

        let filtered = processor.filterLayer(points)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].coordinate.latitude, 40.0, accuracy: 0.0001)
        XCTAssertEqual(filtered[1].coordinate.latitude, 40.002, accuracy: 0.0001)
    }

    func testFilterRemovesOutOfOrderTimestamps() {
        let points = [
            makePoint(lat: 40.0, lng: 116.0, secondsFromStart: 100),
            makePoint(lat: 40.001, lng: 116.001, secondsFromStart: 50),  // Earlier!
            makePoint(lat: 40.002, lng: 116.002, secondsFromStart: 200),
        ]

        let filtered = processor.filterLayer(points)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[1].timestamp.timeIntervalSinceReferenceDate, 200, accuracy: 0.1)
    }

    func testFilterRemovesTeleportation() {
        // Two points 1 second apart but thousands of km away (impossible speed)
        let points = [
            makePoint(lat: 40.0, lng: 116.0, secondsFromStart: 0),
            makePoint(lat: 60.0, lng: 116.0, secondsFromStart: 1),  // ~2200km in 1s
        ]

        let filtered = processor.filterLayer(points)

        XCTAssertEqual(filtered.count, 1)
    }

    func testFilterPassesAllValidPoints() {
        // Walking pace: ~0.001 degrees per 60 seconds
        let points = [
            makePoint(lat: 40.0, lng: 116.0, secondsFromStart: 0),
            makePoint(lat: 40.001, lng: 116.0, secondsFromStart: 60),
            makePoint(lat: 40.002, lng: 116.0, secondsFromStart: 120),
        ]

        let filtered = processor.filterLayer(points)

        XCTAssertEqual(filtered.count, 3)
    }

    func testFilterEmptyReturnsEmpty() {
        let filtered = processor.filterLayer([])
        XCTAssertTrue(filtered.isEmpty)
    }

    // MARK: - Layer 2: Kalman Smooth

    func testKalmanSmoothPreservesCount() {
        let points = [
            makePoint(lat: 40.0, lng: 116.0, accuracy: 10, secondsFromStart: 0),
            makePoint(lat: 40.001, lng: 116.001, accuracy: 10, secondsFromStart: 60),
            makePoint(lat: 40.002, lng: 116.002, accuracy: 10, secondsFromStart: 120),
        ]

        let smoothed = processor.kalmanSmooth(points)

        XCTAssertEqual(smoothed.count, points.count)
    }

    func testKalmanSmoothFirstPointUnchanged() {
        let points = [
            makePoint(lat: 40.0, lng: 116.0, accuracy: 10, secondsFromStart: 0),
            makePoint(lat: 40.001, lng: 116.001, accuracy: 10, secondsFromStart: 60),
        ]

        let smoothed = processor.kalmanSmooth(points)

        XCTAssertEqual(smoothed[0].coordinate.latitude, 40.0, accuracy: 0.0001)
        XCTAssertEqual(smoothed[0].coordinate.longitude, 116.0, accuracy: 0.0001)
    }

    func testKalmanSmoothReducesNoise() {
        // A noisy point (bad accuracy) should be pulled toward the trajectory
        let points = [
            makePoint(lat: 40.0, lng: 116.0, accuracy: 5, secondsFromStart: 0),
            makePoint(lat: 40.01, lng: 116.0, accuracy: 200, secondsFromStart: 60), // Very noisy
            makePoint(lat: 40.002, lng: 116.0, accuracy: 5, secondsFromStart: 120),
        ]

        let smoothed = processor.kalmanSmooth(points)

        // The noisy middle point should be pulled closer to the trajectory
        let rawMiddle = points[1].coordinate.latitude
        let smoothedMiddle = smoothed[1].coordinate.latitude
        let firstLat = points[0].coordinate.latitude

        // Smoothed should be closer to first point than raw noisy point
        XCTAssertLessThan(abs(smoothedMiddle - firstLat), abs(rawMiddle - firstLat))
    }

    func testKalmanSinglePointReturnsSamePoint() {
        let points = [makePoint(lat: 40.0, lng: 116.0, secondsFromStart: 0)]
        let smoothed = processor.kalmanSmooth(points)

        XCTAssertEqual(smoothed.count, 1)
        XCTAssertEqual(smoothed[0].coordinate.latitude, 40.0, accuracy: 0.0001)
    }

    // MARK: - Layer 3: Douglas-Peucker

    func testDouglasPeuckerStraightLineReducesToTwoPoints() {
        // Three collinear points → simplified to 2
        let smoothed = [
            TrajectoryProcessor.SmoothedPoint(
                coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: 116.0),
                timestamp: Date(timeIntervalSinceReferenceDate: 0), speed: nil
            ),
            TrajectoryProcessor.SmoothedPoint(
                coordinate: CLLocationCoordinate2D(latitude: 40.00005, longitude: 116.00005),
                timestamp: Date(timeIntervalSinceReferenceDate: 60), speed: nil
            ),
            TrajectoryProcessor.SmoothedPoint(
                coordinate: CLLocationCoordinate2D(latitude: 40.0001, longitude: 116.0001),
                timestamp: Date(timeIntervalSinceReferenceDate: 120), speed: nil
            ),
        ]

        let simplified = processor.douglasPeucker(smoothed, epsilon: 15)

        XCTAssertEqual(simplified.count, 2)
    }

    func testDouglasPeuckerKeepsSharpTurn() {
        // A sharp detour that is far from the start→end line
        let smoothed = [
            TrajectoryProcessor.SmoothedPoint(
                coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: 116.0),
                timestamp: Date(timeIntervalSinceReferenceDate: 0), speed: nil
            ),
            TrajectoryProcessor.SmoothedPoint(
                coordinate: CLLocationCoordinate2D(latitude: 40.001, longitude: 116.001),
                timestamp: Date(timeIntervalSinceReferenceDate: 60), speed: nil
            ),
            TrajectoryProcessor.SmoothedPoint(
                coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: 116.002),
                timestamp: Date(timeIntervalSinceReferenceDate: 120), speed: nil
            ),
        ]

        let simplified = processor.douglasPeucker(smoothed, epsilon: 15)

        // The middle point is ~100m+ off the line — should be kept
        XCTAssertGreaterThanOrEqual(simplified.count, 3)
    }

    func testDouglasPeuckerTwoPointsReturnsSame() {
        let smoothed = [
            TrajectoryProcessor.SmoothedPoint(
                coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: 116.0),
                timestamp: Date(timeIntervalSinceReferenceDate: 0), speed: nil
            ),
            TrajectoryProcessor.SmoothedPoint(
                coordinate: CLLocationCoordinate2D(latitude: 40.001, longitude: 116.001),
                timestamp: Date(timeIntervalSinceReferenceDate: 60), speed: nil
            ),
        ]

        let simplified = processor.douglasPeucker(smoothed, epsilon: 15)

        XCTAssertEqual(simplified.count, 2)
    }

    // MARK: - Layer 4: Segmentation

    func testSegmentDetectsDwellPoint() {
        // Many points in the same place over 25 minutes → dwell
        let base = Date(timeIntervalSinceReferenceDate: 0)
        var points: [TrajectoryProcessor.SmoothedPoint] = []

        for i in 0..<30 {
            points.append(TrajectoryProcessor.SmoothedPoint(
                coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: 116.0),
                timestamp: base.addingTimeInterval(Double(i) * 60), // 1 per minute, 30 min total
                speed: 0
            ))
        }

        let segments = processor.segment(points)

        let dwellSegments = segments.filter { $0.type == .dwell }
        XCTAssertFalse(dwellSegments.isEmpty, "Should detect at least one dwell segment")
    }

    func testSegmentDetectsMovement() {
        // Points spread over a large distance
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let points = [
            TrajectoryProcessor.SmoothedPoint(
                coordinate: CLLocationCoordinate2D(latitude: 40.0, longitude: 116.0),
                timestamp: base, speed: 10
            ),
            TrajectoryProcessor.SmoothedPoint(
                coordinate: CLLocationCoordinate2D(latitude: 40.01, longitude: 116.01),
                timestamp: base.addingTimeInterval(60), speed: 10
            ),
            TrajectoryProcessor.SmoothedPoint(
                coordinate: CLLocationCoordinate2D(latitude: 40.02, longitude: 116.02),
                timestamp: base.addingTimeInterval(120), speed: 10
            ),
        ]

        let segments = processor.segment(points)

        let moveSegments = segments.filter { $0.type == .movement }
        XCTAssertFalse(moveSegments.isEmpty, "Should detect movement segment")
    }

    func testSegmentEmptyReturnsEmpty() {
        let segments = processor.segment([])
        XCTAssertTrue(segments.isEmpty)
    }

    // MARK: - Transport Mode

    func testTransportModeRawValues() {
        XCTAssertEqual(TrajectoryProcessor.TransportMode.walking.rawValue, "步行")
        XCTAssertEqual(TrajectoryProcessor.TransportMode.cycling.rawValue, "骑行")
        XCTAssertEqual(TrajectoryProcessor.TransportMode.driving.rawValue, "车辆")
        XCTAssertEqual(TrajectoryProcessor.TransportMode.flying.rawValue, "飞行")
        XCTAssertEqual(TrajectoryProcessor.TransportMode.stationary.rawValue, "停留")
    }

    // MARK: - Full Pipeline

    func testFullPipelineReturnsAllLayers() {
        let points = [
            makePoint(lat: 40.0, lng: 116.0, accuracy: 10, secondsFromStart: 0),
            makePoint(lat: 40.001, lng: 116.001, accuracy: 10, secondsFromStart: 60),
            makePoint(lat: 40.002, lng: 116.002, accuracy: 10, secondsFromStart: 120),
        ]

        let result = processor.process(rawPoints: points)

        XCTAssertFalse(result.filtered.isEmpty)
        XCTAssertFalse(result.smoothed.isEmpty)
        XCTAssertFalse(result.simplified.isEmpty)
    }

    // MARK: - Config Defaults

    func testDefaultConfigThresholds() {
        let config = TrajectoryProcessor.Config()
        XCTAssertEqual(config.maxAccuracyMeters, 100, accuracy: 0.01)
        XCTAssertEqual(config.maxSpeedKmh, 200, accuracy: 0.01)
        XCTAssertEqual(config.flyingSpeedKmh, 1200, accuracy: 0.01)
        XCTAssertEqual(config.simplificationEpsilon, 15, accuracy: 0.01)
        XCTAssertEqual(config.dwellRadiusMeters, 200, accuracy: 0.01)
        XCTAssertEqual(config.walkMaxKmh, 5, accuracy: 0.01)
        XCTAssertEqual(config.bikeMaxKmh, 20, accuracy: 0.01)
        XCTAssertEqual(config.carMaxKmh, 120, accuracy: 0.01)
    }
}
