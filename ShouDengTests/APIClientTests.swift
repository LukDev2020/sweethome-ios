import XCTest
@testable import ShouDeng

final class APIClientTests: XCTestCase {

    // MARK: - Configuration

    func testBaseURLConfiguration() {
        let config = APIClient.Config(baseURL: "https://api.shoudeng.app")
        XCTAssertEqual(config.baseURL, "https://api.shoudeng.app")
        XCTAssertEqual(config.timeoutInterval, 30)
        XCTAssertEqual(config.maxRetries, 1)
    }

    func testCustomTimeout() {
        let config = APIClient.Config(baseURL: "https://api.shoudeng.app", timeoutInterval: 60)
        XCTAssertEqual(config.timeoutInterval, 60)
    }

    // MARK: - Token Management

    func testSetAccessToken() {
        let queue = OfflineQueue()
        let client = APIClient(
            config: .init(baseURL: "https://api.shoudeng.app"),
            offlineQueue: queue
        )

        client.setAccessToken("test-token-123")
        // Token is private, but we can verify it doesn't crash
        client.setAccessToken(nil)
    }

    // MARK: - Error Descriptions

    /// Messages follow the app's language (they were always Chinese).
    func testAPIErrorDescriptions() {
        let lang = LanguageManager.shared
        let saved = lang.current
        defer { lang.choose(saved) }
        lang.choose(.chinese)
        XCTAssertEqual(APIError.unauthorized.errorDescription, "登录已过期，请重新登录")
        XCTAssertEqual(APIError.serverError(500).errorDescription, "服务器错误（500）")
        lang.choose(.english)
        XCTAssertEqual(APIError.unauthorized.errorDescription, "Your session expired. Sign in again.")
        XCTAssertEqual(APIError.serverError(500).errorDescription, "Server error (500)")
        for error in [APIError.invalidURL, .forbidden, .notFound, .conflict, .rateLimited, .unknown] {
            let text = error.errorDescription ?? ""
            XCTAssertFalse(text.isEmpty || text.hasPrefix("api.error."), "\(error): \(text)")
        }
    }

    func testValidationError() {
        let error = APIError.validation("手机号格式错误")
        XCTAssertEqual(error.errorDescription, "手机号格式错误")
    }

    func testNetworkError() {
        let underlying = NSError(domain: NSURLErrorDomain, code: -1009)
        let error = APIError.networkError(underlying)
        XCTAssertEqual(error.errorDescription, LanguageManager.shared.localized("api.error.network"))
        XCTAssertFalse(error.errorDescription?.hasPrefix("api.error.") ?? true)
    }

    // MARK: - OnUnauthorized Callback

    func testOnUnauthorizedCallbackConfigurable() {
        let queue = OfflineQueue()
        let client = APIClient(
            config: .init(baseURL: "https://api.shoudeng.app"),
            offlineQueue: queue
        )

        XCTAssertNil(client.onUnauthorized)

        client.onUnauthorized = { return false }
        XCTAssertNotNil(client.onUnauthorized)
    }

    // MARK: - Request/Response Types

    func testHeartbeatRequestEncoding() throws {
        let request = HeartbeatRequest(
            userId: "user-1",
            timestamp: Date(timeIntervalSince1970: 1000000),
            source: .appForeground,
            batteryLevel: 0.85,
            batteryState: .charging,
            latitude: 39.9042,
            longitude: 116.4074,
            accuracy: 10
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["user_id"] as? String, "user-1")
        XCTAssertEqual(json?["battery_level"] as? Double, 0.85)
        XCTAssertEqual(json?["latitude"] as? Double, 39.9042)
    }

    func testSOSTriggerRequestEncoding() throws {
        let request = SOSTriggerRequest(
            protectedPersonId: "person-1",
            triggerMethod: .longPress,
            latitude: 39.9042,
            longitude: 116.4074,
            batteryLevel: 0.5
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["protected_person_id"] as? String, "person-1")
        XCTAssertEqual(json?["trigger_method"] as? String, "longPress")
    }

    func testEmptyResponseDecodable() throws {
        let data = "{}".data(using: .utf8)!
        let response = try JSONDecoder().decode(EmptyResponse.self, from: data)
        XCTAssertNotNil(response)
    }
}
