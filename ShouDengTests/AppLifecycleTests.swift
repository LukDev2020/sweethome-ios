import XCTest
import SwiftUI
@testable import ShouDeng

final class AppLifecycleTests: XCTestCase {

    private func record(_ transitions: [(ScenePhase, ScenePhase)]) -> [String] {
        var events: [String] = []
        let router = AppLifecycleRouter(
            onBecameActive: { events.append("active") },
            onResignedActive: { events.append("resign") }
        )
        for (old, new) in transitions { router.handle(from: old, to: new) }
        return events
    }

    func testColdLaunchBecomesActive() {
        XCTAssertEqual(record([(.background, .inactive), (.inactive, .active)]), ["active"])
    }

    func testBackgroundingResignsOnce() {
        XCTAssertEqual(record([(.active, .inactive), (.inactive, .background)]), ["resign"])
    }

    func testReturningFromBackgroundBecomesActiveAgain() {
        XCTAssertEqual(
            record([(.active, .inactive), (.inactive, .background), (.background, .inactive), (.inactive, .active)]),
            ["resign", "active"]
        )
    }

    func testControlCenterPullDownResignsAndReactivates() {
        XCTAssertEqual(record([(.active, .inactive), (.inactive, .active)]), ["resign", "active"])
    }

    func testNoOpTransitionIgnored() {
        XCTAssertEqual(record([(.active, .active)]), [])
    }

    /// Under the SwiftUI App lifecycle UIKit never calls these delegate methods, so
    /// logic placed in them silently never runs. Keep them out of AppDelegate.
    func testAppDelegateDoesNotRelyOnSceneDeliveredCallbacks() {
        XCTAssertFalse(AppDelegate.instancesRespond(to: #selector(UIApplicationDelegate.applicationDidBecomeActive(_:))))
        XCTAssertFalse(AppDelegate.instancesRespond(to: #selector(UIApplicationDelegate.applicationWillResignActive(_:))))
        XCTAssertFalse(AppDelegate.instancesRespond(to: #selector(UIApplicationDelegate.application(_:open:options:))))
        XCTAssertFalse(AppDelegate.instancesRespond(
            to: #selector(UIApplicationDelegate.application(_:continue:restorationHandler:))))
    }
}
