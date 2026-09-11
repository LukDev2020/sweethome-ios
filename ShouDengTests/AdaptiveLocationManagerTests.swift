import XCTest
import CoreLocation
@testable import ShouDeng

final class AdaptiveLocationManagerTests: XCTestCase {

    private var manager: AdaptiveLocationManager!

    override func setUp() {
        super.setUp()
        manager = AdaptiveLocationManager()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    // MARK: - Location Mode Properties

    func testSOSModeHasBestAccuracy() {
        let mode = AdaptiveLocationManager.LocationMode.sos
        XCTAssertEqual(mode.desiredAccuracy, kCLLocationAccuracyBest)
    }

    func testSOSModeReportsEvery5Seconds() {
        let mode = AdaptiveLocationManager.LocationMode.sos
        XCTAssertEqual(mode.reportIntervalSec, 5)
    }

    func testSafeModeReportsOnlyOnSignificantChange() {
        let mode = AdaptiveLocationManager.LocationMode.safe
        XCTAssertEqual(mode.reportIntervalSec, .infinity)
    }

    func testMovingModeReportsEvery60Seconds() {
        let mode = AdaptiveLocationManager.LocationMode.moving
        XCTAssertEqual(mode.reportIntervalSec, 60)
    }

    func testUnknownModeReportsEvery10Minutes() {
        let mode = AdaptiveLocationManager.LocationMode.unknown
        XCTAssertEqual(mode.reportIntervalSec, 600)
    }

    func testLowBatteryModeDoubleUnknownInterval() {
        let unknown = AdaptiveLocationManager.LocationMode.unknown
        let lowBattery = AdaptiveLocationManager.LocationMode.lowBattery
        XCTAssertEqual(lowBattery.reportIntervalSec, unknown.reportIntervalSec * 2)
    }

    func testLowBatteryModeHasLargerDistanceFilter() {
        let moving = AdaptiveLocationManager.LocationMode.moving
        let lowBattery = AdaptiveLocationManager.LocationMode.lowBattery
        XCTAssertGreaterThan(lowBattery.distanceFilter, moving.distanceFilter)
    }

    // MARK: - Initial State

    func testInitialModeIsSafe() {
        XCTAssertEqual(manager.currentMode, .safe)
    }

    // MARK: - Mode Switching

    func testEnterSOSMode() {
        manager.enterSOSMode()
        XCTAssertEqual(manager.currentMode, .sos)
    }

    func testExitSOSModeWithoutLocationGoesToUnknown() {
        manager.enterSOSMode()
        manager.exitSOSMode()
        XCTAssertEqual(manager.currentMode, .unknown)
    }

    func testModeChangeCallback() {
        var oldModes: [AdaptiveLocationManager.LocationMode] = []
        var newModes: [AdaptiveLocationManager.LocationMode] = []

        manager.onModeChange = { old, new in
            oldModes.append(old)
            newModes.append(new)
        }

        manager.enterSOSMode()

        XCTAssertEqual(oldModes, [.safe])
        XCTAssertEqual(newModes, [.sos])
    }

    func testSwitchToSameModeIsNoOp() {
        var callCount = 0
        manager.onModeChange = { _, _ in callCount += 1 }

        manager.switchMode(.safe) // Already in safe mode
        XCTAssertEqual(callCount, 0)
    }

    // MARK: - Configuration Defaults

    func testDefaultConfigValues() {
        let config = AdaptiveLocationManager.Config()
        XCTAssertEqual(config.movingSpeedThreshold, 1.5, accuracy: 0.01)
        XCTAssertEqual(config.stationarySpeedThreshold, 0.5, accuracy: 0.01)
        XCTAssertEqual(config.deduplicationDistanceMeters, 50, accuracy: 0.01)
        XCTAssertEqual(config.deduplicationTimeSec, 120, accuracy: 0.01)
        XCTAssertEqual(config.maxGeofenceRegions, 19)
        XCTAssertEqual(config.dwellPointRadiusMeters, 200, accuracy: 0.01)
        XCTAssertEqual(config.dwellPointMinDurationSec, 1200, accuracy: 0.01)
        XCTAssertEqual(config.safeZoneHysteresisMeters, 50, accuracy: 0.01)
        XCTAssertEqual(config.lowBatteryThreshold, 0.15, accuracy: 0.01)
    }

    // MARK: - Dwell Classification

    func testDwellClassificationRawValues() {
        XCTAssertEqual(AdaptiveLocationManager.DwellClassification.home.rawValue, "住所")
        XCTAssertEqual(AdaptiveLocationManager.DwellClassification.workSchool.rawValue, "学校/工作地")
        XCTAssertEqual(AdaptiveLocationManager.DwellClassification.frequent.rawValue, "常去地点")
        XCTAssertEqual(AdaptiveLocationManager.DwellClassification.unfamiliar.rawValue, "陌生地点")
    }

    // MARK: - Cluster Dwell Points (empty history)

    func testClusterDwellPointsEmptyReturnsEmpty() {
        let result = manager.clusterDwellPoints()
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - All Modes Exist

    func testAllLocationModesExist() {
        let modes: [AdaptiveLocationManager.LocationMode] = [
            .safe, .unknown, .moving, .sos, .lowBattery,
        ]
        XCTAssertEqual(modes.count, 5)
    }
}
