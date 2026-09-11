import UIKit
import UserNotifications
import FirebaseCore
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {

    let appCoordinator = AppCoordinator()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // Initialize Firebase (only if GoogleService-Info.plist has real values)
        if Self.hasValidFirebaseConfig() {
            FirebaseApp.configure()

            #if DEBUG
            print("[Firebase] Configured for project: \(FirebaseApp.app()?.options.projectID ?? "unknown")")
            #endif
        }

        // Install crash reporter immediately
        appCoordinator.crashReporter.install()
        appCoordinator.crashReporter.uploadPendingCrashes(using: appCoordinator.apiClient)

        // Defer all permission-requiring services until after onboarding
        if UserDefaults.standard.bool(forKey: "onboardingComplete") {
            startServices(application)
        }

        // Check if launched from significant location change
        if launchOptions?[.location] != nil {
            appCoordinator.heartbeatService.significantLocationChanged(
                location: Location(
                    latitude: 0, longitude: 0, accuracy: 0,
                    altitude: nil, speed: nil, timestamp: Date(),
                    address: nil, isInSafeZone: nil, safeZoneName: nil
                )
            )
        }

        return true
    }

    func startServices(_ application: UIApplication) {
        appCoordinator.pushService.registerForPushNotifications()
        application.registerForRemoteNotifications()
        appCoordinator.heartbeatService.start()
        appCoordinator.locationManager.start()
        appCoordinator.deviceHealthMonitor.beginMonitoring()
    }

    // MARK: - Push Token

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Forward APNs token to Firebase Auth (required for phone auth on real devices)
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
        appCoordinator.registerDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if DEBUG
        print("[AppDelegate] Push registration failed: \(error)")
        #endif
    }

    // MARK: - URL Handling (Firebase reCAPTCHA callback)

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if Auth.auth().canHandle(url) {
            return true
        }
        return false
    }

    // MARK: - Silent Push (Background Fetch)

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Let Firebase Auth handle silent push for phone verification
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }

        // Silent push received — record heartbeat
        appCoordinator.heartbeatService.silentPushReceived()

        // Perform background sensor burst
        appCoordinator.motionService.performBackgroundBurst { result in
            switch result {
            case .prolongedStillness:
                #if DEBUG
                print("[AppDelegate] Background burst: prolonged stillness detected")
                #endif
            case .normal, .unavailable:
                break
            }
            completionHandler(.newData)
        }
    }

    // MARK: - App Lifecycle

    func applicationDidBecomeActive(_ application: UIApplication) {
        appCoordinator.heartbeatService.appDidBecomeActive()
        appCoordinator.motionService.startForegroundMonitoring()

        // Flush offline queue when we come back online
        Task { await appCoordinator.apiClient.flushOfflineQueue() }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        appCoordinator.motionService.stopForegroundMonitoring()
    }

    // MARK: - Firebase Config Check

    private static func hasValidFirebaseConfig() -> Bool {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let apiKey = dict["API_KEY"] as? String else {
            return false
        }
        // Placeholder values start with "YOUR_"
        return !apiKey.hasPrefix("YOUR_")
    }
}
