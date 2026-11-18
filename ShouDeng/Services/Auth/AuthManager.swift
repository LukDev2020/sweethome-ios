import Foundation
import UIKit
import Combine
import FirebaseCore
import FirebaseAuth

// MARK: - Auth Manager
//
// Manages authentication state: phone OTP login, Sign in with Apple, Sign in with
// Alipay, signup, token refresh, logout. Phone numbers are verified by Firebase
// Phone Auth; Apple and Alipay by our server (IdentitySignIn.swift). Every method
// ends with our backend's own session tokens.
//
// Phone flow:
//   1. requestCode(phone:) → Firebase sends SMS, stores verificationID
//   2. verifyCode(code:) → Firebase verifies OTP, returns idToken
//   3. login/signup → sends idToken to backend, gets app tokens

final class AuthManager: ObservableObject {

    enum AuthState: Equatable {
        case unknown       // App just launched, checking keychain
        case loggedOut
        case loggedIn(userId: String)
    }

    @Published var state: AuthState = .unknown
    @Published var lastLoginRole: String?

    var isLoggedIn: Bool {
        if case .loggedIn = state { return true }
        return false
    }

    var currentUserId: String? {
        if case .loggedIn(let userId) = state { return userId }
        return nil
    }

    private let keychain = KeychainHelper.shared
    private let api: APIClient
    private let phoneAuth: PhoneAuthProviding

    /// Stored verification ID from Firebase after SMS is sent.
    private var verificationID: String?

    /// Stored idToken from verified OTP, used by signup flow.
    private var verifiedIdToken: String?

    /// The phone number was verified (by signup, or by a login that found no
    /// account) and signup can go straight to the profile step.
    var hasVerifiedPhone: Bool { verifiedIdToken != nil }

    /// Apple / Alipay sign-in the server verified with no account yet: signup uses
    /// it, or a phone sign-in connects it to the existing account.
    @Published var pendingIdentity: PendingIdentity?

    /// The Alipay round trip in progress (state + the secret only this phone knows).
    /// Kept in the keychain for its 10 minutes: iOS may close the app while the
    /// person is in the Alipay app, and Alipay's "back" link then relaunches it.
    private(set) var pendingAlipay: AlipayStartResponse? {
        didSet { if persistsSession { Self.storePendingAlipay(pendingAlipay) } }
    }
    private let persistsSession: Bool
    private static let pendingAlipayAccount = "alipay_pending_signin"
    private static let pendingAlipayLifetime: TimeInterval = 10 * 60

    private struct StoredAlipay: Codable {
        let start: AlipayStartResponse
        let savedAt: Date
    }

    private static func storePendingAlipay(_ start: AlipayStartResponse?) {
        let value = start.flatMap { try? JSONEncoder().encode(StoredAlipay(start: $0, savedAt: Date())) }
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        KeychainHelper.shared.save(pendingAlipayAccount, value: value)
    }

    private static func loadPendingAlipay() -> AlipayStartResponse? {
        guard let raw = KeychainHelper.shared.read(pendingAlipayAccount), !raw.isEmpty,
              let stored = try? JSONDecoder().decode(StoredAlipay.self, from: Data(raw.utf8)),
              Date().timeIntervalSince(stored.savedAt) < pendingAlipayLifetime else { return nil }
        return stored.start
    }

    /// M5 fix: prevent concurrent token refresh calls
    private var isRefreshing = false
    private var refreshContinuations: [CheckedContinuation<Void, Error>] = []

    private let defaults: UserDefaults

    /// - Parameters:
    ///   - defaults: where `currentUserId` is mirrored (Explore Mode passes a throw-away suite)
    ///   - restore: read the saved session from the keychain (false for Explore Mode)
    init(api: APIClient, phoneAuth: PhoneAuthProviding = FirebasePhoneAuthProvider(),
         defaults: UserDefaults = .standard, restore: Bool = true) {
        self.api = api
        self.phoneAuth = phoneAuth
        self.defaults = defaults
        self.persistsSession = restore
        if restore {
            restoreSession()
            pendingAlipay = Self.loadPendingAlipay()
        } else {
            state = .loggedOut
        }
    }

    /// Explore Mode: become a sample family member. No token, no keychain write.
    func startDemoSession(userId: String, role: String) {
        lastLoginRole = role
        state = .loggedIn(userId: userId)
    }

    // MARK: - Session Restore

