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
        #if DEBUG
        if UserDefaults.standard.string(forKey: "lockscreen-shot") != nil { return .dark } // white status bar
        #endif
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
                // `-rider-mock`: Rider mode design mock (see RiderModeMock.swift)
                .overlay { if ProcessInfo.processInfo.arguments.contains("-rider-mock") { RiderModeMock() } }
                // `-lockscreen-shot protected|guardian`: a lock screen with the Live Activity card
                .overlay {
                    if let role = UserDefaults.standard.string(forKey: "lockscreen-shot") {
                        LockScreenShot(guardian: role == "guardian")
                    }
                }
                // `-setup-shot care,work,guardian`: the setup after sign-up for those sides, on
                // its own (nothing is saved: buttons that call the server just fail quietly)
                .overlay {
                    if let sides = UserDefaults.standard.string(forKey: "setup-shot") {
                        let set = Set(sides.split(separator: ","))
                        RiderSetupView(steps: RiderSetupStep.signupFlow(family: set.contains("care"), work: set.contains("work"),
                                                                       guardian: set.contains("guardian")),
                                       start: .home)
                            .environmentObject(appDelegate.appCoordinator)
                    }
                }
                // `-plans-shot`: the plans screen on its own (App Store / IAP review screenshots)
                .overlay {
                    if ProcessInfo.processInfo.arguments.contains("-plans-shot") {
                        NavigationStack { GuardianPlanBillingView() }
                            .environmentObject(appDelegate.appCoordinator)
                    }
                }
                // `-settings-free-plan`: the Settings plan card of a family without a plan,
                // for both roles (the demo family always has one)
                .overlay {
                    if ProcessInfo.processInfo.arguments.contains("-settings-free-plan") {
                        SettingsPlanCardGallery()
                            .environmentObject(appDelegate.appCoordinator)
                    }
                }
                // `-liveTrackSim`: Live Track on its own, recording on this phone only (nothing
                // sent) — drive it with `xcrun simctl location <udid> run "City Bicycle Ride"`
                .overlay {
                    if ProcessInfo.processInfo.arguments.contains("-liveTrackSim") {
                        LiveTrackSimulation()
                            .environmentObject(appDelegate.appCoordinator)
                    }
                }
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

#if DEBUG
/// Simulator test harness for the live track and the PDF report
private struct LiveTrackSimulation: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        LiveTrackView(recorder: coordinator.tripRecordingService)
            .background(Color(.systemBackground))
            .task {
                coordinator.locationManager.start()
                coordinator.tripRecordingService.startLocalRecording()
                // The coordinator turns trip GPS on when a recording starts; be explicit here
                coordinator.locationManager.setTripRecording(true)
            }
    }
}
#endif
