import XCTest
@testable import ShouDeng

final class ModelTests: XCTestCase {

    // MARK: - SOSEvent

    func testSOSEventIsActiveWhenUnresolved() {
        let event = SOSEvent(
            id: "sos-1",
            protectedPersonId: "p-1",
            triggeredAt: Date(),
            triggerMethod: .longPress,
            location: nil,
            batteryLevel: 0.5,
            escalationState: .initiated,
            resolvedAt: nil,
            resolvedBy: nil,
            resolution: nil
        )
        XCTAssertTrue(event.isActive)
    }

    func testSOSEventIsNotActiveWhenResolved() {
        let event = SOSEvent(
            id: "sos-1",
            protectedPersonId: "p-1",
            triggeredAt: Date().addingTimeInterval(-300),
            triggerMethod: .fallDetection,
            location: nil,
            batteryLevel: 0.5,
            escalationState: .resolved,
            resolvedAt: Date(),
            resolvedBy: "g-1",
            resolution: .guardianConfirmedSafe
        )
        XCTAssertFalse(event.isActive)
    }

    func testSOSEventElapsedSeconds() {
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        let event = SOSEvent(
            id: "sos-1",
            protectedPersonId: "p-1",
            triggeredAt: fiveMinutesAgo,
            triggerMethod: .longPress,
            location: nil,
            batteryLevel: nil,
            escalationState: .initiated,
            resolvedAt: nil,
            resolvedBy: nil,
            resolution: nil
        )
        XCTAssertEqual(event.elapsedSeconds, 300, accuracy: 2)
    }

    func testSOSEventElapsedSecondsWhenResolved() {
        let start = Date().addingTimeInterval(-600)
        let end = Date().addingTimeInterval(-300)
        let event = SOSEvent(
            id: "sos-1",
            protectedPersonId: "p-1",
            triggeredAt: start,
            triggerMethod: .longPress,
            location: nil,
            batteryLevel: nil,
            escalationState: .resolved,
            resolvedAt: end,
            resolvedBy: "g-1",
            resolution: .protectedCancelled
        )
        XCTAssertEqual(event.elapsedSeconds, 300, accuracy: 2)
    }

    // MARK: - SOSTriggerMethod

    func testAllTriggerMethodsExist() {
        let methods: [SOSTriggerMethod] = [
            .longPress, .watchQuickAction, .bluetoothButton,
            .duressPassword, .fallDetection, .voiceWakeWord,
        ]
        XCTAssertEqual(methods.count, 6)
    }

    // MARK: - SOSResolution

    func testAllResolutionsExist() {
        let resolutions: [SOSResolution] = [
            .guardianConfirmedSafe, .protectedCancelled,
            .responderHandled, .falseAlarm, .timeout,
        ]
        XCTAssertEqual(resolutions.count, 5)
    }

    // MARK: - EscalationState

    func testAllEscalationStatesExist() {
        let states: [EscalationState] = [
            .initiated, .hop1_notified, .hop1_acknowledged,
            .hop2_allNotified, .hop3_voiceCalling, .hop3_exhausted,
            .frozen, .resolved,
        ]
        XCTAssertEqual(states.count, 8)
    }

    // MARK: - ProtectedPerson

    func testProtectedPersonIsOverdueWhenNoCheckIn() {
        let person = ProtectedPerson(
            id: "p-1",
            user: makeUser(),
            guardians: [],
            protectionLayers: 1,
            lastCheckIn: nil,
            lastKnownLocation: nil,
            batteryLevel: 0.5,
            batteryState: .unplugged,
            lastPhoneActivity: nil,
            status: .normal
        )
        XCTAssertTrue(person.isOverdue)
    }

    func testProtectedPersonIsNotOverdueWithRecentCheckIn() {
        let person = ProtectedPerson(
            id: "p-1",
            user: makeUser(),
            guardians: [],
            protectionLayers: 1,
            lastCheckIn: Date(), // Just now
            lastKnownLocation: nil,
            batteryLevel: 0.9,
            batteryState: .charging,
            lastPhoneActivity: Date(),
            status: .normal
        )
        XCTAssertFalse(person.isOverdue)
    }

