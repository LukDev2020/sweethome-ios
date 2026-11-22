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

/// "Silent SOS": the first tap asks for a second one (5 s), the second sends an SOS
/// with nothing on this phone's screen — for someone who can't be seen calling for help.
@available(iOS 17.0, *)
struct LockScreenSilentSOSIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Silent SOS"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetDataStore.enqueuePendingAction(WidgetDataStore.silentSOSTap() ? .silentSOS : .armSilentSOS)
        await MainActor.run { LiveActivityActionBridge.handler?() }
        return .result()
    }
}

/// "Fake call": an incoming-call screen after the delay set in Settings → Fake call.
@available(iOS 17.0, *)
struct LockScreenFakeCallIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Fake call"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetDataStore.enqueuePendingAction(.fakeCall)
        await MainActor.run { LiveActivityActionBridge.handler?() }
        return .result()
    }
}

/// Countdown "+15 min" (safety timer or home timer, whichever is on the card).
@available(iOS 17.0, *)
struct LockScreenExtendTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add 15 minutes"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetDataStore.enqueuePendingAction(.extendTimer)
        await MainActor.run { LiveActivityActionBridge.handler?() }
        return .result()
    }
}

/// Countdown "I'm here": ends the countdown and checks in.
@available(iOS 17.0, *)
struct LockScreenArrivedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "I've arrived"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetDataStore.enqueuePendingAction(.arrived)
        await MainActor.run { LiveActivityActionBridge.handler?() }
        return .result()
    }
}

/// Guardian card during an SOS: "On my way" — acknowledges the SOS (stops the
/// automatic calls, tells the person and the other guardians).
@available(iOS 17.0, *)
struct LockScreenAcknowledgeSOSIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "On my way"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        WidgetDataStore.enqueuePendingAction(.acknowledgeSOS)
        await MainActor.run { LiveActivityActionBridge.handler?() }
        return .result()
    }
}
