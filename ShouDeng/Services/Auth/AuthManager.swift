import Foundation
import Combine

// MARK: - Auth Manager
//
// Manages authentication state: login, signup, token refresh, logout.
// Publishes auth state so RootView can decide what to show.

final class AuthManager: ObservableObject {

    enum AuthState: Equatable {
        case unknown       // App just launched, checking keychain
        case loggedOut
        case loggedIn(userId: String)
    }

    @Published var state: AuthState = .unknown

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

    init(api: APIClient) {
        self.api = api
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

    // MARK: - Login

    func login(phone: String, code: String) async throws {
        let response: AuthResponse = try await api.post(
            "/v1/auth/login",
            body: LoginRequest(phone: phone, verificationCode: code)
        )
        handleAuthResponse(response)
    }

    // MARK: - Signup

    func signup(phone: String, code: String, displayName: String, role: String) async throws {
        let response: AuthResponse = try await api.post(
            "/v1/auth/signup",
            body: SignupRequest(
                phone: phone,
                verificationCode: code,
                displayName: displayName,
                role: role
            )
        )
        handleAuthResponse(response)
    }

    // MARK: - Request Verification Code

    func requestCode(phone: String) async throws {
        let _: EmptyResponse = try await api.post(
            "/v1/auth/send-code",
            body: SendCodeRequest(phone: phone)
        )
    }

    // MARK: - Token Refresh

    func refreshToken() async throws {
        guard let refreshToken = keychain.read(.refreshToken) else {
            await MainActor.run { state = .loggedOut }
            throw APIError.unauthorized
        }
        let response: AuthResponse = try await api.post(
            "/v1/auth/refresh",
            body: RefreshRequest(refreshToken: refreshToken)
        )
        handleAuthResponse(response)
    }

    // MARK: - Logout

    func logout() {
        keychain.deleteAll()
        api.setAccessToken(nil)
        UserDefaults.standard.removeObject(forKey: "currentUserId")
        state = .loggedOut
    }

    // MARK: - Private

    private func handleAuthResponse(_ response: AuthResponse) {
        keychain.save(response.accessToken, for: .accessToken)
        keychain.save(response.refreshToken, for: .refreshToken)
        keychain.save(response.userId, for: .userId)
        api.setAccessToken(response.accessToken)
        UserDefaults.standard.set(response.userId, forKey: "currentUserId")
        DispatchQueue.main.async {
            self.state = .loggedIn(userId: response.userId)
        }
    }
}

// MARK: - Request/Response Types

struct LoginRequest: Codable {
    let phone: String
    let verificationCode: String
}

struct SignupRequest: Codable {
    let phone: String
    let verificationCode: String
    let displayName: String
    let role: String
}

struct SendCodeRequest: Codable {
    let phone: String
}

struct RefreshRequest: Codable {
    let refreshToken: String
}

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let userId: String
}

struct EmptyResponse: Codable {}