    private func restoreSession() {
        switch (keychain.readResult(.accessToken), keychain.readResult(.userId)) {
        case (.value(let token), .value(let userId)) where !token.isEmpty:
            // Reject dev tokens left over from debug builds
            if token.hasPrefix("dev_token_") {
                logout()
                return
            }
            api.setAccessToken(token)
            state = .loggedIn(userId: userId)
            defaults.set(userId, forKey: "currentUserId")
        case (.unavailable, _), (_, .unavailable):
            // Keychain locked (background launch before first unlock). Stay
            // .unknown — NOT .loggedOut, which would wipe local data — and retry
            // once protected data becomes available.
            state = .unknown
            waitForProtectedData()
        default:
            state = .loggedOut
        }
    }

    private var protectedDataObserver: NSObjectProtocol?

    private func waitForProtectedData() {
        guard protectedDataObserver == nil else { return }
        protectedDataObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let observer = self.protectedDataObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            self.protectedDataObserver = nil
            self.restoreSession()
        }
    }

    // MARK: - Step 1: Request OTP Code

    /// Send verification code to the E.164 formatted phone number.
    /// Example: "+8613800138000", "+14155551234"
    func requestCode(phone: String) async throws {
        let vid = try await phoneAuth.verifyPhoneNumber(phone)
        verificationID = vid
    }

    // MARK: - Step 2: Verify OTP Code

    /// Verify OTP code with Firebase and store the idToken for subsequent signup.
    func verifyCode(code: String) async throws {
        guard let vid = verificationID else {
            throw AuthError.noVerificationID
        }
        verifiedIdToken = try await phoneAuth.signIn(verificationID: vid, verificationCode: code)
    }

    // MARK: - Step 2 + 3: Login (verify code + exchange with backend)

    func login(phone: String, code: String) async throws {
        guard let vid = verificationID else {
            throw AuthError.noVerificationID
        }

        // Verify OTP with Firebase -> get idToken
        let idToken = try await phoneAuth.signIn(verificationID: vid, verificationCode: code)

        // Exchange idToken with our backend (connecting a pending Apple / Alipay sign-in)
        do {
            let response: AuthResponse
            if let pending = pendingIdentity {
                do {
                    response = try await api.postReportingCode(
                        "/v1/auth/login",
                        body: LoginLinkingRequest(idToken: idToken, linkToken: pending.signupToken)
                    )
                } catch let error as APIServerError {
                    throw IdentitySignInError.from(error)
                }
                await MainActor.run { self.pendingIdentity = nil }
            } else {
                response = try await api.post(
                    "/v1/auth/login",
                    body: LoginWithTokenRequest(idToken: idToken)
                )
            }
            handleAuthResponse(response)
        } catch {
            #if DEBUG
            print("[AuthManager] login backend error: \(type(of: error)) — \(error)")
            #endif
            // 404 from backend means user not registered. The phone number is
            // verified already: keep the idToken so signup needs no second SMS.
            if let apiError = error as? APIError, case .notFound = apiError {
                #if DEBUG
                print("[AuthManager] → user not found, redirecting to signup")
                #endif
                verifiedIdToken = idToken
                throw AuthError.userNotFound
            }
            throw error
        }
    }

    // MARK: - Signup (verify code + create account on backend)

    func signup(displayName: String, role: String, countryCode: String,
                dataTransferConsent: String? = nil) async throws {
        // Apple / Alipay: the server's signup token stands in for a verified phone
        if verifiedIdToken == nil, let pending = pendingIdentity {
            let response: AuthResponse
            do {
                response = try await api.postReportingCode(
                    "/v1/auth/signup",
                    body: SignupWithIdentityRequest(signupToken: pending.signupToken, displayName: displayName,
                                                    role: role, countryCode: countryCode,
                                                    dataTransferConsent: dataTransferConsent)
                )
            } catch {
                throw IdentitySignInError.from(error)
            }
            handleAuthResponse(response)
            await MainActor.run { self.pendingIdentity = nil }
            return
        }
        guard let idToken = verifiedIdToken else {
            throw AuthError.noVerificationID
        }

        // Create account on backend with previously verified idToken
        let response: AuthResponse = try await api.post(
            "/v1/auth/signup",
            body: SignupWithTokenRequest(
                idToken: idToken,
                displayName: displayName,
                role: role,
                countryCode: countryCode,
                dataTransferConsent: dataTransferConsent
            )
        )
        handleAuthResponse(response)
        verifiedIdToken = nil
        // Came from Apple / Alipay, then signed up with a phone number: connect it too
        if let pending = pendingIdentity {
            let _: EmptyResponse? = try? await api.postReportingCode("/v1/auth/link",
                                                                     body: SignupTokenRequest(signupToken: pending.signupToken))
            await MainActor.run { self.pendingIdentity = nil }
        }
    }

    // MARK: - Sign in with Apple / Alipay

    /// Which buttons to show (Alipay only once the server has its keys)
    func providers() async -> AuthProvidersResponse? {
        try? await api.get("/v1/auth/providers")
    }

    @MainActor
    func signInWithApple(identityToken: String, rawNonce: String, authorizationCode: String?,
                         fullName: String?) async throws -> IdentityOutcome {
        do {
            let response: IdentitySignInResponse = try await api.postReportingCode(
                "/v1/auth/apple",
                body: AppleSignInRequest(identityToken: identityToken, rawNonce: rawNonce,
                                         authorizationCode: authorizationCode, fullName: fullName)
            )
            return try accept(response, provider: .apple)
        } catch APIError.unauthorized {
            throw IdentitySignInError.appleFailed
        } catch {
            throw IdentitySignInError.from(error)
        }
    }

    @MainActor
    func startAlipaySignIn() async throws -> AlipayStartResponse {
        do {
            let start: AlipayStartResponse = try await api.postReportingCode("/v1/auth/alipay/start", body: EmptyBody())
            pendingAlipay = start
            return start
        } catch APIError.serverError(503) {
            throw IdentitySignInError.alipayUnavailable
        } catch {
            throw IdentitySignInError.from(error)
        }
    }

    /// Back from Alipay: signed in, a profile to fill in, or still waiting for Alipay.
    /// `connecting`: Settings → connect Alipay to the signed-in account instead.
    @MainActor
    func completeAlipaySignIn(connecting: Bool = false) async throws -> IdentityOutcome {
        guard let pending = pendingAlipay else { throw IdentitySignInError.alipayNotConfirmed }
        do {
            let response: IdentitySignInResponse = try await api.postReportingCode(
                "/v1/auth/alipay/complete",
                body: AlipayCompleteRequest(state: pending.state, secret: pending.secret)
            )
            if response.status == "pending" { return .waiting }
            pendingAlipay = nil
            guard connecting else { return try accept(response, provider: .alipay) }
            try await link(response)
            return .signedIn
        } catch let error as APIServerError {
            // Declined, expired or unknown: this round trip is over
            pendingAlipay = nil
            throw IdentitySignInError.from(error)
        }
    }

    @MainActor
    func cancelAlipaySignIn() {
        pendingAlipay = nil
    }

    @MainActor
    func cancelPendingIdentity() {
        pendingIdentity = nil
    }

    @MainActor
    private func accept(_ response: IdentitySignInResponse, provider: PendingIdentity.Provider) throws -> IdentityOutcome {
        if let auth = response.authResponse {
            pendingIdentity = nil
            handleAuthResponse(auth)
            return .signedIn
        }
        guard response.status == "signupRequired", let token = response.signupToken else {
            throw provider == .apple ? IdentitySignInError.appleFailed : IdentitySignInError.alipayNotConfirmed
        }
        let pending = PendingIdentity(provider: provider, signupToken: token,
                                      suggestedName: response.displayName, email: response.email)
        pendingIdentity = pending
        return .signupRequired(pending)
    }

    // MARK: - Sign-in methods (Settings)

    func signInMethods() async throws -> SignInMethodsResponse {
        try await api.get("/v1/auth/methods")
    }

    /// Settings → connect Apple to the signed-in account
    @MainActor
    func connectApple(identityToken: String, rawNonce: String, authorizationCode: String?) async throws {
        let response: IdentitySignInResponse
        do {
            response = try await api.postReportingCode(
                "/v1/auth/apple",
                body: AppleSignInRequest(identityToken: identityToken, rawNonce: rawNonce,
                                         authorizationCode: authorizationCode, fullName: nil)
            )
        } catch {
            throw IdentitySignInError.from(error)
        }
        try await link(response)
    }

    /// Connect a verified Apple / Alipay sign-in to the signed-in account
    @MainActor
    private func link(_ response: IdentitySignInResponse) async throws {
        if response.status == "signedIn" {
            // It already opens an account: this one, or another
            if response.userId == currentUserId { return }
            throw IdentitySignInError.linkedElsewhere
        }
        guard let token = response.signupToken else { throw IdentitySignInError.expired }
        do {
            let _: EmptyResponse = try await api.postReportingCode("/v1/auth/link", body: SignupTokenRequest(signupToken: token))
        } catch {
            throw IdentitySignInError.from(error)
        }
    }

    /// Add a phone number to an Apple / Alipay account: Firebase checks the code,
    /// the server attaches the number (texts and calls reach this person; they
    /// can sign in with it too).
    func linkPhone(code: String) async throws -> String? {
        guard let vid = verificationID else { throw AuthError.noVerificationID }
        let idToken = try await phoneAuth.signIn(verificationID: vid, verificationCode: code)
        do {
            let response: LinkPhoneResponse = try await api.postReportingCode("/v1/auth/link-phone",
                                                                             body: LinkPhoneRequest(idToken: idToken))
            return response.phone
        } catch {
            throw IdentitySignInError.from(error)
        }
    }

    // MARK: - Token Refresh

    @MainActor
    func refreshToken() async throws {
        // M5 fix: serialize concurrent refresh calls
        if isRefreshing {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                refreshContinuations.append(continuation)
            }
            return
        }
        isRefreshing = true

        do {
            let refreshToken: String
            switch keychain.readResult(.refreshToken) {
            case .value(let token):
                refreshToken = token
            case .unavailable:
                // Locked before the first unlock (background relaunch): not "no
                // session" — a transient failure that must not sign the person out
                throw KeychainLockedError()
            case .notFound:
                throw APIError.unauthorized
            }
            // No 401→refresh on the refresh call itself (it would await itself)
            let response: AuthResponse = try await api.postWithoutRefresh(
                "/v1/auth/refresh",
                body: RefreshRequest(refreshToken: refreshToken)
            )
            handleAuthResponse(response)
            isRefreshing = false
            let waiters = refreshContinuations
            refreshContinuations = []
            waiters.forEach { $0.resume() }
        } catch {
            isRefreshing = false
            let waiters = refreshContinuations
            refreshContinuations = []
            waiters.forEach { $0.resume(throwing: error) }
            throw error
        }
    }

    /// The keychain can't be read yet (device not unlocked since reboot)
    struct KeychainLockedError: Error {}

    /// Only a definitive answer from /refresh ends the session. Timeouts, 5xx and
    /// 429 must not log the user out (and discard queued SOS) in the middle of an
    /// emergency.
    static func refreshFailureIsDefinitive(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        switch api {
        case .unauthorized, .forbidden: return true
        default: return false
        }
    }

    // MARK: - Dev Login (DEBUG only)

    /// Dev/test login bypass. Creates a fake session so the app is fully navigable.
    func devLogin(role: String = "guardian") {
        let response = AuthResponse(
            accessToken: "dev_token_\(UUID().uuidString)",
            refreshToken: "dev_refresh_\(UUID().uuidString)",
            userId: "dev_user_\(UUID().uuidString.prefix(8))",
            role: role,
            displayName: "开发测试"
        )
        handleAuthResponse(response)
    }

    // MARK: - Logout

    func logout() {
        keychain.deleteAll()
        api.setAccessToken(nil)
        verificationID = nil
        verifiedIdToken = nil
        pendingAlipay = nil
        DispatchQueue.main.async { self.pendingIdentity = nil }
        defaults.removeObject(forKey: "currentUserId")
        state = .loggedOut

        // Reset biometric unlock state so gate re-appears on next login
        BiometricAuthManager.shared.resetUnlockState()

        // Sign out from Firebase too
        phoneAuth.signOut()
    }

    // MARK: - Private

    private func handleAuthResponse(_ response: AuthResponse) {
        keychain.save(response.accessToken, for: .accessToken)
        keychain.save(response.refreshToken, for: .refreshToken)
        keychain.save(response.userId, for: .userId)
        api.setAccessToken(response.accessToken)
        defaults.set(response.userId, forKey: "currentUserId")
        DispatchQueue.main.async {
            // A token refresh for the signed-in user is not a new login: publishing
            // `.loggedIn` again would re-run the whole login flow (onLoginComplete).
            if self.state == .loggedIn(userId: response.userId) { return }
            self.lastLoginRole = response.role
            self.state = .loggedIn(userId: response.userId)
        }
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    /// Only a wrong code counts toward the login lockout — never a network
    /// error, a busy server or an expired sign-in
    static func isWrongCode(_ error: Error) -> Bool {
        if case AuthError.invalidVerificationCode = error { return true }
        return false
    }

    case noVerificationID
    case firebaseNotConfigured
    case invalidVerificationCode
    case smsSendFailed(String)
    case tooManyRequests
    case regionNotEnabled
    case userNotFound

    var errorDescription: String? {
        let lang = LanguageManager.shared
        switch self {
        case .noVerificationID:
            return lang.localized("error.no.code")
        case .firebaseNotConfigured:
            return lang.localized("error.not.configured")
        case .invalidVerificationCode:
            return lang.localized("error.invalid.code")
        case .smsSendFailed(let detail):
            return "\(lang.localized("error.sms.failed"))\(detail)"
        case .tooManyRequests:
            return lang.localized("error.too.many")
        case .regionNotEnabled:
            return lang.localized("error.region")
        case .userNotFound:
            return lang.localized("error.user.not.found")
        }
    }
}

