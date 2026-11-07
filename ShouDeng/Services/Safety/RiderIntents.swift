import AppIntents
import Foundation

// MARK: - Siri, Shortcuts and the Action Button
//
// "Hey Siri, Lantern Care SOS", or Settings → Action Button → Shortcut → Lantern Care
// → SOS. SOS opens the app at the cancel countdown (as from the lock screen); shifts
// start and end without opening it.

enum AppIntentBridge {
    @MainActor static weak var coordinator: AppCoordinator?
}

@available(iOS 17.0, *)
struct LanternSOSIntent: AppIntent {
    static var title: LocalizedStringResource = "Lantern Care SOS"
    static var description = IntentDescription("Opens Lantern Care at the SOS countdown.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentBridge.coordinator?.requestSOS(method: .widgetTap)
        return .result()
    }
}

@available(iOS 17.0, *)
struct StartRiderShiftIntent: AppIntent {
    static var title: LocalizedStringResource = "Start shift"
    static var description = IntentDescription("Starts a Lantern Care rider shift and shares your location with your crew.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let coordinator = await AppIntentBridge.coordinator else { return .result(dialog: "Open Lantern Care first.") }
        await coordinator.startShift(plannedEnd: Date().addingTimeInterval(4 * 3600))
        return .result(dialog: "Shift started. Your crew can see you.")
    }
}

@available(iOS 17.0, *)
struct EndRiderShiftIntent: AppIntent {
    static var title: LocalizedStringResource = "End shift"
    static var description = IntentDescription("Ends your Lantern Care rider shift.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let coordinator = await AppIntentBridge.coordinator else { return .result(dialog: "Open Lantern Care first.") }
        await coordinator.endShift()
        return .result(dialog: "Shift ended. Get home safe.")
    }
}

@available(iOS 17.0, *)
struct LanternShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LanternSOSIntent(),
                    phrases: ["\(.applicationName) SOS", "Help me with \(.applicationName)"],
                    shortTitle: "SOS", systemImageName: "sos")
        AppShortcut(intent: StartRiderShiftIntent(),
                    phrases: ["Start shift in \(.applicationName)", "Start my \(.applicationName) shift"],
                    shortTitle: "Start shift", systemImageName: "bicycle")
        AppShortcut(intent: EndRiderShiftIntent(),
                    phrases: ["End shift in \(.applicationName)", "End my \(.applicationName) shift"],
                    shortTitle: "End shift", systemImageName: "house")
    }
}
