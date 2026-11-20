import Foundation
import AuthenticationServices
import UIKit

// MARK: - Sign in with Apple / Alipay (login screen, signup, Settings)
//
// Signed in → the usual login flow runs (authManager.state). No account yet →
// signup opens at the profile step with the verified identity; from there the
// person can also sign in with their phone number to connect it to an account
// they already have.

extension AppCoordinator {

    // MARK: Apple

    /// The Sign in with Apple button's answer
    @MainActor
    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>, rawNonce: String, connecting: Bool = false) async {
        identitySignInError = nil
        switch result {
        case .failure(let error):
            // Closing Apple's sheet is not an error
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            // Apple's own code (e.g. 1000) so a report from a tester can be traced
            let ns = error as NSError
            identitySignInError = IdentitySignInError.appleFailed.localizedDescription + " (Apple \(ns.code))"
            print("[Auth] Sign in with Apple failed on the phone: \(ns.domain) \(ns.code) \(ns.localizedDescription)")
            return
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                identitySignInError = IdentitySignInError.appleFailed.localizedDescription + " (no token)"
                return
            }
            let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            do {
                if connecting {
                    try await authManager.connectApple(identityToken: identityToken, rawNonce: rawNonce, authorizationCode: code)
                } else {
                    let outcome = try await authManager.signInWithApple(
                        identityToken: identityToken, rawNonce: rawNonce, authorizationCode: code,
                        fullName: AppleSignInNonce.displayName(credential.fullName))
                    continueAfter(outcome)
                }
            } catch {
                identitySignInError = error.localizedDescription
                print("[Auth] Sign in with Apple: the server step failed: \(error)")
            }
        }
    }

    // MARK: Alipay

    /// "Sign in with Alipay": the Alipay app when installed, else Alipay's web page
    @MainActor
    func startAlipaySignIn(connecting: Bool = false) async {
        identitySignInError = nil
        alipayConnecting = connecting
        let start: AlipayStartResponse
        do {
            start = try await authManager.startAlipaySignIn()
        } catch {
            identitySignInError = error.localizedDescription
            return
        }
        if let appURL = URL(string: start.alipayAppUrl), let probe = URL(string: "alipays://"),
           UIApplication.shared.canOpenURL(probe) {
            alipayWaiting = true
            _ = await UIApplication.shared.open(appURL)
            return
        }
        guard let webURL = URL(string: start.authUrl) else { return }
        alipayWaiting = true
        let returned = await AlipayWebSignIn().run(url: webURL)
        if returned {
            await finishAlipaySignIn(quiet: false)
        } else {
            // Sheet closed: the person may still have agreed just before
            await finishAlipaySignIn(quiet: true)
        }
    }

    /// Back from Alipay (its "back" link, the web sheet, or the app coming to the front).
    /// `quiet`: nobody tapped anything — no error if Alipay simply hasn't answered.
    @MainActor
    func finishAlipaySignIn(quiet: Bool) async {
        guard authManager.pendingAlipay != nil else { alipayWaiting = false; return }
        do {
            let outcome = try await authManager.completeAlipaySignIn(connecting: alipayConnecting)
            if outcome == .waiting {
                // Still on Alipay's side: keep waiting (the screen offers "Check again" / Cancel)
                if quiet { return }
                // The link came back first; Alipay's answer is moments behind
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                let again = try await authManager.completeAlipaySignIn(connecting: alipayConnecting)
                if again == .waiting { return }
                finishAlipay(again)
                return
            }
            finishAlipay(outcome)
        } catch {
            alipayWaiting = false
            identitySignInError = error.localizedDescription
        }
    }

    @MainActor
    func cancelAlipaySignIn() {
        authManager.cancelAlipaySignIn()
        alipayWaiting = false
        alipayConnecting = false
    }

    @MainActor
    private func finishAlipay(_ outcome: IdentityOutcome) {
        alipayWaiting = false
        if alipayConnecting {
            alipayConnecting = false
            alipayJustConnected = true
            return
        }
        continueAfter(outcome)
    }

    // MARK: Shared

    @MainActor
    private func continueAfter(_ outcome: IdentityOutcome) {
        switch outcome {
        case .signedIn, .waiting:
            break   // signed in: authManager.state drives the login flow
        case .signupRequired:
            // Profile step, with the verified Apple / Alipay account
            showSignup = true
        }
    }

    /// Signup → "I already have an account": sign in with the phone number instead,
    /// which connects this Apple / Alipay sign-in to that account.
    @MainActor
    func connectPendingIdentityByPhone() {
        showSignup = false
    }
}
