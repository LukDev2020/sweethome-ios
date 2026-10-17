#if DEBUG
import SwiftUI

// MARK: - Screenshot Gallery
//
// Minimal version: cycles through views without mutating coordinator.
// Uses simctl screenshot externally to capture each phase.

struct ScreenshotGalleryView: View {
    @State private var phaseIndex = 0

    private let labels = [
        "Guardian Home", "Guardian Feed", "Guardian Records", "Guardian Settings",
        "Protected Home", "Protected Feed", "Protected Coverage", "Protected Records", "Protected Settings",
        "Login", "Onboarding 1", "Onboarding 2", "Onboarding 3"
    ]

    var body: some View {
        ZStack {
            screenView
        }
        .task {
            // Auto-advance through phases
            for i in 0..<labels.count {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                phaseIndex = i
                print("[Screenshot] Showing phase \(i): \(labels[i])")
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            phaseIndex = labels.count
            print("[Screenshot] Done — \(labels.count) phases shown")
        }
    }

    @ViewBuilder
    private var screenView: some View {
        switch phaseIndex {
        case 0: OnboardingScreenshot(page: 0)
        case 1: OnboardingScreenshot(page: 1)
        case 2: OnboardingScreenshot(page: 2)
        case 3: LoginView()
        case 4: GuardianTabViewFixed(selectedTab: 0)
        case 5: GuardianTabViewFixed(selectedTab: 1)
        case 6: GuardianTabViewFixed(selectedTab: 2)
        case 7: GuardianTabViewFixed(selectedTab: 3)
        case 8: ProtectedTabViewFixed(selectedTab: 0)
        case 9: ProtectedTabViewFixed(selectedTab: 1)
        case 10: ProtectedTabViewFixed(selectedTab: 2)
        case 11: ProtectedTabViewFixed(selectedTab: 3)
        case 12: ProtectedTabViewFixed(selectedTab: 4)
        default:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("All \(labels.count) screens captured")
                    .font(.headline)
            }
        }
    }
}

// MARK: - Fixed-Tab Versions

struct GuardianTabViewFixed: View {
    let selectedTab: Int
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    var body: some View {
        TabView(selection: .constant(selectedTab)) {
            GuardianHomeView()
                .tabItem { Label("首页", systemImage: "eye.fill") }
                .tag(0)
            FamilyFeedView()
                .tabItem { Label("家庭圈", systemImage: "bubble.left.and.bubble.right") }
                .tag(1)
            GuardianRecordsView()
                .tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }
                .tag(2)
            GuardianSettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(3)
        }
        .tint(pro)
    }
}

struct ProtectedTabViewFixed: View {
    let selectedTab: Int
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    var body: some View {
        TabView(selection: .constant(selectedTab)) {
            ProtectedHomeView()
                .tabItem { Label("首页", systemImage: "shield.fill") }
                .tag(0)
            FamilyFeedView()
                .tabItem { Label("家庭圈", systemImage: "heart.text.square") }
                .tag(1)
            ProtectedCoverageView()
                .tabItem { Label("覆盖", systemImage: "globe.americas") }
                .tag(2)
            ProtectedRecordsView()
                .tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }
                .tag(3)
            ProtectedSettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(4)
        }
        .tint(safe)
    }
}

// MARK: - Onboarding Screenshot

struct OnboardingScreenshot: View {
    let page: Int
    @ObservedObject private var lang = LanguageManager.shared

    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    private var screens: [DisclaimerCopy.Onboarding.Screen] {
        DisclaimerCopy.Onboarding.screens(for: lang.current)
    }

    var body: some View {
        ZStack {
            inkDeep.ignoresSafeArea(.all, edges: .all)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(0..<screens.count, id: \.self) { i in
                        Circle()
                            .fill(i <= page ? lamp : lamp.opacity(0.25))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 60)
                Spacer().frame(maxHeight: 60)
                Image(systemName: screens[page].icon)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(lamp)
                    .frame(height: 60)
                Text(screens[page].title)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
                Text(screens[page].body)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
                Spacer()
                Text(screens[page].buttonTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(inkDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(lamp)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .padding(.bottom, 48)
            }
            .padding(.horizontal, 28)
        }
    }
}
#endif
