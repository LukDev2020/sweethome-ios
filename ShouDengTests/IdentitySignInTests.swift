import XCTest
@testable import ShouDeng

/// Sign in with Apple / Alipay on the phone side, against a stubbed server: what is
/// sent, signed in vs. "fill in your profile", connecting by phone, the Alipay round
/// trip, and the server's error codes turned into words.
@MainActor
final class IdentitySignInTests: XCTestCase {

    private var manager: AuthManager!

    override func setUp() async throws {
        StubURLProtocol.reset()
        let client = APIClient(config: .init(baseURL: "https://api.test"), offlineQueue: OfflineQueue(fileURL: nil),
                               sessionConfiguration: StubURLProtocol.session())
        manager = AuthManager(api: client, phoneAuth: MockPhoneAuthProvider(),
                              defaults: UserDefaults(suiteName: "IdentitySignInTests")!, restore: false)
    }

    override func tearDown() async throws {
        manager.logout()
        StubURLProtocol.reset()
    }

    private func json(_ s: String) -> Data { Data(s.utf8) }
    private func body(_ path: String) throws -> [String: Any] {
        let r = try XCTUnwrap(StubURLProtocol.requests.last { $0.path == path })
        return try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(r.body)) as? [String: Any])
    }

    private let signupRequired = #"{"status":"signupRequired","signupToken":"st-1","displayName":"Wei Chen","email":"wei@privaterelay.appleid.com"}"#
    private let signedIn = #"{"status":"signedIn","accessToken":"a","refreshToken":"r","userId":"u-9","role":"guardian","displayName":"Wei"}"#

    // MARK: Apple

    func testNonceIsRandomAndHashedForApple() {
        let a = AppleSignInNonce.make(), b = AppleSignInNonce.make()
        XCTAssertEqual(a.count, 32)
        XCTAssertNotEqual(a, b)
        // Same as the server's sha256Hex: hex, lowercase, 64 characters
        XCTAssertTrue(AppleSignInNonce.sha256("x").allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertEqual(AppleSignInNonce.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testNewAppleIdGoesToTheProfileStep() async throws {
        StubURLProtocol.handler = { _ in (200, self.json(self.signupRequired)) }
        let outcome = try await manager.signInWithApple(identityToken: "id.tok.en", rawNonce: "n1", authorizationCode: "c1", fullName: "Wei Chen")
        let sent = try body("/v1/auth/apple")
        XCTAssertEqual(sent["identityToken"] as? String, "id.tok.en")
        XCTAssertEqual(sent["rawNonce"] as? String, "n1")
        XCTAssertEqual(sent["authorizationCode"] as? String, "c1")
        XCTAssertEqual(sent["fullName"] as? String, "Wei Chen")
        let pending = PendingIdentity(provider: .apple, signupToken: "st-1", suggestedName: "Wei Chen", email: "wei@privaterelay.appleid.com")
        XCTAssertEqual(outcome, .signupRequired(pending))
        XCTAssertEqual(manager.pendingIdentity, pending)
        XCTAssertFalse(manager.isLoggedIn)

        // The profile step creates the account with the signup token (no phone)
        StubURLProtocol.handler = { _ in (201, self.json(#"{"accessToken":"a","refreshToken":"r","userId":"new-1","role":"protected","displayName":"Wei"}"#)) }
        try await manager.signup(displayName: "Wei", role: "protected", countryCode: "CA", dataTransferConsent: "v1")
        let signup = try body("/v1/auth/signup")
        XCTAssertEqual(signup["signupToken"] as? String, "st-1")
        XCTAssertNil(signup["idToken"])
        XCTAssertEqual(signup["countryCode"] as? String, "CA")
        XCTAssertNil(manager.pendingIdentity)
        try await waitForLogin("new-1")
    }

    func testKnownAppleIdSignsStraightIn() async throws {
        StubURLProtocol.handler = { _ in (200, self.json(self.signedIn)) }
        let outcome = try await manager.signInWithApple(identityToken: "t", rawNonce: "n", authorizationCode: nil, fullName: nil)
        XCTAssertEqual(outcome, .signedIn)
        try await waitForLogin("u-9")
        XCTAssertEqual(manager.lastLoginRole, "guardian")
    }

    func testRejectedAppleTokenSaysSo() async {
        StubURLProtocol.handler = { _ in (401, self.json(#"{"error":"x","code":"APPLE_INVALID"}"#)) }
        do {
            _ = try await manager.signInWithApple(identityToken: "t", rawNonce: "n", authorizationCode: nil, fullName: nil)
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? IdentitySignInError, .appleFailed)
        }
    }

    // MARK: Connecting by phone

    func testPhoneSignInConnectsThePendingAppleId() async throws {
        StubURLProtocol.handler = { _ in (200, self.json(self.signupRequired)) }
        _ = try await manager.signInWithApple(identityToken: "t", rawNonce: "n", authorizationCode: nil, fullName: nil)

        StubURLProtocol.handler = { _ in (200, self.json(#"{"accessToken":"a","refreshToken":"r","userId":"phone-wei","role":"guardian","linked":"apple"}"#)) }
        try await manager.requestCode(phone: "+14165550001")
        try await manager.login(phone: "+14165550001", code: "123456")
        let sent = try body("/v1/auth/login")
        XCTAssertEqual(sent["linkToken"] as? String, "st-1")
        XCTAssertNotNil(sent["idToken"])
        XCTAssertNil(manager.pendingIdentity)
        try await waitForLogin("phone-wei")
    }

    func testAppleIdOnAnotherAccountIsExplained() async throws {
        StubURLProtocol.handler = { _ in (200, self.json(self.signupRequired)) }
        _ = try await manager.signInWithApple(identityToken: "t", rawNonce: "n", authorizationCode: nil, fullName: nil)
        StubURLProtocol.handler = { _ in (409, self.json(#"{"error":"x","code":"IDENTITY_LINKED_ELSEWHERE"}"#)) }
        try await manager.requestCode(phone: "+14165550001")
        do {
            try await manager.login(phone: "+14165550001", code: "123456")
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? IdentitySignInError, .linkedElsewhere)
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    // MARK: Alipay

    func testAlipayRoundTrip() async throws {
        StubURLProtocol.handler = { req in
            switch req.url?.path {
            case "/v1/auth/alipay/start":
                return (200, self.json(#"{"state":"s1","secret":"k1","authUrl":"https://openauth.alipay.com/x","alipayAppUrl":"alipays://y"}"#))
            default:
                return (202, self.json(#"{"status":"pending"}"#))
            }
        }
        let start = try await manager.startAlipaySignIn()
        XCTAssertEqual(start.state, "s1")
        XCTAssertEqual(manager.pendingAlipay?.secret, "k1")

        // Back too early: still waiting, nothing forgotten
        let early = try await manager.completeAlipaySignIn()
        XCTAssertEqual(early, .waiting)
        let sent = try body("/v1/auth/alipay/complete")
        XCTAssertEqual(sent["state"] as? String, "s1")
        XCTAssertEqual(sent["secret"] as? String, "k1")
        XCTAssertNotNil(manager.pendingAlipay)

        StubURLProtocol.handler = { _ in (200, self.json(#"{"status":"signupRequired","signupToken":"st-ali","displayName":"小王"}"#)) }
        let done = try await manager.completeAlipaySignIn()
        XCTAssertEqual(done, .signupRequired(PendingIdentity(provider: .alipay, signupToken: "st-ali", suggestedName: "小王", email: nil)))
        XCTAssertNil(manager.pendingAlipay, "one round trip, used once")
    }

    func testAlipayDeclinedEndsTheRoundTrip() async throws {
        StubURLProtocol.handler = { req in
            req.url?.path == "/v1/auth/alipay/start"
                ? (200, self.json(#"{"state":"s1","secret":"k1","authUrl":"https://a","alipayAppUrl":"alipays://y"}"#))
                : (400, self.json(#"{"error":"x","code":"ALIPAY_DENIED","reason":"declined"}"#))
        }
        _ = try await manager.startAlipaySignIn()
        do {
            _ = try await manager.completeAlipaySignIn()
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? IdentitySignInError, .alipayNotConfirmed)
        }
        XCTAssertNil(manager.pendingAlipay)
    }

    func testAlipayOffOnTheServer() async {
        StubURLProtocol.handler = { _ in (503, self.json(#"{"error":"x","code":"ALIPAY_UNAVAILABLE"}"#)) }
        do {
            _ = try await manager.startAlipaySignIn()
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? IdentitySignInError, .alipayUnavailable)
        }
    }

    func testProvidersTellWhetherToShowAlipay() async {
        StubURLProtocol.handler = { _ in (200, self.json(#"{"phone":true,"apple":true,"alipay":false}"#)) }
        let providers = await manager.providers()
        XCTAssertEqual(providers, AuthProvidersResponse(phone: true, apple: true, alipay: false))
    }

    // MARK: Adding a phone number

    func testAddingAPhoneNumber() async throws {
        StubURLProtocol.handler = { _ in (200, self.json(#"{"success":true,"phone":"+14165550002"}"#)) }
        try await manager.requestCode(phone: "+14165550002")
        let phone = try await manager.linkPhone(code: "123456")
        XCTAssertEqual(phone, "+14165550002")
        XCTAssertNotNil(try body("/v1/auth/link-phone")["idToken"])

        StubURLProtocol.handler = { _ in (409, self.json(#"{"error":"x","code":"PHONE_HAS_ACCOUNT"}"#)) }
        do {
            _ = try await manager.linkPhone(code: "123456")
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? IdentitySignInError, .phoneHasAccount)
        }
    }

    func testEveryErrorHasWordsInEveryLanguage() {
        let all: [IdentitySignInError] = [.appleFailed, .alipayUnavailable, .alipayNotConfirmed, .linkedElsewhere, .phoneHasAccount, .expired]
        for error in all {
            let text = error.localizedDescription
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.hasPrefix("auth."), "missing string for \(error)")
        }
    }

    // MARK: Helpers

    private func waitForLogin(_ uid: String) async throws {
        for _ in 0..<50 where manager.currentUserId != uid { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(manager.currentUserId, uid)
    }
}
