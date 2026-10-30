import SwiftUI

// MARK: - App Lifecycle Router
//
// The app uses the SwiftUI `App` lifecycle, so UIKit delivers activation and URL
// events to the scene — `UIApplicationDelegate.applicationDidBecomeActive`,
// `applicationWillResignActive`, `application(_:open:options:)` and
// `application(_:continue:restorationHandler:)` are never called.
// ShouDengApp feeds `scenePhase` changes through this router instead.

struct AppLifecycleRouter {
    var onBecameActive: () -> Void
    var onResignedActive: () -> Void

    func handle(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        guard oldPhase != newPhase else { return }
        if newPhase == .active {
            onBecameActive()
        } else if oldPhase == .active {
            onResignedActive()
        }
    }
}
