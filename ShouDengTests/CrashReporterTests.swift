import XCTest
@testable import ShouDeng

final class CrashReporterTests: XCTestCase {

    // MARK: - Crash Report Model

    func testCrashReportEncoding() throws {
        let report = CrashReport(
            type: "exception",
            name: "NSInvalidArgumentException",
            reason: "Test crash",
            callStack: ["frame1", "frame2", "frame3"],
            timestamp: Date(timeIntervalSince1970: 1725580800),
            appVersion: "1.0.0",
            buildNumber: "1",
            osVersion: "iOS 17.0",
            deviceModel: "iPhone15,2"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? String, "exception")
        XCTAssertEqual(json?["name"] as? String, "NSInvalidArgumentException")
        XCTAssertEqual(json?["reason"] as? String, "Test crash")
        XCTAssertEqual((json?["callStack"] as? [String])?.count, 3)
        XCTAssertEqual(json?["appVersion"] as? String, "1.0.0")
        XCTAssertEqual(json?["deviceModel"] as? String, "iPhone15,2")
    }

    func testCrashReportRoundTrip() throws {
        let original = CrashReport(
            type: "signal",
            name: "SIGSEGV",
            reason: "Signal 11 received",
            callStack: [],
            timestamp: Date(),
            appVersion: "1.0.0",
            buildNumber: "42",
            osVersion: "iOS 18.0",
            deviceModel: "arm64"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CrashReport.self, from: data)

        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.reason, original.reason)
        XCTAssertEqual(decoded.buildNumber, original.buildNumber)
    }

    // MARK: - Singleton

    func testSharedInstanceExists() {
        let reporter = CrashReporter.shared
        XCTAssertNotNil(reporter)
    }

    func testSharedInstanceIsSingleton() {
        let a = CrashReporter.shared
        let b = CrashReporter.shared
        XCTAssertTrue(a === b)
    }
}
