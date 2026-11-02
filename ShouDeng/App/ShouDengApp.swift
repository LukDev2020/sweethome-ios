import SwiftUI
import FirebaseAuth

@main
struct ShouDengApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

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
                .preferredColorScheme(.light)
                // Firebase phone-auth reCAPTCHA callback + shoudeng:// deep links
                .onOpenURL { url in
                    if AppDelegate.firebaseConfigured, Auth.auth().canHandle(url) { return }
                    appDelegate.appCoordinator.handleDeepLink(url)
                }
                // Universal links (invites)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    appDelegate.appCoordinator.handleUserActivity(activity)
                }
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
