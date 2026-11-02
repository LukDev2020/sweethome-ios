import XCTest
import Combine
@testable import ShouDeng

/// Roles phase A (docs/roles/ROLES.md): invite errors are told apart, sign-up has
/// no default role, an unregistered login needs no second SMS, a token refresh is
/// not a new login, and an invite link opens the confirmation sheet.
final class InviteFlowTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func json(_ s: String) -> Data { s.data(using: .utf8)! }

    private func coded(_ status: Int, _ body: String) -> APIServerError {
        APIServerError(status: status, body: json(body))!
    }

    // MARK: - Error mapping (mockup ③)

    func testServerErrorCodesMapToTheirOwnFailure() {
        XCTAssertEqual(InviteFailure(error: coded(404, #"{"error":"x","code":"NOT_FOUND"}"#)), .notFound)
        XCTAssertEqual(InviteFailure(error: coded(410, #"{"error":"x","code":"INVITE_EXPIRED"}"#)), .expired)
        XCTAssertEqual(InviteFailure(error: coded(409, #"{"error":"x","code":"INVITE_USED"}"#)), .used)
        XCTAssertEqual(InviteFailure(error: coded(400, #"{"error":"x","code":"SELF_ACCEPT"}"#)), .selfAccept)
        XCTAssertEqual(
            InviteFailure(error: coded(403, #"{"error":"x","code":"PLAN_LIMIT","upgrade":true,"maxProtected":1,"guardianIsYou":false}"#)),
            .planLimit(max: 1, yourPlan: false))
        XCTAssertEqual(
            InviteFailure(error: coded(403, #"{"code":"PLAN_LIMIT","maxProtected":4,"guardianIsYou":true}"#)),
            .planLimit(max: 4, yourPlan: true))
    }

    func testUnknownCodesAndOlderServersFallBackToTheStatus() {
        XCTAssertEqual(InviteFailure(error: coded(410, #"{"code":"SOMETHING_NEW"}"#)), .expired)
        XCTAssertEqual(InviteFailure(error: APIError.notFound), .notFound)
        XCTAssertEqual(InviteFailure(error: APIError.conflict), .used)
        XCTAssertEqual(InviteFailure(error: APIError.serverError(410)), .expired)
        XCTAssertEqual(InviteFailure(error: APIError.forbidden), .planLimit(max: nil, yourPlan: false))
        XCTAssertEqual(InviteFailure(error: APIError.rateLimited), .tooManyAttempts)
        XCTAssertEqual(InviteFailure(error: APIError.networkError(URLError(.notConnectedToInternet))), .network)
        XCTAssertEqual(InviteFailure(error: APIError.serverError(503)), .network)
        XCTAssertEqual(InviteFailure(error: URLError(.timedOut)), .network)
        XCTAssertEqual(InviteFailure(error: APIError.validation("bad")), .other)
    }

    func testPreviewOfAnInviteThatCantBeAccepted() {
        func preview(_ status: String, own: Bool = false) -> InvitePreviewResponse {
            InvitePreviewResponse(code: "ABC123", inviterName: "Mom", avatarInitial: "M", inviterRole: "protected",
                                  expiresAt: nil, status: status, isOwnInvite: own)
        }
        XCTAssertEqual(InviteFailure(preview: preview("expired")), .expired)
        XCTAssertEqual(InviteFailure(preview: preview("accepted")), .used)
        XCTAssertEqual(InviteFailure(preview: preview("pending", own: true)), .selfAccept)
        XCTAssertNil(InviteFailure(preview: preview("pending")))
    }

    func testEveryFailureHasItsOwnLocalizedMessage() {
        let all: [InviteFailure] = [.notFound, .expired, .used, .selfAccept, .planLimit(max: 1, yourPlan: false),
                                    .planLimit(max: nil, yourPlan: false), .planLimit(max: 2, yourPlan: true),
                                    .planLimit(max: nil, yourPlan: true), .network, .tooManyAttempts, .other]
        let messages = all.map(\.message)
        XCTAssertEqual(Set(messages).count, messages.count, "messages must differ: \(messages)")
        for m in messages {
            XCTAssertFalse(m.hasPrefix("invite.error."), "raw key on screen: \(m)")
            XCTAssertFalse(m.contains("%d"), m)
        }
        XCTAssertTrue(InviteFailure.planLimit(max: 1, yourPlan: false).message.contains("1"))
        XCTAssertTrue(InviteFailure.planLimit(max: 1, yourPlan: false).suggestsAskingToUpgrade)
        XCTAssertFalse(InviteFailure.planLimit(max: 1, yourPlan: true).suggestsAskingToUpgrade)
        XCTAssertFalse(InviteFailure.expired.suggestsAskingToUpgrade)
    }

    func testCodedRequestsThrowTheServerCodeButPlainRequestsDoNot() async throws {
        let client = APIClient(config: .init(baseURL: "https://api.test"), offlineQueue: OfflineQueue(fileURL: nil),
                               sessionConfiguration: StubURLProtocol.session())
        StubURLProtocol.handler = { _ in (410, self.json(#"{"error":"Invite has expired","code":"INVITE_EXPIRED"}"#)) }

        do {
            let _: InvitePreviewResponse = try await client.getReportingCode("/v1/invite/preview?code=ABC123")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIServerError, APIServerError(status: 410, code: "INVITE_EXPIRED", message: "Invite has expired"))
            XCTAssertEqual(InviteFailure(error: error), .expired)
        }
        // Everyone else still gets the generic APIError
        do {
            let _: InvitePreviewResponse = try await client.get("/v1/invite/preview?code=ABC123")
            XCTFail("expected an error")
        } catch {
            guard case .serverError(410)? = error as? APIError else { return XCTFail("\(error)") }
        }
    }

    func testInviteRequestsCarryTheDirection() throws {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CreateInviteRequest(inviterRole: .guardian))) as? [String: String]
        XCTAssertEqual(body, ["inviterRole": "guardian"])
        let preview = InvitePreviewResponse(code: "A1B2C3", inviterName: nil, avatarInitial: nil, inviterRole: "guardian",
                                            expiresAt: nil, status: "pending", isOwnInvite: false)
        XCTAssertEqual(preview.acceptorRole, .protected_)
        let other = InvitePreviewResponse(code: "A1B2C3", inviterName: nil, avatarInitial: nil, inviterRole: "protected",
                                          expiresAt: nil, status: "pending", isOwnInvite: false)
        XCTAssertEqual(other.acceptorRole, .guardian)
        XCTAssertEqual(InviteAcceptSheet.inviterName(preview), LanguageManager.shared.localized("invite.accept.someone"))
    }

    // MARK: - Sign-up role gating

    func testFinishNeedsAStartChoice() {
        XCTAssertFalse(SignupProfileGate.canFinish(name: "Ann", selectedRole: nil, usesInviteCode: false,
                                                   inviteCode: "", agreedToDataTransfer: true),
                       "nothing is preselected")
        XCTAssertTrue(SignupProfileGate.canFinish(name: "Ann", selectedRole: .protected_, usesInviteCode: false,
                                                  inviteCode: "", agreedToDataTransfer: true))
        XCTAssertTrue(SignupProfileGate.canFinish(name: "Ann", selectedRole: .guardian, usesInviteCode: false,
                                                  inviteCode: "", agreedToDataTransfer: true))
    }

    func testInvitePathNeedsACode() {
        XCTAssertFalse(SignupProfileGate.canFinish(name: "Ann", selectedRole: nil, usesInviteCode: true,
                                                   inviteCode: "", agreedToDataTransfer: true))
        XCTAssertFalse(SignupProfileGate.canFinish(name: "Ann", selectedRole: nil, usesInviteCode: true,
                                                   inviteCode: "7F", agreedToDataTransfer: true))
        XCTAssertTrue(SignupProfileGate.canFinish(name: "Ann", selectedRole: nil, usesInviteCode: true,
                                                  inviteCode: "7F3A9C", agreedToDataTransfer: true))
    }

    func testFinishStillNeedsNameAndConsent() {
        XCTAssertFalse(SignupProfileGate.canFinish(name: "  ", selectedRole: .guardian, usesInviteCode: false,
                                                   inviteCode: "", agreedToDataTransfer: true))
        XCTAssertFalse(SignupProfileGate.canFinish(name: "Ann", selectedRole: .guardian, usesInviteCode: false,
                                                   inviteCode: "", agreedToDataTransfer: false))
    }

    func testAccountRoleOnEachPath() {
        XCTAssertNil(SignupProfileGate.accountRole(selectedRole: nil, usesInviteCode: false))
        XCTAssertEqual(SignupProfileGate.accountRole(selectedRole: .guardian, usesInviteCode: false), .guardian)
        // The invite decides when accepted; the account starts on the protected side
        XCTAssertEqual(SignupProfileGate.accountRole(selectedRole: nil, usesInviteCode: true), .protected_)
    }

    // MARK: - Login 404 → signup without a second SMS

    private func makeAuth(_ phone: MockPhoneAuthProvider) -> AuthManager {
        let client = APIClient(config: .init(baseURL: "https://api.test"), offlineQueue: OfflineQueue(fileURL: nil),
                               sessionConfiguration: StubURLProtocol.session())
        return AuthManager(api: client, phoneAuth: phone,
                           defaults: UserDefaults(suiteName: "invite-tests-\(UUID().uuidString)")!, restore: false)
    }

    private func waitForMain() async {
        await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
    }

    @MainActor
    func testUnregisteredLoginKeepsTheVerificationForSignup() async throws {
        let phone = MockPhoneAuthProvider()
        let auth = makeAuth(phone)
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/auth/login": return (404, self.json(#"{"error":"User not found"}"#))
            case "/v1/auth/signup":
                return (201, self.json(#"{"accessToken":"a1","refreshToken":"r1","userId":"new-user","role":"guardian","displayName":"Ann"}"#))
            default: return (404, self.json("{}"))
            }
        }

        try await auth.requestCode(phone: "+14165550123")
        do {
            try await auth.login(phone: "+14165550123", code: "123456")
            XCTFail("expected userNotFound")
        } catch AuthError.userNotFound {}
        XCTAssertTrue(auth.hasVerifiedPhone)

        try await auth.signup(displayName: "Ann", role: "guardian", countryCode: "CA")
        await waitForMain()

        XCTAssertEqual(phone.verifyCount, 1, "no second SMS")
        XCTAssertEqual(phone.signInCount, 1, "the code is not entered twice")
        let signup = try XCTUnwrap(StubURLProtocol.requests.first { $0.path == "/v1/auth/signup" })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: signup.body ?? Data()) as? [String: Any])
        XCTAssertEqual(body["idToken"] as? String, "mock-idtoken-mock-verification-id-\("+14165550123".hash)")
        XCTAssertEqual(auth.state, .loggedIn(userId: "new-user"))
        XCTAssertFalse(auth.hasVerifiedPhone, "used up by signup")
        auth.logout()
    }

    @MainActor
    func testFailedLoginForOtherReasonsKeepsNoVerification() async throws {
        let auth = makeAuth(MockPhoneAuthProvider())
        StubURLProtocol.handler = { _ in (500, self.json("{}")) }
        try await auth.requestCode(phone: "+14165550123")
        do { try await auth.login(phone: "+14165550123", code: "123456"); XCTFail("expected an error") } catch {}
        XCTAssertFalse(auth.hasVerifiedPhone)
    }

    // MARK: - Token refresh is not a new login

    @MainActor
    func testRefreshForTheSameUserDoesNotRepublishLoggedIn() async throws {
        let auth = makeAuth(MockPhoneAuthProvider())
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/auth/login":
                return (200, self.json(#"{"accessToken":"a1","refreshToken":"r1","userId":"u1","role":"protected"}"#))
            case "/v1/auth/refresh":
                return (200, self.json(#"{"accessToken":"a2","refreshToken":"r2","userId":"u1","role":"protected"}"#))
            default: return (404, self.json("{}"))
            }
        }
        try await auth.requestCode(phone: "+14165550123")
        try await auth.login(phone: "+14165550123", code: "123456")
        await waitForMain()
        XCTAssertEqual(auth.state, .loggedIn(userId: "u1"))

        var published: [AuthManager.AuthState] = []
        let sub = auth.$state.dropFirst().sink { published.append($0) }
        try await auth.refreshToken()
        await waitForMain()
        XCTAssertEqual(published, [], "a refresh must not re-run the login flow")
        XCTAssertEqual(StubURLProtocol.requests.last?.path, "/v1/auth/refresh")
        sub.cancel()
        auth.logout()
    }

    // MARK: - Invite links open the sheet

    func testInviteLinkFormats() {
        let cases: [(String, DeepLinkDestination?)] = [
            ("https://shoudeng.app/invite/7f3a9c", .invite(code: "7F3A9C")),
            ("https://shoudeng.app/invite?code=7F3A9C", .invite(code: "7F3A9C")),
            ("shoudeng://invite/7F3A9C", .invite(code: "7F3A9C")),
            ("shoudeng://invite?code=7f3a9c", .invite(code: "7F3A9C")),
            ("https://shoudeng.app/invite", nil),
            ("https://shoudeng.app/invite?code=%24", nil),
            ("https://shoudeng.app/evidence/tok", .evidence(shareToken: "tok")),
        ]
        for (url, expected) in cases {
            XCTAssertEqual(DeepLinkRouter.parse(url: URL(string: url)!), expected, url)
        }
    }

    @MainActor
    private func makeCoordinator() -> AppCoordinator {
        AppCoordinator(environment: .init(
            isDemo: true,
            baseURL: "https://api.test",
            sessionConfiguration: StubURLProtocol.session(),
            offlineQueue: OfflineQueue(fileURL: nil),
            defaults: UserDefaults(suiteName: "invite-tests-\(UUID().uuidString)")!
        ))
    }

    @MainActor
    func testInviteLinkWhileSignedInPresentsTheSheet() {
        let coordinator = makeCoordinator()
        coordinator.authManager.startDemoSession(userId: "u1", role: "protected")

        coordinator.handleDeepLink(URL(string: "https://shoudeng.app/invite?code=7f3a9c")!)

        XCTAssertTrue(coordinator.showInviteAccept)
        XCTAssertEqual(coordinator.pendingInviteCode, "7F3A9C")
        XCTAssertTrue(InviteSheetGate.isPresented(requested: coordinator.showInviteAccept,
                                                  authState: coordinator.authManager.state, biometricLocked: false))
        XCTAssertFalse(InviteSheetGate.isPresented(requested: coordinator.showInviteAccept,
                                                   authState: coordinator.authManager.state, biometricLocked: true),
                       "waits for Face ID")
    }

    @MainActor
    func testInviteLinkWhileSignedOutWaitsForLogin() {
        let coordinator = makeCoordinator()
        XCTAssertEqual(coordinator.authManager.state, .loggedOut)

        coordinator.handleDeepLink(URL(string: "https://shoudeng.app/invite/7F3A9C")!)

        XCTAssertFalse(coordinator.showInviteAccept)
        XCTAssertEqual(coordinator.pendingDeepLink, .invite(code: "7F3A9C"), "kept for sign-up / after login")
        XCTAssertFalse(InviteSheetGate.isPresented(requested: true, authState: .loggedOut, biometricLocked: false))
    }

    @MainActor
    func testEveryEntryPointUsesTheSameSheet() {
        let coordinator = makeCoordinator()
        coordinator.presentInviteAccept()
        XCTAssertTrue(coordinator.showInviteAccept)
        XCTAssertNil(coordinator.pendingInviteCode, "family circle / Settings open with an empty code")
        coordinator.presentInviteAccept(code: " 7f3a9c ")
        XCTAssertEqual(coordinator.pendingInviteCode, "7F3A9C")
    }

    // MARK: - Accepting refreshes the family on my side

    @MainActor
    func testAcceptingRefreshesProfileAndTheFamilyOnMySide() async throws {
        let coordinator = makeCoordinator()
        coordinator.authManager.startDemoSession(userId: "kid", role: "protected")
        StubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/v1/invite/accept":
                return (200, self.json(#"{"success":true,"guardianId":"kid","protectedPersonId":"mom","linkId":"kid_mom","acceptorRole":"guardian"}"#))
            default:
                return (404, self.json("{}"))
            }
        }

        let response = try await coordinator.acceptInvite(code: "7F3A9C", criticalAlertConsent: false)

        XCTAssertEqual(response.acceptorRole, "guardian")
        let paths = StubURLProtocol.requests.map(\.path)
        let afterAccept = paths[(paths.firstIndex(of: "/v1/invite/accept") ?? 0)...]
        XCTAssertTrue(afterAccept.contains("/v1/user/me"), "\(paths)")
        XCTAssertTrue(afterAccept.contains("/v1/guardian/protected-persons"), "I became the guardian: \(paths)")
        let accept = try XCTUnwrap(StubURLProtocol.requests.first { $0.path == "/v1/invite/accept" })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: accept.body ?? Data()) as? [String: Any])
        XCTAssertEqual(body["code"] as? String, "7F3A9C")
        XCTAssertEqual(body["criticalAlertConsent"] as? Bool, false)
    }

    // MARK: - Households (one plan for the family)

    func testGuardianLimitIsItsOwnMessage() {
        let full = APIServerError(status: 403, code: "PLAN_LIMIT",
                                  details: ["limit": "guardians", "max": "4", "guardianIsYou": "false"])
        let failure = InviteFailure(error: full)
        XCTAssertEqual(failure, .guardianLimit(max: 4, yourPlan: false))
        XCTAssertTrue(failure.message.contains("4"))
        XCTAssertTrue(failure.suggestsAskingToUpgrade)
        XCTAssertFalse(InviteFailure.guardianLimit(max: nil, yourPlan: true).message.isEmpty)
    }

    @MainActor
    func testHouseholdPlanUnlocksFeaturesForAFamilyMemberWhoDidntPay() {
        let store = StoreKitManager(apiClient: APIClient(config: .init(baseURL: "https://api.test"), offlineQueue: OfflineQueue(fileURL: nil)), observeTransactions: false)
        store.setAccount("kevin")
        XCTAssertEqual(store.activePlanId, "free")
        XCTAssertFalse(store.canAccessFeature("duty_schedule"))
        store.applyHousehold(.init(planId: "family", payerId: "sarah", payerName: "Sarah",
                                   guardians: 2, maxGuardians: 4, protected: 2, maxProtected: 6))
        XCTAssertEqual(store.activePlanId, "family")
        XCTAssertTrue(store.canAccessFeature("duty_schedule"))
        XCTAssertEqual(store.coveredByName, "Sarah")
        XCTAssertEqual(store.maxProtected, 6)
        XCTAssertEqual(store.maxGuardians, 4)
        // Own plan: not "covered by"
        store.applyHousehold(.init(planId: "family", payerId: "kevin", payerName: nil,
                                   guardians: 1, maxGuardians: 4, protected: 1, maxProtected: 6))
        XCTAssertNil(store.coveredByName)
    }
}
