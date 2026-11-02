import AppIntents
import Foundation

// MARK: - Lock-screen card buttons
//
// "Check in" and "Location" on the Live Activity act without opening the app: as
// LiveActivityIntents compiled into the app as well as the widget, they run in the
// app's process (launched in the background if needed). The action is queued first,
// so it is never lost: if the app can't send it yet (not signed in, offline), it goes
// out the next time the app opens. SOS is different on purpose — it opens the app to
// the confirmation and the 5-second cancel countdown.

/// Set by the app at launch; nil inside the widget extension.
enum LiveActivityActionBridge {
    @MainActor static var handler: (() -> Void)?
}

@available(iOS 17.0, *)
struct LockScreenCheckInIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Check in"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetDataStore.enqueuePendingAction(.checkIn)
        await MainActor.run { LiveActivityActionBridge.handler?() }
        return .result()
    }
}

@available(iOS 17.0, *)
struct LockScreenShareLocationIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Send my location"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetDataStore.enqueuePendingAction(.shareLocation)
        await MainActor.run { LiveActivityActionBridge.handler?() }
        return .result()
    }
}
