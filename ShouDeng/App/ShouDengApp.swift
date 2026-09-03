import SwiftUI

@main
struct ShouDengApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appDelegate.appCoordinator)
        }
    }
}
