import SwiftUI

struct RootView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    // TEMP: Set to true to bypass login during development
    private let devBypassLogin = true

    var body: some View {
        Group {
            if devBypassLogin {
                // DEV BYPASS: skip login and onboarding
                ZStack(alignment: .top) {
                    Group {
                        switch coordinator.userRole {
                        case .protected_:
                            ProtectedTabView()
                        case .guardian:
                            GuardianTabView()
                        }
                    }
                    #if DEBUG
                    .overlay(alignment: .topTrailing) {
                        portalSwitcher
                    }
                    #endif
                    DegradationBannerView()
                        .environmentObject(coordinator)
                }
            } else {
                switch coordinator.authManager.state {
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
                            Group {
                                switch coordinator.userRole {
                                case .protected_:
                                    ProtectedTabView()
                                case .guardian:
                                    GuardianTabView()
                                }
                            }
                            #if DEBUG
                            .overlay(alignment: .topTrailing) {
                                portalSwitcher
                            }
                            #endif
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

    #if DEBUG
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
    #endif
}
