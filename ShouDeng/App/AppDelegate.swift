import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {

    let appCoordinator = AppCoordinator()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // Register for push notifications
        appCoordinator.pushService.registerForPushNotifications()
        application.registerForRemoteNotifications()

        // Start heartbeat service
        appCoordinator.heartbeatService.start()

        // Start location service
        appCoordinator.locationManager.start()

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

    // MARK: - Push Token

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        appCoordinator.pushService.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[AppDelegate] Push registration failed: \(error)")
    }

    // MARK: - Silent Push (Background Fetch)

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Silent push received — record heartbeat
        appCoordinator.heartbeatService.silentPushReceived()

        // Perform background sensor burst (piggyback on wake-up)
        appCoordinator.motionService.performBackgroundBurst { result in
            switch result {
            case .prolongedStillness:
                // Person hasn't moved — this is a signal for the baseline scorer
                print("[AppDelegate] Background burst: prolonged stillness detected")
            case .normal:
                break
            case .unavailable:
                break
            }
            completionHandler(.newData)
        }
    }

    // MARK: - App Lifecycle

    func applicationDidBecomeActive(_ application: UIApplication) {
        appCoordinator.heartbeatService.appDidBecomeActive()

        // Start foreground motion monitoring
        appCoordinator.motionService.startForegroundMonitoring()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Stop foreground motion monitoring (iOS will kill it anyway)
        appCoordinator.motionService.stopForegroundMonitoring()
    }
}
