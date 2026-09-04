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
    @State private var currentPage = 0

    // Design system
    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let paper = Color(red: 236/255, green: 238/255, blue: 240/255)

    private let screens = DisclaimerCopy.Onboarding.screens

    var body: some View {
        ZStack {
            inkDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                progressDots
                    .padding(.top, 20)

                Spacer()

                // Content
                screenContent(screens[currentPage])

                Spacer()

                // Action button
                actionButton(screens[currentPage])
                    .padding(.bottom, 48)
            }
            .padding(.horizontal, 28)
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

            // Body
            Text(screen.body)
                .font(.system(size: 14.5))
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
