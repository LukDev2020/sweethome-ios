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

    func testAPIErrorDescriptions() {
        XCTAssertEqual(APIError.invalidURL.errorDescription, "无效的请求地址")
        XCTAssertEqual(APIError.unauthorized.errorDescription, "登录已过期，请重新登录")
        XCTAssertEqual(APIError.forbidden.errorDescription, "无权执行此操作")
        XCTAssertEqual(APIError.notFound.errorDescription, "请求的资源不存在")
        XCTAssertEqual(APIError.rateLimited.errorDescription, "请求过于频繁，请稍后再试")
        XCTAssertEqual(APIError.serverError(500).errorDescription, "服务器错误（500）")
        XCTAssertEqual(APIError.unknown.errorDescription, "未知错误")
    }

    func testValidationError() {
        let error = APIError.validation("手机号格式错误")
        XCTAssertEqual(error.errorDescription, "手机号格式错误")
    }

    func testNetworkError() {
        let underlying = NSError(domain: NSURLErrorDomain, code: -1009)
        let error = APIError.networkError(underlying)
        XCTAssertEqual(error.errorDescription, "网络连接失败，请检查网络设置")
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
