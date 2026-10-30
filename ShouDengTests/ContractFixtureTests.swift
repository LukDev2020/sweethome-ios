import XCTest
@testable import ShouDeng

/// Decodes JSON produced by the REAL backend routes (written by the backend jest
/// contract tests into ShouDengTests/ContractFixtures) with the app's own models
/// and API decoder. If the server shape drifts, one of the two suites fails.
final class ContractFixtureTests: XCTestCase {

    private let decoder = APIClient(config: .init(baseURL: "https://contract.invalid"), offlineQueue: OfflineQueue()).decoder

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ContractFixtures")
            .appendingPathComponent(name)
        return try Data(contentsOf: url)
    }

    func testGuardianProtectedPersonsFromBigQueryFallback() throws {
        let list = try decoder.decode(LossyArray<ProtectedPersonStatusResponse>.self,
                                      from: fixture("guardian_protected_persons.json"))
        XCTAssertEqual(list.droppedCount, 0)
        XCTAssertEqual(list.elements.count, 2)
        let mom = try XCTUnwrap(list.elements.first { $0.personId == "mom" })
        XCTAssertNotNil(mom.locationTimestamp)
        XCTAssertNotNil(mom.lastPhoneActivity)
        XCTAssertNotNil(mom.lastCheckIn)
        XCTAssertEqual(mom.protectionLayers, 2)
        XCTAssertEqual(mom.status, .normal)
        XCTAssertEqual(mom.cityName, "Chengdu")
        // Strict decode must also work (no per-field fallback needed)
        XCTAssertNoThrow(try decoder.decode([ProtectedPersonStatusResponse].self,
                                            from: fixture("guardian_protected_persons.json")))
    }

    func testGuardianProtectedPersonsRealtime() throws {
        let list = try decoder.decode([ProtectedPersonStatusResponse].self,
                                      from: fixture("guardian_protected_persons_realtime.json"))
        let mom = try XCTUnwrap(list.first { $0.personId == "mom" })
        XCTAssertEqual(mom.batteryLevel, 0.41)
        XCTAssertEqual(mom.batteryState, .charging)
    }

    func testTimelineDecodesEveryBackendType() throws {
        let response = try decoder.decode(TimelineResponse.self, from: fixture("timeline.json"))
        XCTAssertEqual(response.hasMore, false)
        XCTAssertEqual(response.entries.count, 9)
        XCTAssertFalse(response.entries.contains { $0.type == .other },
                       "Every type the backend writes should have a dedicated case")
        XCTAssertTrue(response.entries.contains { $0.type == .bleSeparation })
        XCTAssertTrue(response.entries.contains { $0.type == .silentAlarmEscalated })
        XCTAssertTrue(response.entries.contains { $0.type == .voiceNote })
    }

    // MARK: - Tolerance

    func testOneBadPersonDoesNotBlankDashboard() throws {
        let json = """
        [
          {"personId":"a","displayName":"A","status":"normal","batteryState":"full","protectionLayers":1,
           "lastPhoneActivity":"[object Object]","locationTimestamp":{"value":"2026-10-30T11:55:00.000Z"}},
          {"displayName":"missing id"},
          {"personId":"b","displayName":"B","status":"somethingNew","batteryState":"weird","protectionLayers":2}
        ]
        """.data(using: .utf8)!
        let list = try decoder.decode(LossyArray<ProtectedPersonStatusResponse>.self, from: json)
        XCTAssertEqual(list.elements.map(\.personId), ["a", "b"])
        XCTAssertEqual(list.droppedCount, 1)
        XCTAssertNil(list.elements[0].lastPhoneActivity)
        XCTAssertNil(list.elements[0].locationTimestamp)
        XCTAssertEqual(list.elements[1].status, .unreachable)
        XCTAssertEqual(list.elements[1].batteryState, .unknown)
    }

    func testTimelineWithoutHasMoreAndUnknownType() throws {
        let json = """
        {"entries":[
          {"id":"1","type":"brandNewType","description":"x","detail":null,"timestamp":"2026-10-30T12:00:00.000Z"},
          {"id":"2","type":"checkIn","description":"y","detail":null,"timestamp":null}
        ]}
        """.data(using: .utf8)!
        let response = try decoder.decode(TimelineResponse.self, from: json)
        XCTAssertNil(response.hasMore)
        XCTAssertEqual(response.entries.map(\.id), ["1"])
        XCTAssertEqual(response.entries.first?.type, .other)
    }
}
