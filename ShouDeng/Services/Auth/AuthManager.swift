import Foundation
import Combine
import FirebaseCore
import FirebaseAuth

// MARK: - Auth Manager
//
// Manages authentication state: phone OTP login, signup, token refresh, logout.
// Uses Firebase Phone Auth for OTP verification, then exchanges the Firebase
// idToken with our backend for app-level session tokens.
//
// Flow:
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

    /// M5 fix: prevent concurrent token refresh calls
    private var isRefreshing = false
    private var refreshContinuations: [CheckedContinuation<Void, Error>] = []

    init(api: APIClient, phoneAuth: PhoneAuthProviding = FirebasePhoneAuthProvider()) {
        self.api = api
        self.phoneAuth = phoneAuth
        restoreSession()
    }

    // MARK: - Session Restore

    private func restoreSession() {
        if let token = keychain.read(.accessToken),
           let userId = keychain.read(.userId),
           !token.isEmpty {
            api.setAccessToken(token)
            state = .loggedIn(userId: userId)
            UserDefaults.standard.set(userId, forKey: "currentUserId")
        } else {
            state = .loggedOut
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

        // Exchange idToken with our backend
        do {
            let response: AuthResponse = try await api.post(
                "/v1/auth/login",
                body: LoginWithTokenRequest(idToken: idToken)
            )
            handleAuthResponse(response)
        } catch {
            #if DEBUG
            print("[AuthManager] login backend error: \(type(of: error)) — \(error)")
            #endif
            // 404 from backend means user not registered
            if let apiError = error as? APIError, case .notFound = apiError {
                #if DEBUG
                print("[AuthManager] → user not found, redirecting to signup")
                #endif
                throw AuthError.userNotFound
            }
            throw error
        }
    }

    // MARK: - Signup (verify code + create account on backend)

    func signup(displayName: String, role: String, countryCode: String) async throws {
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
                countryCode: countryCode
            )
        )
        handleAuthResponse(response)
        verifiedIdToken = nil
    }

    // MARK: - Token Refresh

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
            guard let refreshToken = keychain.read(.refreshToken) else {
                await MainActor.run { state = .loggedOut }
                throw APIError.unauthorized
            }
            let response: AuthResponse = try await api.post(
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

    // MARK: - Logout

    func logout() {
        keychain.deleteAll()
        api.setAccessToken(nil)
        verificationID = nil
        verifiedIdToken = nil
        UserDefaults.standard.removeObject(forKey: "currentUserId")
        state = .loggedOut

        // Sign out from Firebase too
        phoneAuth.signOut()
    }

    // MARK: - Private

    private func handleAuthResponse(_ response: AuthResponse) {
        keychain.save(response.accessToken, for: .accessToken)
        keychain.save(response.refreshToken, for: .refreshToken)
        keychain.save(response.userId, for: .userId)
        api.setAccessToken(response.accessToken)
        UserDefaults.standard.set(response.userId, forKey: "currentUserId")
        DispatchQueue.main.async {
            self.lastLoginRole = response.role
            self.state = .loggedIn(userId: response.userId)
        }
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
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

        let result = try await Auth.auth().signIn(with: credential)
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
