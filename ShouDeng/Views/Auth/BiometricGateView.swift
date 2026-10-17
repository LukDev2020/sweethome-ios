import SwiftUI

// MARK: - Biometric Gate View
//
// Shown on app launch when the user has an active session and biometric
// login is enabled. Prompts Face ID / Touch ID automatically.
// Fallback: "使用验证码登录" logs out and shows the OTP login page.

struct BiometricGateView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var biometric = BiometricAuthManager.shared

    private let navy = Color(red: 1/255, green: 69/255, blue: 129/255)
    private let blue = Color(red: 61/255, green: 154/255, blue: 192/255)
    private let bg = Color(red: 251/255, green: 248/255, blue: 241/255)
    private let ink2 = Color(red: 14/255, green: 43/255, blue: 74/255).opacity(0.62)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea(.all, edges: .all)

            VStack(spacing: 0) {
                Spacer()

                // Logo
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [blue.opacity(0.16), blue.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)

                    VStack(spacing: 10) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Text(Brand.displayTitle(locale: LanguageManager.shared.current))
                            .font(.system(size: 29, weight: .black, design: .serif))
                            .foregroundStyle(navy)
                            .tracking(1.5)
                    }
                }

                // Biometric tap target
                Button {
                    Task { await attemptBiometric() }
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: biometric.biometricIconName)
                            .font(.system(size: 44))
                            .foregroundStyle(navy.opacity(0.7))

                        Text("轻触以\(biometric.biometricName)解锁")
                            .font(.system(size: 14))
                            .foregroundStyle(ink2)
                    }
                }
                .padding(.top, 40)

                Spacer()

                // Fallback
                Button {
                    biometric.disable()
                    coordinator.authManager.logout()
                } label: {
                    Text("使用验证码登录")
                        .font(.system(size: 13))
                        .foregroundStyle(ink2)
                        .underline()
                }
                .padding(.bottom, 48)
            }
        }
        .task {
            await attemptBiometric()
        }
    }

    @MainActor
    private func attemptBiometric() async {
        let result = await biometric.authenticate()
        switch result {
        case .success:
            break // isUnlocked is now true, RootView reacts
        case .biometricsChanged:
            coordinator.authManager.logout()
        case .cancelled, .failed:
            break // User can tap to retry or use fallback
        }
    }
}