// MARK: - Phone Auth Provider Protocol

/// Abstraction over Firebase Phone Auth for testability.
protocol PhoneAuthProviding {
    /// Send OTP to phone number. Returns a verification ID.
    @MainActor func verifyPhoneNumber(_ phoneNumber: String) async throws -> String

    /// Verify OTP code with the verification ID. Returns Firebase idToken.
    func signIn(verificationID: String, verificationCode: String) async throws -> String

    /// Sign out from the auth provider.
    func signOut()
}

// MARK: - Firebase Phone Auth Provider

final class FirebasePhoneAuthProvider: PhoneAuthProviding {

    private var isFirebaseConfigured: Bool {
        FirebaseApp.app() != nil
    }

    @MainActor
    func verifyPhoneNumber(_ phoneNumber: String) async throws -> String {
        guard isFirebaseConfigured else {
            throw AuthError.firebaseNotConfigured
        }
        #if DEBUG
        print("[FirebaseAuth] verifyPhoneNumber called")
        #endif
        do {
            let verificationID = try await PhoneAuthProvider.provider().verifyPhoneNumber(
                phoneNumber,
                uiDelegate: nil
            )
            #if DEBUG
            print("[FirebaseAuth] verificationID received: \(verificationID.prefix(8))...")
            #endif
            return verificationID
        } catch {
            let nsError = error as NSError
            #if DEBUG
            print("[FirebaseAuth] verifyPhoneNumber FAILED: \(nsError.domain) \(nsError.code)")
            print("[FirebaseAuth]   \(nsError.userInfo)")
            #endif
            // Map Firebase error codes to friendly errors
            switch nsError.code {
            case 17010: // TOO_MANY_REQUESTS
                throw AuthError.tooManyRequests
            case 17006: // SMS region not enabled
                throw AuthError.regionNotEnabled
            default:
                let detail: String
                if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
                   let body = underlyingError.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any],
                   let serverMsg = body["message"] as? String {
                    detail = serverMsg
                } else if let body = nsError.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any],
                          let serverMsg = body["message"] as? String {
                    detail = serverMsg
                } else {
                    detail = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
                }
                throw AuthError.smsSendFailed(detail)
            }
        }
    }

    func signIn(verificationID: String, verificationCode: String) async throws -> String {
        guard isFirebaseConfigured else {
            throw AuthError.firebaseNotConfigured
        }
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: verificationCode
        )

        let result: AuthDataResult
        do {
            result = try await Auth.auth().signIn(with: credential)
        } catch let error as NSError where error.domain == AuthErrorDomain {
            // A wrong code is the only failure that counts toward the lockout
            switch AuthErrorCode(rawValue: error.code) {
            case .invalidVerificationCode: throw AuthError.invalidVerificationCode
            case .tooManyRequests: throw AuthError.tooManyRequests
            default: throw error
            }
        }
        let idToken = try await result.user.getIDToken()
        return idToken
    }

    func signOut() {
        guard isFirebaseConfigured else { return }
        try? Auth.auth().signOut()
    }
}

// MARK: - Request/Response Types

struct LoginWithTokenRequest: Codable {
    let idToken: String
}

struct SignupWithTokenRequest: Codable {
    let idToken: String
    let displayName: String
    let role: String
    let countryCode: String
    /// Version of the "your data is stored in the US" consent the user ticked
    var dataTransferConsent: String? = nil
}

struct RefreshRequest: Codable {
    let refreshToken: String
}

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let role: String?
    let displayName: String?
}

struct EmptyResponse: Codable {}
