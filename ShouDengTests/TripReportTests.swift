import XCTest
import CoreLocation
import PDFKit
@testable import ShouDeng

final class TripReportTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// A point `metersNorth` north of a fixed origin, `seconds` after t0
    private func p(_ metersNorth: Double, _ seconds: TimeInterval, speed: Double? = nil,
                   altitude: Double? = nil, accuracy: Double = 5) -> TripPoint {
        TripPoint(latitude: 43.6 + metersNorth / 111_195, longitude: -79.4, accuracy: accuracy,
                  altitude: altitude, speed: speed, timestamp: t0.addingTimeInterval(seconds), activityType: nil)
    }

    // MARK: Stats

    func testDistanceDurationAndMovingTime() {
        // 1 km north in 10 min at walking pace, then 5 min standing still
        var pts = (0...10).map { p(Double($0) * 100, Double($0) * 60) }
        pts += (1...5).map { p(1000, 600 + Double($0) * 60) }
        let s = TripStats.compute(pts)
        XCTAssertEqual(s.distanceMeters, 1000, accuracy: 5)
        XCTAssertEqual(s.durationSeconds, 900)
        XCTAssertEqual(s.movingSeconds, 600)
        XCTAssertEqual(s.averageSpeed, 1000.0 / 600, accuracy: 0.02)
    }

    func testGPSJumpIsIgnored() {
        // A fix 50 km away one second later, then back: not travel, not top speed
        let pts = [p(0, 0), p(10, 10), p(50_000, 11), p(20, 20)]
        let s = TripStats.compute(pts)
        XCTAssertLessThan(s.maxSpeed, 5)
        XCTAssertLessThan(s.distanceMeters, 100)
    }

    func testPhoneSpeedIsPreferred() {
        let s = TripStats.compute([p(0, 0, speed: 3), p(30, 10, speed: 8)])
        XCTAssertEqual(s.maxSpeed, 8, accuracy: 0.001)
    }

    func testClimbIgnoresSmallWobbles() {
        let alts: [Double] = [100, 101, 99, 102, 110, 108, 120, 117, 100]
        let pts = alts.enumerated().map { p(Double($0.offset) * 10, Double($0.offset) * 10, altitude: $0.element) }
        let s = TripStats.compute(pts)
        // 100 → 110 → 120 counted (+20), then 120 → 117 → 100 (−20); ±1–2 m wobble ignored
        XCTAssertEqual(s.elevationGain, 20, accuracy: 0.001)
        XCTAssertEqual(s.elevationLoss, 20, accuracy: 0.001)
        XCTAssertEqual(s.minAltitude, 99)
        XCTAssertEqual(s.maxAltitude, 120)
    }

    func testStopsOfThreeMinutesOrMore() {
        var pts = (0...5).map { p(Double($0) * 100, Double($0) * 60) }       // walking
        pts += (1...4).map { p(510, 300 + Double($0) * 60) }                 // 4 min at one spot
        pts += (1...3).map { p(500 + Double($0) * 200, 540 + Double($0) * 60) }
        let stops = TripStats.stops(pts)
        XCTAssertEqual(stops.count, 1)
        XCTAssertEqual(stops.first?.duration ?? 0, 240, accuracy: 1)
        XCTAssertTrue(TripStats.stops(Array(pts.prefix(6))).isEmpty)
    }

    func testBearing() {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        XCTAssertEqual(TripStats.bearing(from: a, to: .init(latitude: 1, longitude: 0)), 0, accuracy: 0.01)
        XCTAssertEqual(TripStats.bearing(from: a, to: .init(latitude: 0, longitude: 1)), 90, accuracy: 0.01)
        XCTAssertEqual(TripStats.bearing(from: a, to: .init(latitude: 0, longitude: -1)), 270, accuracy: 0.01)
    }

    // MARK: Coloured runs

    func testRunsSplitBySpeedAndShareJoints() {
        // walk (1 m/s), then drive through town (12 m/s ≈ 43 km/h)
        let pts = [p(0, 0), p(10, 10), p(20, 20), p(140, 30), p(260, 40)]
        let runs = TrackRun.runs(pts)
        XCTAssertEqual(runs.map(\.band), [.slow, .fast])
        XCTAssertEqual(runs[0].coordinates.count, 3)
        // The second run starts where the first ends: no gap in the line
        XCTAssertEqual(runs[0].coordinates.last?.latitude, runs[1].coordinates.first?.latitude)
        XCTAssertTrue(TrackRun.runs([p(0, 0)]).isEmpty)
    }

    func testSpeedBands() {
        XCTAssertEqual(TrackSpeedBand.band(for: 1), .slow)          // 3.6 km/h
        XCTAssertEqual(TrackSpeedBand.band(for: 4), .moderate)      // 14.4 km/h
        XCTAssertEqual(TrackSpeedBand.band(for: 12), .fast)         // 43 km/h
        XCTAssertEqual(TrackSpeedBand.band(for: 30), .veryFast)     // 108 km/h
    }

    // MARK: Report

    func testSampleKeepsEndsAndLimit() {
        let pts = (0..<1000).map { p(Double($0), Double($0)) }
        let s = TripReportPDF.sample(pts, max: 300)
        XCTAssertEqual(s.count, 300)
        XCTAssertEqual(s.first?.timestamp, pts.first?.timestamp)
        XCTAssertEqual(s.last?.timestamp, pts.last?.timestamp)
        XCTAssertEqual(TripReportPDF.sample(Array(pts.prefix(10)), max: 300).count, 10)
    }

    func testPDFHasSummaryChartsAndLog() async throws {
        let pts = (0..<400).map { i in
            p(Double(i) * 8, Double(i) * 5, speed: 1.6, altitude: 80 + Double(i % 50))
        }
        let input = TripReportInput(personName: "Xiulan Chen", points: pts, inProgress: true, generatedAt: t0)
        let data = await TripReportPDF.render(input, includeMap: false)
        let doc = try XCTUnwrap(PDFDocument(data: data))
        // Summary + map, charts + stops, then the log (300 sampled rows over several pages)
        XCTAssertGreaterThanOrEqual(doc.pageCount, 4)
        let first = doc.page(at: 0)?.string ?? ""
        XCTAssertTrue(first.contains("Xiulan Chen"))
        XCTAssertTrue(first.contains("400"), "point count in the summary")
        let all = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined()
        XCTAssertTrue(all.contains("43.60"), "the GPS log lists coordinates")
    }

    func testThinningKeepsRecentDetail() {
        let pts = (0..<100).map { p(Double($0), Double($0)) }
        let thin = TripRecordingService.thinned(pts)
        XCTAssertEqual(thin.count, 75)
        XCTAssertEqual(thin.last?.timestamp, pts.last?.timestamp)
        XCTAssertEqual(Array(thin.suffix(50)).map(\.timestamp), Array(pts.suffix(50)).map(\.timestamp))
    }

    @MainActor
    func testLocalRecordingKeepsTheFinishedTrip() async throws {
        let rec = TripRecordingService()
        rec.startLocalRecording()
        XCTAssertTrue(rec.isRecording)
        // The phone's cached position from before the trip is not part of it
        rec.addPoint(CLLocation(coordinate: .init(latitude: 40, longitude: -70), altitude: 0,
                                horizontalAccuracy: 5, verticalAccuracy: -1, course: 0, speed: 0,
                                timestamp: Date().addingTimeInterval(-600)))
        XCTAssertTrue(rec.livePoints.isEmpty)
        XCTAssertTrue(rec.isLocalOnly)
        for i in 0..<5 {
            rec.addPoint(CLLocation(coordinate: .init(latitude: 43.6 + Double(i) * 0.0005, longitude: -79.4),
                                    altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                                    course: 0, speed: 2, timestamp: Date().addingTimeInterval(Double(i) * 30)))
        }
        XCTAssertEqual(rec.livePoints.count, 5)
        XCTAssertEqual(rec.currentSpeed, 2)
        let end = try await rec.stopRecording()
        XCTAssertEqual(end?.pointCount, 5)
        XCTAssertFalse(rec.isRecording)
        XCTAssertTrue(rec.livePoints.isEmpty)
        XCTAssertEqual(rec.lastFinishedTrip?.points.count, 5)
    }
}
