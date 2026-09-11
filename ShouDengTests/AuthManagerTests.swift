import XCTest
@testable import ShouDeng

final class AuthManagerTests: XCTestCase {

    // MARK: - Auth State

    func testInitialStateResolvesFromKeychain() {
        let queue = OfflineQueue()
        let client = APIClient(
            config: .init(baseURL: "https://api.shoudeng.app"),
            offlineQueue: queue
        )
        let manager = AuthManager(api: client, phoneAuth: MockPhoneAuthProvider())

        switch manager.state {
        case .loggedIn, .loggedOut:
            break // Both are valid
        case .unknown:
            XCTFail("State should resolve immediately from keychain")
        }
    }

    func testIsLoggedInProperty() {
        let queue = OfflineQueue()
        let client = APIClient(
            config: .init(baseURL: "https://api.shoudeng.app"),
            offlineQueue: queue
        )
        let manager = AuthManager(api: client, phoneAuth: MockPhoneAuthProvider())

        if case .loggedIn = manager.state {
            XCTAssertTrue(manager.isLoggedIn)
        } else {
            XCTAssertFalse(manager.isLoggedIn)
        }
    }

    // MARK: - Request Types (Firebase token-based)

    func testLoginWithTokenRequestEncoding() throws {
        let request = LoginWithTokenRequest(idToken: "firebase-id-token-abc")
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["idToken"] as? String, "firebase-id-token-abc")
    }

    func testSignupWithTokenRequestEncoding() throws {
        let request = SignupWithTokenRequest(
            idToken: "firebase-id-token-abc",
            displayName: "小明",
            role: "protected"
        )
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["idToken"] as? String, "firebase-id-token-abc")
        XCTAssertEqual(json?["displayName"] as? String, "小明")
        XCTAssertEqual(json?["role"] as? String, "protected")
    }

    func testAuthResponseDecoding() throws {
        let json = """
        {
            "accessToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9",
            "refreshToken": "refresh-token-abc",
            "userId": "user-123"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AuthResponse.self, from: json)
        XCTAssertEqual(response.accessToken, "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9")
        XCTAssertEqual(response.refreshToken, "refresh-token-abc")
        XCTAssertEqual(response.userId, "user-123")
    }

    // MARK: - Logout

    func testLogoutClearsState() {
        let queue = OfflineQueue()
        let client = APIClient(
            config: .init(baseURL: "https://api.shoudeng.app"),
            offlineQueue: queue
        )
        let manager = AuthManager(api: client, phoneAuth: MockPhoneAuthProvider())

        manager.logout()

        XCTAssertEqual(manager.state, .loggedOut)
        XCTAssertFalse(manager.isLoggedIn)
        XCTAssertNil(manager.currentUserId)
    }

    // MARK: - Mock Phone Auth Provider

    func testMockPhoneAuthVerifyReturnsVerificationID() async throws {
        let mock = MockPhoneAuthProvider()
        let vid = try await mock.verifyPhoneNumber("+8613800138000")
        XCTAssertFalse(vid.isEmpty)
    }

    func testMockPhoneAuthSignInReturnsToken() async throws {
        let mock = MockPhoneAuthProvider()
        let token = try await mock.signIn(verificationID: "test-vid", verificationCode: "123456")
        XCTAssertFalse(token.isEmpty)
        XCTAssertTrue(token.contains("mock-idtoken"))
    }

    func testMockPhoneAuthSignInRejectsShortCode() async {
        let mock = MockPhoneAuthProvider()
        do {
            _ = try await mock.signIn(verificationID: "test-vid", verificationCode: "12")
            XCTFail("Should reject code shorter than 4 digits")
        } catch {
            XCTAssertTrue(error is AuthError)
        }
    }

    func testAuthManagerWithMockProvider() {
        let queue = OfflineQueue()
        let client = APIClient(
            config: .init(baseURL: "https://api.shoudeng.app"),
            offlineQueue: queue
        )
        let mock = MockPhoneAuthProvider()
        let manager = AuthManager(api: client, phoneAuth: mock)

        XCTAssertNotNil(manager)
        if case .loggedOut = manager.state {
            // expected
        } else if case .loggedIn = manager.state {
            // also acceptable if previous session exists
        } else {
            XCTFail("Unexpected state")
        }
    }

    func testMockPhoneAuthFailureMode() async {
        let mock = MockPhoneAuthProvider()
        mock.shouldFail = true

        do {
            _ = try await mock.verifyPhoneNumber("+14155551234")
            XCTFail("Should throw when shouldFail is true")
        } catch let error as AuthError {
            if case .smsSendFailed = error {
                // expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testMockPhoneAuthTracksLastPhoneNumber() async throws {
        let mock = MockPhoneAuthProvider()
        _ = try await mock.verifyPhoneNumber("+14155551234")
        XCTAssertEqual(mock.lastPhoneNumber, "+14155551234")
    }

    func testMockPhoneAuthCanadaNumber() async throws {
        let mock = MockPhoneAuthProvider()
        let vid = try await mock.verifyPhoneNumber("+16135551234")
        XCTAssertFalse(vid.isEmpty)
        XCTAssertEqual(mock.lastPhoneNumber, "+16135551234")
    }
}

// MARK: - Mock Phone Auth Provider for Tests

final class MockPhoneAuthProvider: PhoneAuthProviding {
    var lastPhoneNumber: String?
    var shouldFail = false

    func verifyPhoneNumber(_ phoneNumber: String) async throws -> String {
        lastPhoneNumber = phoneNumber
        if shouldFail { throw AuthError.smsSendFailed("Mock failure") }
        return "mock-verification-id-\(phoneNumber.hash)"
    }

    func signIn(verificationID: String, verificationCode: String) async throws -> String {
        if shouldFail { throw AuthError.invalidVerificationCode }
        guard verificationCode.count >= 4 else {
            throw AuthError.invalidVerificationCode
        }
        return "mock-idtoken-\(verificationID)"
    }

    func signOut() {}
}
