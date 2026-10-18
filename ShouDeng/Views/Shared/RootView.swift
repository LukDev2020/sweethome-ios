import SwiftUI

struct RootView: View {
    #if DEBUG
    private var isScreenshotMode: Bool { ScreenshotCapture.isEnabled }
    #else
    private var isScreenshotMode: Bool { false }
    #endif

    var body: some View {
        if isScreenshotMode {
            #if DEBUG
            ScreenshotGalleryView()
            #endif
        } else {
            AuthenticatedRootView()
        }
    }
}

// MARK: - Authenticated Root View
// Separated so that coordinator observation doesn't interfere with screenshot mode.

private struct AuthenticatedRootView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage("setupWizardComplete") private var setupWizardComplete = false
    @ObservedObject private var biometric = BiometricAuthManager.shared
    @State private var showBiometricPrompt = false

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("-show-onboarding") {
                OnboardingView(isComplete: $onboardingComplete)
            } else if !onboardingComplete {
                // D-05: Disclaimer onboarding before any auth/login
                OnboardingView(isComplete: $onboardingComplete)
                    .transition(.opacity)
            } else {
                switch coordinator.authState {
                case .unknown:
                    splashView
                case .loggedOut:
                    LoginView()
                        .sheet(isPresented: $coordinator.showSignup) {
                            SignupView()
                        }
                case .loggedIn:
                    if biometric.isEnabled && !biometric.isUnlocked {
                        BiometricGateView()
                    } else if !setupWizardComplete && coordinator.showSetupWizard {
                        PostSignupWizardView(onComplete: {
                            setupWizardComplete = true
                            coordinator.showSetupWizard = false
                        })
                        .environmentObject(coordinator)
                    } else {
                        ZStack(alignment: .top) {
                            switch coordinator.userRole {
                            case .protected_:
                                ProtectedTabView()
                            case .guardian:
                                GuardianTabView()
                            }
                            VStack(spacing: 0) {
                                betaBanner
                                DegradationBannerView()
                                    .environmentObject(coordinator)
                            }
                        }
                        .sheet(isPresented: $showBiometricPrompt) {
                            BiometricEnablePromptView(isPresented: $showBiometricPrompt)
                        }
                        .onAppear {
                            // After login, offer biometric setup if available (skip if wizard already handled it)
                            if biometric.isAvailable && !biometric.hasShownPrompt && !biometric.isEnabled && setupWizardComplete {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    showBiometricPrompt = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Beta Banner

    @ViewBuilder
    private var betaBanner: some View {
        #if BETA
        HStack(spacing: 6) {
            Image(systemName: "hammer.fill")
                .font(.caption)
            Text("TestFlight 测试版")
                .font(.caption.bold())
            Text("· SOS/跌倒升级走模拟通道")
                .font(.caption2)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.orange)
        #endif
    }

    // MARK: - Splash

    private var splashView: some View {
        VStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("守灯")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
