import XCTest
import CoreLocation
@testable import ShouDeng

final class ReactiveLocationServiceTests: XCTestCase {

    // MARK: - Init

    func testInitialState() {
        let service = ReactiveLocationService()
        XCTAssertNil(service.currentLocation)
        XCTAssertEqual(service.currentHeading, 0)
        XCTAssertEqual(service.currentAccuracy, 0)
        XCTAssertTrue(service.memberLocations.isEmpty)
        XCTAssertEqual(service.followMode, .followMe)
        XCTAssertNil(service.lastUpdateTime)
        XCTAssertNil(service.lastUpdateMinutes)
    }

    // MARK: - Bind to AdaptiveLocationManager

    func testBindSeedsFromBestAvailable() {
        let service = ReactiveLocationService()
        let manager = AdaptiveLocationManager()
        // Before binding, no location
        XCTAssertNil(service.currentLocation)

        // Bind — should seed from bestAvailableLocation (nil for fresh manager)
        service.bind(to: manager)
        XCTAssertNil(service.currentLocation) // Manager has no location yet
    }

    func testBindPreservesExistingCallback() {
        let service = ReactiveLocationService()
        let manager = AdaptiveLocationManager()

        var callbackCalled = false
        manager.onLocationReport = { _ in
            callbackCalled = true
        }

        service.bind(to: manager)

        // The onLocationReport should still call the original callback
        let testLocation = Location(
            latitude: 39.9, longitude: 116.4,
            accuracy: 10, altitude: 50, speed: 1.5,
            timestamp: Date(), address: nil,
            isInSafeZone: false, safeZoneName: nil
        )
        manager.onLocationReport?(testLocation)

        XCTAssertTrue(callbackCalled, "Original callback should be preserved")
    }

    func testLocationReportUpdatesPublished() {
        let service = ReactiveLocationService()
        let manager = AdaptiveLocationManager()
        service.bind(to: manager)

        let testLocation = Location(
            latitude: 40.0, longitude: 116.5,
            accuracy: 15, altitude: nil, speed: nil,
            timestamp: Date(), address: nil,
            isInSafeZone: false, safeZoneName: nil
        )

        // Trigger the callback
        manager.onLocationReport?(testLocation)

        // Wait for main thread dispatch
        let exp = expectation(description: "location updated")
        DispatchQueue.main.async {
            XCTAssertNotNil(service.currentLocation)
            XCTAssertEqual(service.currentLocation!.latitude, 40.0, accuracy: 0.001)
            XCTAssertEqual(service.currentLocation!.longitude, 116.5, accuracy: 0.001)
            XCTAssertEqual(service.currentAccuracy, 15)
            XCTAssertNotNil(service.lastUpdateTime)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }

    // MARK: - Member Location Management

    func testUpdateMember() {
        let service = ReactiveLocationService()
        let coord = CLLocationCoordinate2D(latitude: 31.2, longitude: 121.4)
        let now = Date()

        service.updateMember(
            userId: "guardian1",
            coordinate: coord,
            accuracy: 20,
            timestamp: now,
            battery: 0.85,
            isOnline: true
        )

        XCTAssertEqual(service.memberLocations.count, 1)
        let member = service.memberLocations["guardian1"]
        XCTAssertNotNil(member)
        XCTAssertEqual(member!.coordinate.latitude, 31.2, accuracy: 0.001)
        XCTAssertEqual(member?.battery, 0.85)
        XCTAssertTrue(member?.isOnline ?? false)
    }

    func testUpdateMemberOverwrites() {
        let service = ReactiveLocationService()

        service.updateMember(
            userId: "person1",
            coordinate: CLLocationCoordinate2D(latitude: 30.0, longitude: 120.0)
        )
        service.updateMember(
            userId: "person1",
            coordinate: CLLocationCoordinate2D(latitude: 31.0, longitude: 121.0)
        )

        XCTAssertEqual(service.memberLocations.count, 1)
        XCTAssertEqual(service.memberLocations["person1"]!.coordinate.latitude, 31.0, accuracy: 0.001)
    }

    func testRemoveMember() {
        let service = ReactiveLocationService()
        service.updateMember(
            userId: "person1",
            coordinate: CLLocationCoordinate2D(latitude: 30.0, longitude: 120.0)
        )
        XCTAssertEqual(service.memberLocations.count, 1)

        service.removeMember(userId: "person1")
        XCTAssertTrue(service.memberLocations.isEmpty)
    }

    func testClearMembers() {
        let service = ReactiveLocationService()
        service.updateMember(userId: "a", coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1))
        service.updateMember(userId: "b", coordinate: CLLocationCoordinate2D(latitude: 2, longitude: 2))
        XCTAssertEqual(service.memberLocations.count, 2)

        service.clearMembers()
        XCTAssertTrue(service.memberLocations.isEmpty)
    }

    // MARK: - Follow Mode

    func testFollowModeDefaultsToFollowMe() {
        let service = ReactiveLocationService()
        XCTAssertEqual(service.followMode, .followMe)
    }

    func testFollowModeEquatable() {
        XCTAssertEqual(ReactiveLocationService.FollowMode.free, .free)
        XCTAssertEqual(ReactiveLocationService.FollowMode.followMe, .followMe)
        XCTAssertEqual(
            ReactiveLocationService.FollowMode.followPerson(id: "abc"),
            .followPerson(id: "abc")
        )
        XCTAssertNotEqual(
            ReactiveLocationService.FollowMode.followPerson(id: "abc"),
            .followPerson(id: "def")
        )
    }

    // MARK: - Last Update Minutes

    func testLastUpdateMinutesNilWhenNoUpdate() {
        let service = ReactiveLocationService()
        XCTAssertNil(service.lastUpdateMinutes)
    }

    func testLastUpdateMinutesReturnsZeroForRecent() {
        let service = ReactiveLocationService()
        service.lastUpdateTime = Date()
        XCTAssertEqual(service.lastUpdateMinutes, 0)
    }

    func testLastUpdateMinutesReturnsCorrectValue() {
        let service = ReactiveLocationService()
        service.lastUpdateTime = Date().addingTimeInterval(-300) // 5 minutes ago
        XCTAssertEqual(service.lastUpdateMinutes, 5)
    }

    // MARK: - MemberLocation Equatable

    func testMemberLocationEquatable() {
        let a = ReactiveLocationService.MemberLocation(
            userId: "u1",
            coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            accuracy: 10,
            timestamp: Date(timeIntervalSince1970: 1000),
            battery: 0.5,
            isOnline: true
        )
        let b = ReactiveLocationService.MemberLocation(
            userId: "u1",
            coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            accuracy: 10,
            timestamp: Date(timeIntervalSince1970: 1000),
            battery: 0.8,
            isOnline: false
        )
        XCTAssertEqual(a, b, "Should be equal when userId, coordinate, and timestamp match")
    }
}