    func testProtectedPersonIsOverdueAfterThreshold() {
        let person = ProtectedPerson(
            id: "p-1",
            user: makeUser(),
            guardians: [],
            protectionLayers: 1,
            lastCheckIn: Date().addingTimeInterval(-5 * 3600), // 5 hours ago (threshold is 4)
            lastKnownLocation: nil,
            batteryLevel: 0.3,
            batteryState: .unplugged,
            lastPhoneActivity: nil,
            status: .normal
        )
        XCTAssertTrue(person.isOverdue)
    }

    func testProtectedPersonOverdueThresholdIs4Hours() {
        let person = ProtectedPerson(
            id: "p-1",
            user: makeUser(),
            guardians: [],
            protectionLayers: 1,
            lastCheckIn: Date(),
            lastKnownLocation: nil,
            batteryLevel: nil,
            batteryState: .unknown,
            lastPhoneActivity: nil,
            status: .normal
        )
        XCTAssertEqual(person.overdueThresholdSeconds, 4 * 3600)
    }

    // MARK: - CheckInEvent

    func testCheckInEventCreate() {
        let checkIn = CheckInEvent.create(userId: "u-1", location: nil)
        XCTAssertEqual(checkIn.userId, "u-1")
        XCTAssertFalse(checkIn.id.isEmpty)
        XCTAssertNil(checkIn.location)
        XCTAssertNil(checkIn.note)
    }

