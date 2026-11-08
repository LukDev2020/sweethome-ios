import Foundation
import CryptoKit
import AuthenticationServices
import UIKit

// MARK: - Sign in with Apple / Alipay
//
// Both are checked by our server, not by Firebase: the phone sends Apple's signed
// identity token (or finishes an Alipay round trip) and gets our own session tokens
// back. A verified Apple / Alipay account with no Lantern Care account yet gets a
// signup token: the person fills in the profile (SignupView), or signs in with
// their phone number to connect it to the account they already have.

/// An Apple / Alipay sign-in the server verified, waiting for a profile (or a link)
struct PendingIdentity: Equatable {
    enum Provider: String { case apple, alipay }
    let provider: Provider
    let signupToken: String
    let suggestedName: String?
    let email: String?
}

enum IdentityOutcome: Equatable {
    case signedIn
    case signupRequired(PendingIdentity)
    /// Alipay hasn't sent the person back to our server yet
    case waiting
}

// MARK: Apple nonce

enum AppleSignInNonce {
    /// A fresh random nonce; Apple gets its SHA-256, the server checks it against this
    static func make(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            return UUID().uuidString + UUID().uuidString
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// "Wei Chen" / "陈伟" from what Apple shares (first sign-in only)
    static func displayName(_ name: PersonNameComponents?) -> String? {
        guard let name else { return nil }
        let formatted = PersonNameComponentsFormatter.localizedString(from: name, style: .default)
            .trimmingCharacters(in: .whitespaces)
        return formatted.isEmpty ? nil : formatted
    }
}

// MARK: Wire types

struct AuthProvidersResponse: Codable, Equatable {
    let phone: Bool
    let apple: Bool
    let alipay: Bool
}

struct AppleSignInRequest: Encodable {
    let identityToken: String
    let rawNonce: String
    let authorizationCode: String?
    let fullName: String?
}

/// POST /v1/auth/apple and /v1/auth/alipay/complete
struct IdentitySignInResponse: Decodable {
    let status: String
    let accessToken: String?
    let refreshToken: String?
    let userId: String?
    let role: String?
    let displayName: String?
    let signupToken: String?
    let email: String?

    var authResponse: AuthResponse? {
        guard status == "signedIn", let accessToken, let refreshToken, let userId else { return nil }
        return AuthResponse(accessToken: accessToken, refreshToken: refreshToken, userId: userId,
                            role: role, displayName: displayName)
    }
}

struct AlipayStartResponse: Codable, Equatable {
    let state: String
    let secret: String
    let authUrl: String
    let alipayAppUrl: String
}

struct AlipayCompleteRequest: Encodable {
    let state: String
    let secret: String
}

struct SignupTokenRequest: Encodable {
    let signupToken: String
}

struct LinkPhoneRequest: Encodable {
    let idToken: String
}

struct LinkPhoneResponse: Decodable {
    let success: Bool
    let phone: String?
}

struct SignInMethodsResponse: Decodable, Equatable {
    let phone: String?
    let apple: Bool
    let alipay: Bool
}

struct LoginLinkingRequest: Codable {
    let idToken: String
    let linkToken: String
}

struct SignupWithIdentityRequest: Codable {
    let signupToken: String
    let displayName: String
    let role: String
    let countryCode: String
    var dataTransferConsent: String? = nil
}

// MARK: Errors

enum IdentitySignInError: LocalizedError, Equatable {
    case appleFailed
    case alipayUnavailable
    case alipayNotConfirmed
    case linkedElsewhere
    case phoneHasAccount
    case expired

    var errorDescription: String? {
        let lang = LanguageManager.shared
        switch self {
        case .appleFailed: return lang.localized("auth.apple.failed")
        case .alipayUnavailable: return lang.localized("auth.alipay.unavailable")
        case .alipayNotConfirmed: return lang.localized("auth.alipay.notConfirmed")
        case .linkedElsewhere: return lang.localized("auth.link.elsewhere")
        case .phoneHasAccount: return lang.localized("auth.phone.hasAccount")
        case .expired: return lang.localized("auth.identity.expired")
        }
    }

    /// The server's error code → what to tell the person
    static func from(_ error: Error) -> Error {
        guard let server = error as? APIServerError else { return error }
        switch server.code {
        case "APPLE_INVALID": return IdentitySignInError.appleFailed
        case "ALIPAY_UNAVAILABLE": return IdentitySignInError.alipayUnavailable
        case "ALIPAY_DENIED", "ALIPAY_UNKNOWN": return IdentitySignInError.alipayNotConfirmed
        case "IDENTITY_LINKED_ELSEWHERE": return IdentitySignInError.linkedElsewhere
        case "PHONE_HAS_ACCOUNT": return IdentitySignInError.phoneHasAccount
        case "LINK_EXPIRED", "SIGNUP_EXPIRED": return IdentitySignInError.expired
        default: return error
        }
    }
}

// MARK: Alipay web sign-in (no Alipay app on the phone)

/// Alipay's authorization page in a sign-in sheet; it ends at shoudeng://auth/alipay
@MainActor
final class AlipayWebSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// true when the page sent the person back (the result is then on the server)
    func run(url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "shoudeng") { callback, _ in
                continuation.resume(returning: callback != nil)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            if !session.start() { continuation.resume(returning: false) }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
