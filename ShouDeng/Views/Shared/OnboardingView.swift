import SwiftUI

// MARK: - Onboarding: 3-Screen Disclosure Flow
//
// From revised plan, section 5.3:
//   - One concept per screen, not a single large popup
//   - Button text "我明白了" not "确定"
//   - Cannot be skipped
//   - Each tap logs consent with copy version

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage("hasCompletedOnboardingOnce") private var hasCompletedOnce = false
    @State private var currentPage = UserDefaults.standard.integer(forKey: "debug_onboarding_page")
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Design system
    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let paper = Color(red: 236/255, green: 238/255, blue: 240/255)

    private var screens: [DisclaimerCopy.Onboarding.Screen] {
        DisclaimerCopy.Onboarding.screens(for: lang.current)
    }

    var body: some View {
        ZStack {
            inkDeep.ignoresSafeArea(.all, edges: .all)

            if sizeClass == .regular {
                duoOnboardingLayout
            } else {
                compactOnboardingLayout
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Compact Layout

    private var compactOnboardingLayout: some View {
        VStack(spacing: 0) {
            onboardingTopBar
            progressDots
                .padding(.top, 4)
            Spacer()
                .frame(maxHeight: 60)
            screenContent(screens[currentPage])
            Spacer()
            actionButton(screens[currentPage])
                .padding(.bottom, 48)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Duo Layout (Inner Screen)

    private var duoOnboardingLayout: some View {
        HStack(spacing: 0) {
            // LEFT: Icon + Title
            VStack(spacing: 0) {
                onboardingTopBar
                    .padding(.horizontal, 28)
                progressDots
                    .padding(.top, 4)
                Spacer()
                Image(systemName: screens[currentPage].icon)
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(lamp)
                    .frame(height: 70)
                Text(screens[currentPage].title)
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .padding(.horizontal, 32)
                Spacer()
                Spacer()
            }
            .frame(width: 445)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)

            // RIGHT: Body + Button
            VStack(spacing: 0) {
                Spacer()
                Text(screens[currentPage].body)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 36)
                Spacer()
                actionButton(screens[currentPage])
                    .padding(.horizontal, 36)
                    .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Shared Top Bar

    private var onboardingTopBar: some View {
        HStack {
            HStack(spacing: 2) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Button {
                        lang.current = language
                    } label: {
                        Text(language.displayName)
                            .font(.system(size: 12))
                            .foregroundStyle(lang.current == language ? .white : .white.opacity(0.35))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                lang.current == language
                                    ? Capsule().fill(.white.opacity(0.15))
                                    : nil
                            )
                    }
                }
            }
            .padding(.leading, 16)

            Spacer()

            if hasCompletedOnce {
                Button {
                    skipToHome()
                } label: {
                    Text(lang.current == .chinese ? "跳过" : "Skip")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.top, 8)
        .padding(.trailing, 4)
    }

    private func skipToHome() {
        coordinator.locationManager.start()
        coordinator.heartbeatService.start()
        coordinator.pushService.registerForPushNotifications()
        coordinator.deviceHealthMonitor.beginMonitoring()
        withAnimation {
            isComplete = true
        }
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<screens.count, id: \.self) { i in
                Circle()
                    .fill(i <= currentPage ? lamp : lamp.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
    }

    // MARK: - Screen Content

    private func screenContent(_ screen: DisclaimerCopy.Onboarding.Screen) -> some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: screen.icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(lamp)
                .frame(height: 60)

            // Title
            Text(screen.title)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            // Body
            Text(screen.body)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.75))
                .lineSpacing(6)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Action Button

    private func actionButton(_ screen: DisclaimerCopy.Onboarding.Screen) -> some View {
        Button {
            // Log consent
            ConsentLogger.shared.logOnboardingScreen(screen.id)

            if currentPage < screens.count - 1 {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPage += 1
                }
            } else {
                // Start services now that user has been informed
                hasCompletedOnce = true
                coordinator.locationManager.start()
                coordinator.heartbeatService.start()
                coordinator.pushService.registerForPushNotifications()
                coordinator.deviceHealthMonitor.beginMonitoring()
                withAnimation {
                    isComplete = true
                }
            }
        } label: {
            Text(screen.buttonTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(inkDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(lamp)
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
    }
}