    func testCheckInEventCreateHasUniqueIds() {
        let a = CheckInEvent.create(userId: "u-1", location: nil)
        let b = CheckInEvent.create(userId: "u-1", location: nil)
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - Location

    func testLocationCodableRoundTrip() {
        let location = Location(
            latitude: 40.7128,
            longitude: -74.0060,
            accuracy: 10,
            altitude: 15.5,
            speed: 1.2,
            timestamp: Date(timeIntervalSinceReferenceDate: 1000),
            address: "New York",
            isInSafeZone: true,
            safeZoneName: "Home"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try! encoder.encode(location)
        let decoded = try! decoder.decode(Location.self, from: data)

        XCTAssertEqual(decoded.latitude, 40.7128, accuracy: 0.0001)
        XCTAssertEqual(decoded.longitude, -74.0060, accuracy: 0.0001)
        XCTAssertEqual(decoded.accuracy, 10, accuracy: 0.01)
        XCTAssertEqual(decoded.altitude, 15.5)
        XCTAssertEqual(decoded.speed, 1.2)
        XCTAssertEqual(decoded.address, "New York")
        XCTAssertEqual(decoded.isInSafeZone, true)
        XCTAssertEqual(decoded.safeZoneName, "Home")
    }

    // MARK: - SafeZone

    func testSafeZoneCoordinate() {
        let zone = SafeZone(
            id: "sz-1",
            name: "Home",
            latitude: 40.0,
            longitude: 116.0,
            radius: 200,
            isAutoSuggested: false,
            visitFrequency: 30,
            typicalHours: 8...17
        )

        let (lat, lng) = zone.coordinate
        XCTAssertEqual(lat, 40.0)
        XCTAssertEqual(lng, 116.0)
    }

    // MARK: - GuardianPermissions

    func testDefaultPermissions() {
        let perms = GuardianPermissions.defaultPermissions
        XCTAssertTrue(perms.canSeeLocation)
        XCTAssertTrue(perms.canSeeBattery)
        XCTAssertFalse(perms.canSeeHealth)
        XCTAssertFalse(perms.canSeePhoneActivity)
        XCTAssertTrue(perms.canHearEmergencyAudio)
    }

    // MARK: - SafetyStatus

    func testAllSafetyStatusesExist() {
        let statuses: [SafetyStatus] = [
            .normal, .pendingCheckIn, .overdue, .alert, .unreachable,
        ]
        XCTAssertEqual(statuses.count, 5)
    }

    // MARK: - BatteryState

    func testAllBatteryStatesExist() {
        let states: [BatteryState] = [
            .charging, .full, .unplugged, .unknown,
        ]
        XCTAssertEqual(states.count, 4)
    }

    // MARK: - HeartbeatSource

    func testAllHeartbeatSourcesExist() {
        let sources: [HeartbeatSource] = [
            .appForeground, .significantLocation, .silentPush,
            .pushReceipt, .regionEvent, .watchSync,
        ]
        XCTAssertEqual(sources.count, 6)
    }

    // MARK: - TimelineEntryType

    func testAllTimelineEntryTypesExist() {
        let types: [TimelineEntryType] = [
            .checkIn, .sosTriggered, .sosResolved, .enteredSafeZone,
            .leftSafeZone, .missedCheckIn, .guardianAlert,
            .batteryLow, .phoneInactive, .fallDetected, .locationUpdate,
        ]
        XCTAssertEqual(types.count, 11)
    }

    // MARK: - API Request/Response Encoding

    func testHeartbeatRequestEncoding() {
        let request = HeartbeatRequest(
            userId: "u-1",
            timestamp: Date(timeIntervalSinceReferenceDate: 1000),
            source: .appForeground,
            batteryLevel: 0.85,
            batteryState: .charging,
            latitude: 40.0,
            longitude: 116.0,
            accuracy: 10
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        XCTAssertNoThrow(try encoder.encode(request))
    }

    func testLocationReportRequestEncoding() {
        let request = LocationReportRequest(
            userId: "u-1",
            latitude: 40.0,
            longitude: 116.0,
            accuracy: 10,
            altitude: 50,
            speed: 1.5,
            timestamp: Date(),
            isInSafeZone: true,
            safeZoneName: "Home"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        XCTAssertNoThrow(try encoder.encode(request))
    }

    func testSOSTriggerRequestEncoding() {
        let request = SOSTriggerRequest(
            protectedPersonId: "p-1",
            triggerMethod: .longPress,
            latitude: 40.0,
            longitude: 116.0,
            batteryLevel: 0.5
        )

        XCTAssertNoThrow(try JSONEncoder().encode(request))
    }

    func testSOSTriggerResponseDecoding() {
        let json = """
        {"sosEventId":"sos-1","escalationState":"initiated"}
        """.data(using: .utf8)!

        let response = try! JSONDecoder().decode(SOSTriggerResponse.self, from: json)
        XCTAssertEqual(response.sosEventId, "sos-1")
        XCTAssertEqual(response.escalationState, .initiated)
    }

    func testCheckInRequestEncoding() {
        let request = CheckInRequest(
            userId: "u-1",
            latitude: 40.0,
            longitude: 116.0,
            note: "At school"
        )

        XCTAssertNoThrow(try JSONEncoder().encode(request))
    }

    func testCheckInResponseDecoding() {
        let json = """
        {"checkInId":"ci-1","timestamp":"2026-01-01T00:00:00Z"}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try! decoder.decode(CheckInResponse.self, from: json)
        XCTAssertEqual(response.checkInId, "ci-1")
    }

    func testDeviceTokenRequestEncoding() {
        let request = DeviceTokenRequest(
            token: "abc123",
            platform: "ios",
            environment: "production"
        )

        let data = try! JSONEncoder().encode(request)
        let dict = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(dict["token"] as? String, "abc123")
        XCTAssertEqual(dict["platform"] as? String, "ios")
        XCTAssertEqual(dict["environment"] as? String, "production")
    }

    // MARK: - Helpers

    private func makeUser() -> User {
        User(
            id: "u-1",
            displayName: "Test",
            role: .protected_,
            avatarInitial: "T",
            timeZone: .current,
            countryCode: "CN",
            cityName: "Beijing",
            createdAt: Date()
        )
    }
}
