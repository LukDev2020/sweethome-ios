#if DEBUG
import SwiftUI

// MARK: - Screenshot Gallery
//
// Auto-cycles through all app screens, capturing each one.
// Activated when app is launched with -screenshot argument.
// Shows Guardian tabs, then Protected tabs, then auth screens.

struct ScreenshotGalleryView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var capture = ScreenshotCapture.shared
    @State private var phase: Phase = .guardianHome
    @State private var isCapturing = false

    enum Phase: Int, CaseIterable {
        // Guardian role
        case guardianHome = 0
        case guardianFeed
        case guardianRecords
        case guardianSettings
        // Protected role
        case protectedHome
        case protectedFeed
        case protectedCoverage
        case protectedRecords
        case protectedSettings
        // Auth screens
        case login
        case onboarding1
        case onboarding2
        case onboarding3
        // Done
        case done

        var label: String {
            switch self {
            case .guardianHome:     return "Guardian_01_Home"
            case .guardianFeed:     return "Guardian_02_FamilyFeed"
            case .guardianRecords:  return "Guardian_03_Records"
            case .guardianSettings: return "Guardian_04_Settings"
            case .protectedHome:    return "Protected_01_Home"
            case .protectedFeed:    return "Protected_02_FamilyFeed"
            case .protectedCoverage:return "Protected_03_Coverage"
            case .protectedRecords: return "Protected_04_Records"
            case .protectedSettings:return "Protected_05_Settings"
            case .login:            return "Auth_01_Login"
            case .onboarding1:      return "Auth_02_Onboarding_NotEmergency"
            case .onboarding2:      return "Auth_03_Onboarding_Privacy"
            case .onboarding3:      return "Auth_04_Onboarding_Control"
            case .done:             return "done"
            }
        }

        var filePath: String {
            switch self {
            case .guardianHome:     return "Views/Guardian/GuardianHomeView.swift"
            case .guardianFeed:     return "Views/Shared/FamilyFeedView.swift"
            case .guardianRecords:  return "Views/Guardian/GuardianRecordsView.swift"
            case .guardianSettings: return "Views/Guardian/GuardianSettingsView.swift"
            case .protectedHome:    return "Views/Protected/ProtectedHomeView.swift"
            case .protectedFeed:    return "Views/Shared/FamilyFeedView.swift"
            case .protectedCoverage:return "Views/Protected/ProtectedCoverageView.swift"
            case .protectedRecords: return "Views/Protected/ProtectedRecordsView.swift"
            case .protectedSettings:return "Views/Protected/ProtectedSettingsView.swift"
            case .login:            return "Views/Auth/LoginView.swift"
            case .onboarding1:      return "Views/Shared/OnboardingView.swift"
            case .onboarding2:      return "Views/Shared/OnboardingView.swift"
            case .onboarding3:      return "Views/Shared/OnboardingView.swift"
            case .done:             return ""
            }
        }
    }

    var body: some View {
        ZStack {
            currentScreen
                .environmentObject(coordinator)

            // Capture overlay
            if phase == .done {
                VStack {
                    Spacer()
                    Text("All \(capture.capturedCount) screenshots captured!")
                        .font(.headline)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Spacer()
                }
            }
        }
        .onAppear {
            startCaptureCycle()
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch phase {
        // Guardian screens
        case .guardianHome:
            guardianTabAt(0)
        case .guardianFeed:
            guardianTabAt(1)
        case .guardianRecords:
            guardianTabAt(2)
        case .guardianSettings:
            guardianTabAt(3)
        // Protected screens
        case .protectedHome:
            protectedTabAt(0)
        case .protectedFeed:
            protectedTabAt(1)
        case .protectedCoverage:
            protectedTabAt(2)
        case .protectedRecords:
            protectedTabAt(3)
        case .protectedSettings:
            protectedTabAt(4)
        // Auth screens
        case .login:
            LoginView()
        case .onboarding1:
            onboardingAtPage(0)
        case .onboarding2:
            onboardingAtPage(1)
        case .onboarding3:
            onboardingAtPage(2)
        case .done:
            Color.black
        }
    }

    private func guardianTabAt(_ tab: Int) -> some View {
        // Set role to guardian for proper data
        let _ = { coordinator.userRole = .guardian }()
        return GuardianTabViewFixed(selectedTab: tab)
    }

    private func protectedTabAt(_ tab: Int) -> some View {
        let _ = { coordinator.userRole = .protected_ }()
        return ProtectedTabViewFixed(selectedTab: tab)
    }

    private func onboardingAtPage(_ page: Int) -> some View {
        OnboardingScreenshot(page: page)
    }

    private func startCaptureCycle() {
        // Wait for initial render, then start capturing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            captureAndAdvance()
        }
    }

    private func captureAndAdvance() {
        guard phase != .done else {
            capture.generatePDF()
            return
        }

        // Before guardian screens, set guardian role
        if phase == .guardianHome {
            coordinator.userRole = .guardian
        }
        // Before protected screens, set protected role
        if phase == .protectedHome {
            coordinator.userRole = .protected_
        }

        // Wait for render, then capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            capture.capture(name: phase.label, filePath: phase.filePath)

            // Advance to next phase
            let allCases = Phase.allCases
            if let currentIndex = allCases.firstIndex(of: phase),
               currentIndex + 1 < allCases.count {
                phase = allCases[currentIndex + 1]

                // Role switch needs time to propagate
                let delay: Double = (phase == .protectedHome || phase == .login) ? 2.0 : 1.5
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    captureAndAdvance()
                }
            }
        }
    }
}

// MARK: - Fixed-Tab Versions (for screenshot capture)

struct GuardianTabViewFixed: View {
    let selectedTab: Int
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    var body: some View {
        TabView(selection: .constant(selectedTab)) {
            GuardianHomeView()
                .tabItem {
                    Image(systemName: "eye.fill")
                    Text("首页")
                }
                .tag(0)

            FamilyFeedView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("家庭圈")
                }
                .tag(1)

            GuardianRecordsView()
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("记录")
                }
                .tag(2)

            GuardianSettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("设置")
                }
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
                .tabItem {
                    Image(systemName: "shield.fill")
                    Text("首页")
                }
                .tag(0)

            FamilyFeedView()
                .tabItem {
                    Image(systemName: "heart.text.square")
                    Text("家庭圈")
                }
                .tag(1)

            ProtectedCoverageView()
                .tabItem {
                    Image(systemName: "globe.americas")
                    Text("覆盖")
                }
                .tag(2)

            ProtectedRecordsView()
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("记录")
                }
                .tag(3)

            ProtectedSettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("设置")
                }
                .tag(4)
        }
        .tint(safe)
    }
}

// MARK: - Onboarding Screenshot (specific page)

struct OnboardingScreenshot: View {
    let page: Int
    @ObservedObject private var lang = LanguageManager.shared

    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    private var screens: [DisclaimerCopy.Onboarding.Screen] {
        DisclaimerCopy.Onboarding.screens(for: lang.current)
    }

    var body: some View {
        ZStack {
            inkDeep.ignoresSafeArea(.all, edges: .all)

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<screens.count, id: \.self) { i in
                        Circle()
                            .fill(i <= page ? lamp : lamp.opacity(0.25))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 60)

                Spacer().frame(maxHeight: 60)

                // Icon
                Image(systemName: screens[page].icon)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(lamp)
                    .frame(height: 60)

                // Title
                Text(screens[page].title)
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                // Body
                Text(screens[page].body)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)

                Spacer()

                // Button
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
