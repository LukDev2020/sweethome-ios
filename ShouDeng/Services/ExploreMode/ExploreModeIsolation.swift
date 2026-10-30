import Foundation
import UIKit

// MARK: - Explore Mode isolation flag
//
// Set for the lifetime of an Explore Mode (demo) session. Services that would
// otherwise touch the real device or the real account (location, mic, BLE,
// CallKit, background tasks, dead-man switch, disguise, widgets, Live
// Activities, push registration) check it and do nothing. Storage singletons
// switch to throw-away in-memory overlays at the same time (see
// ExploreModeController.beginIsolation).

enum ExploreMode {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _isActive = false

    static var isActive: Bool {
        lock.withLock { _isActive }
    }

    static func setActive(_ active: Bool) {
        lock.withLock { _isActive = active }
    }

    /// Posted when a demo user tries something that would start a real device
    /// feature; the demo overlay explains it is not available in the demo.
    static let blockedFeatureNotification = Notification.Name("ExploreModeBlockedFeature")

    /// Returns true (and tells the demo UI) if `feature` must not run now.
    @discardableResult
    static func blocks(_ feature: String) -> Bool {
        guard isActive else { return false }
        NotificationCenter.default.post(name: blockedFeatureNotification, object: feature)
        return true
    }
}

// MARK: - Leaving the app

/// Opens URLs that leave the app (phone calls, SMS, Maps, Settings). During
/// Explore Mode, calls / texts to the sample family or to emergency numbers are
/// blocked — the demo must never dial anyone.
enum ExternalURL {
    static let blockedSchemes: Set<String> = ["tel", "telprompt", "sms", "facetime", "facetime-audio", "mailto"]

    static func isBlockedInDemo(_ url: URL) -> Bool {
        blockedSchemes.contains(url.scheme?.lowercased() ?? "")
    }

    @MainActor
    static func open(_ url: URL) {
        if isBlockedInDemo(url), ExploreMode.blocks("call") { return }
        UIApplication.shared.open(url)
    }
}
