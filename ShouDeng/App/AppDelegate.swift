import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {

    let appCoordinator = AppCoordinator()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

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

    // MARK: - Silent Push (Background Fetch)

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
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
}
