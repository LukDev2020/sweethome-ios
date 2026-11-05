import SwiftUI
import FirebaseAuth

@main
struct ShouDengApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage("app_dark_mode") private var darkModeEnabled = false
    @ObservedObject private var explore = ExploreModeController.shared

    /// Decided here, at the top: an inner preferredColorScheme loses to an outer one.
    /// Explore Mode is light; onboarding is drawn dark (a light scheme left the status
    /// bar black on black); otherwise the in-app dark mode setting.
    private var colorScheme: ColorScheme {
        if explore.isActive { return .light }
        let onboarding = !onboardingComplete || ProcessInfo.processInfo.arguments.contains("-show-onboarding")
        return darkModeEnabled || onboarding ? .dark : .light
    }

    init() {
        AppTips.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appDelegate.appCoordinator)
                #if DEBUG
                // `-la-gallery`: the lock-screen cards, all four states (see LockScreenCards.swift)
                .overlay { if ProcessInfo.processInfo.arguments.contains("-la-gallery") { LockScreenCardGallery() } }
                #endif
                .preferredColorScheme(colorScheme)
                // Firebase phone-auth reCAPTCHA callback + shoudeng:// deep links
                .onOpenURL { url in
                    if AppDelegate.firebaseConfigured, Auth.auth().canHandle(url) { return }
                    appDelegate.appCoordinator.handleDeepLink(url)
                }
                // Universal links (invites)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    appDelegate.appCoordinator.handleUserActivity(activity)
                }
                #if BETA
                // A Beta binary installed from the App Store must behave like Release
                .task { await BuildChannel.shared.refreshInstallEnvironment() }
                #endif
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            let coordinator = appDelegate.appCoordinator
            AppLifecycleRouter(
                onBecameActive: { coordinator.sceneDidBecomeActive() },
                onResignedActive: { coordinator.sceneWillResignActive() }
            ).handle(from: oldPhase, to: newPhase)
        }
    }
}
