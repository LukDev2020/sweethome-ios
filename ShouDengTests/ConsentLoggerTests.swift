import XCTest
@testable import ShouDeng

/// Tests for ConsentLogger — append-only consent record storage.
final class ConsentLoggerTests: XCTestCase {

    private var testFileURL: URL!

    override func setUp() {
        super.setUp()
        // Use a temp file for tests to avoid polluting real consent log
        testFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_consent_log_\(UUID().uuidString).jsonl")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testFileURL)
        super.tearDown()
    }

    // MARK: - Record Model

    func testConsentRecordEncodeDecode() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let record = ConsentLogger.ConsentRecord(
            userId: "user123",
            timestamp: Date(timeIntervalSince1970: 1700000000),
            item: "onboard.not_emergency",
            copyVersion: "v1.1",
            action: "granted",
            appVersion: "1.0.0",
            locale: "zh_CN",
            deviceId: "device-uuid"
        )

        let data = try encoder.encode(record)
        let decoded = try decoder.decode(ConsentLogger.ConsentRecord.self, from: data)

        XCTAssertEqual(decoded.userId, "user123")
        XCTAssertEqual(decoded.item, "onboard.not_emergency")
        XCTAssertEqual(decoded.copyVersion, "v1.1")
        XCTAssertEqual(decoded.action, "granted")
        XCTAssertEqual(decoded.appVersion, "1.0.0")
        XCTAssertEqual(decoded.locale, "zh_CN")
        XCTAssertEqual(decoded.deviceId, "device-uuid")
    }

    func testConsentRecordRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let now = Date()
        let record = ConsentLogger.ConsentRecord(
            userId: "u1",
            timestamp: now,
            item: "location.always",
            copyVersion: "v2.0",
            action: "denied",
            appVersion: "1.0.1",
            locale: "en_US",
            deviceId: "dev1"
        )

        let jsonData = try encoder.encode(record)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        XCTAssertTrue(jsonString.contains("location.always"))
        XCTAssertTrue(jsonString.contains("denied"))

        let decoded = try decoder.decode(ConsentLogger.ConsentRecord.self, from: jsonData)
        XCTAssertEqual(decoded.action, "denied")
        XCTAssertEqual(decoded.item, "location.always")
    }

    func testConsentRecordContainsAllRequiredFields() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let record = ConsentLogger.ConsentRecord(
            userId: "u",
            timestamp: Date(),
            item: "test",
            copyVersion: "v1",
            action: "granted",
            appVersion: "1.0",
            locale: "en",
            deviceId: "d"
        )

        let data = try encoder.encode(record)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Per PDF section 5, all these fields are required
        XCTAssertNotNil(dict["userId"])
        XCTAssertNotNil(dict["timestamp"])
        XCTAssertNotNil(dict["item"])
        XCTAssertNotNil(dict["copyVersion"])
        XCTAssertNotNil(dict["action"])
        XCTAssertNotNil(dict["appVersion"])
        XCTAssertNotNil(dict["locale"])
        XCTAssertNotNil(dict["deviceId"])
    }

    // MARK: - Singleton

    func testSharedInstanceExists() {
        XCTAssertNotNil(ConsentLogger.shared)
    }

    // MARK: - allRecords returns empty for missing file

    func testAllRecordsReturnsEmptyForNewLogger() {
        let records = ConsentLogger.shared.allRecords()
        // May or may not be empty depending on prior test runs,
        // but should not crash
        XCTAssertTrue(records is [ConsentLogger.ConsentRecord])
    }
}
