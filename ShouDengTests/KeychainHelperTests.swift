import XCTest
@testable import ShouDeng

/// Tests for KeychainHelper — secure token storage wrapper.
final class KeychainHelperTests: XCTestCase {

    private let keychain = KeychainHelper.shared

    override func setUp() {
        super.setUp()
        // Clean up before each test
        keychain.deleteAll()
    }

    override func tearDown() {
        keychain.deleteAll()
        super.tearDown()
    }

    // MARK: - Save & Read

    func testSaveAndReadAccessToken() {
        keychain.save("test-access-token-123", for: .accessToken)
        let read = keychain.read(.accessToken)
        XCTAssertEqual(read, "test-access-token-123")
    }

    func testSaveAndReadRefreshToken() {
        keychain.save("refresh-token-abc", for: .refreshToken)
        let read = keychain.read(.refreshToken)
        XCTAssertEqual(read, "refresh-token-abc")
    }

    func testSaveAndReadUserId() {
        keychain.save("user-id-xyz", for: .userId)
        let read = keychain.read(.userId)
        XCTAssertEqual(read, "user-id-xyz")
    }

    func testSaveAndReadDeviceSecret() {
        keychain.save("device-secret-456", for: .deviceSecret)
        let read = keychain.read(.deviceSecret)
        XCTAssertEqual(read, "device-secret-456")
    }

    // MARK: - Overwrite

    func testOverwriteExistingValue() {
        keychain.save("old-value", for: .accessToken)
        keychain.save("new-value", for: .accessToken)
        let read = keychain.read(.accessToken)
        XCTAssertEqual(read, "new-value")
    }

    // MARK: - Delete

    func testDeleteRemovesValue() {
        keychain.save("to-be-deleted", for: .accessToken)
        keychain.delete(.accessToken)
        let read = keychain.read(.accessToken)
        XCTAssertNil(read)
    }

    func testDeleteNonexistentKeyDoesNotCrash() {
        // Should not throw or crash
        keychain.delete(.deviceSecret)
        XCTAssertNil(keychain.read(.deviceSecret))
    }

    // MARK: - Delete All

    func testDeleteAllClearsAllKeys() {
        keychain.save("a", for: .accessToken)
        keychain.save("b", for: .refreshToken)
        keychain.save("c", for: .userId)
        keychain.save("d", for: .deviceSecret)

        keychain.deleteAll()

        XCTAssertNil(keychain.read(.accessToken))
        XCTAssertNil(keychain.read(.refreshToken))
        XCTAssertNil(keychain.read(.userId))
        XCTAssertNil(keychain.read(.deviceSecret))
    }

    // MARK: - Read Missing

    func testReadMissingKeyReturnsNil() {
        let read = keychain.read(.accessToken)
        XCTAssertNil(read)
    }

    // MARK: - Special Characters

    func testSaveTokenWithSpecialCharacters() {
        let token = "eyJhbGciOiJIUzI1NiJ9.eyJ1aWQiOiJ0ZXN0In0.abc+/=_-~!@#$%"
        keychain.save(token, for: .accessToken)
        let read = keychain.read(.accessToken)
        XCTAssertEqual(read, token)
    }

    func testSaveUnicodeValue() {
        let value = "守灯-用户-测试-🔒"
        keychain.save(value, for: .userId)
        let read = keychain.read(.userId)
        XCTAssertEqual(read, value)
    }

    // MARK: - Key Enum

    func testKeyRawValues() {
        XCTAssertEqual(KeychainHelper.Key.accessToken.rawValue, "accessToken")
        XCTAssertEqual(KeychainHelper.Key.refreshToken.rawValue, "refreshToken")
        XCTAssertEqual(KeychainHelper.Key.userId.rawValue, "userId")
        XCTAssertEqual(KeychainHelper.Key.deviceSecret.rawValue, "deviceSecret")
    }
}
