import SwiftUI
import FirebaseAuth

@main
struct ShouDengApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage("onboarding_copy_version") private var onboardingCopyVersion = ""
    @AppStorage("app_dark_mode") private var darkModeEnabled = false
    /// Set by RootView while login / Face ID / setup wizard is on screen
    @AppStorage("ui_light_only_screen") private var lightOnlyScreen = false
    @ObservedObject private var explore = ExploreModeController.shared

    /// Decided here, at the top: an inner preferredColorScheme loses to an outer one.
    /// Onboarding is drawn dark (a light scheme left the status bar black on black);
    /// otherwise — the demo included — the in-app dark mode setting.
    private var colorScheme: ColorScheme {
        if explore.isActive { return darkModeEnabled ? .dark : .light }
        let onboarding = !onboardingComplete || onboardingCopyVersion != DisclaimerCopy.Onboarding.version
            || ProcessInfo.processInfo.arguments.contains("-show-onboarding")
        if onboarding { return .dark }
        return darkModeEnabled && !lightOnlyScreen ? .dark : .light
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
