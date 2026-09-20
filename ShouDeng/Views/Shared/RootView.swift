import SwiftUI

struct RootView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    // TEMP: Set to true to bypass login during development
    private let devBypassLogin = false

    var body: some View {
        Group {
            if devBypassLogin {
                // DEV BYPASS: skip login and onboarding
                ZStack(alignment: .top) {
                    switch coordinator.userRole {
                    case .protected_:
                        ProtectedTabView()
                    case .guardian:
                        GuardianTabView()
                    }
                    DegradationBannerView()
                        .environmentObject(coordinator)
                }
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
                    if !onboardingComplete {
                        OnboardingView(isComplete: $onboardingComplete)
                    } else {
                        ZStack(alignment: .top) {
                            switch coordinator.userRole {
                            case .protected_:
                                ProtectedTabView()
                            case .guardian:
                                GuardianTabView()
                            }
                            DegradationBannerView()
                                .environmentObject(coordinator)
                        }
                    }
                }
            }
        }
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
