import SwiftUI

struct RootView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some View {
        Group {
            switch coordinator.authManager.state {
            case .unknown:
                // Splash / loading
                splashView

            case .loggedOut:
                // Auth flow
                LoginView()
                    .sheet(isPresented: $coordinator.showSignup) {
                        SignupView()
                    }

            case .loggedIn:
                // Authenticated — check onboarding
                if !onboardingComplete {
                    OnboardingView(isComplete: $onboardingComplete)
                } else {
                    ZStack(alignment: .top) {
                        Group {
                            switch coordinator.userRole {
                            case .protected_:
                                ProtectedTabView()
                            case .guardian:
                                GuardianTabView()
                            }
                        }
                        // Dev-only: long press anywhere to switch portal
                        .overlay(alignment: .topTrailing) {
                            portalSwitcher
                        }

                        // Degradation banner
                        DegradationBannerView()
                            .environmentObject(coordinator)
                    }
                }
            }
        }
    }

    // MARK: - Splash

    private var splashView: some View {
        VStack(spacing: 12) {
            Image(systemName: "light.beacon.max")
                .font(.system(size: 48))
                .foregroundStyle(Color(red: 232/255, green: 163/255, blue: 61/255))
            Text("守灯")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(Color(red: 18/255, green: 32/255, blue: 58/255))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Portal Switcher (development tool)

    private var portalSwitcher: some View {
        Menu {
            Button {
                withAnimation { coordinator.userRole = .protected_ }
            } label: {
                Label("被守护者", systemImage: "shield.fill")
            }
            Button {
                withAnimation { coordinator.userRole = .guardian }
            } label: {
                Label("守护者", systemImage: "eye.fill")
            }
            Divider()
            Button(role: .destructive) {
                coordinator.authManager.logout()
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: coordinator.userRole == .protected_ ? "shield.fill" : "eye.fill")
                    .font(.system(size: 10))
                Text(coordinator.userRole == .protected_ ? "被守护" : "守护者")
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .padding(.top, 54)
        .padding(.trailing, 16)
    }
}
