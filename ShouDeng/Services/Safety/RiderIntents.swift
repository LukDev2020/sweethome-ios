import AppIntents
import Foundation

// MARK: - Siri, Shortcuts and the Action Button
//
// "Hey Siri, Beaconify SOS", or Settings → Action Button → Shortcut → Beaconify
// → SOS. SOS opens the app at the cancel countdown (as from the lock screen); shifts
// start and end without opening it.

// Titles, descriptions, dialogs and phrases live in ShouDeng/AppShortcuts.xcstrings
// (en, zh-Hans, zh-Hant, fr, ja). Siri matches phrases in the phone's language,
// so each language has its own; every phrase keeps ${applicationName}.

enum AppIntentBridge {
    @MainActor static weak var coordinator: AppCoordinator?
}

@available(iOS 17.0, *)
struct LanternSOSIntent: AppIntent {
    static var title = LocalizedStringResource("intent.sos.title", defaultValue: "Beaconify SOS", table: "AppIntents")
    static var description = IntentDescription(LocalizedStringResource("intent.sos.description", defaultValue: "Opens Beaconify at the SOS countdown.", table: "AppIntents"))
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentBridge.coordinator?.requestSOS(method: .widgetTap)
        return .result()
    }
}

@available(iOS 17.0, *)
struct StartRiderShiftIntent: AppIntent {
    static var title = LocalizedStringResource("intent.startShift.title", defaultValue: "Start shift", table: "AppIntents")
    static var description = IntentDescription(LocalizedStringResource("intent.startShift.description", defaultValue: "Starts a Beaconify rider shift and shares your location with your crew.", table: "AppIntents"))

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let coordinator = await AppIntentBridge.coordinator else {
            return .result(dialog: IntentDialog(LocalizedStringResource("intent.openAppFirst", defaultValue: "Open Beaconify first.", table: "AppIntents")))
        }
        await coordinator.startShift(plannedEnd: Date().addingTimeInterval(4 * 3600))
        return .result(dialog: IntentDialog(LocalizedStringResource("intent.startShift.done", defaultValue: "Shift started. Your crew can see you.", table: "AppIntents")))
    }
}

@available(iOS 17.0, *)
struct EndRiderShiftIntent: AppIntent {
    static var title = LocalizedStringResource("intent.endShift.title", defaultValue: "End shift", table: "AppIntents")
    static var description = IntentDescription(LocalizedStringResource("intent.endShift.description", defaultValue: "Ends your Beaconify rider shift.", table: "AppIntents"))

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let coordinator = await AppIntentBridge.coordinator else {
            return .result(dialog: IntentDialog(LocalizedStringResource("intent.openAppFirst", defaultValue: "Open Beaconify first.", table: "AppIntents")))
        }
        await coordinator.endShift()
        return .result(dialog: IntentDialog(LocalizedStringResource("intent.endShift.done", defaultValue: "Shift ended. Get home safe.", table: "AppIntents")))
    }
}

@available(iOS 17.0, *)
struct LanternShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LanternSOSIntent(),
                    phrases: ["\(.applicationName) SOS", "Help me with \(.applicationName)"],
                    shortTitle: LocalizedStringResource("shortcut.sos.short", defaultValue: "SOS", table: "AppIntents"),
                    systemImageName: "sos")
        AppShortcut(intent: StartRiderShiftIntent(),
                    phrases: ["Start shift in \(.applicationName)", "Start my \(.applicationName) shift"],
                    shortTitle: LocalizedStringResource("intent.startShift.title", defaultValue: "Start shift", table: "AppIntents"),
                    systemImageName: "bicycle")
        AppShortcut(intent: EndRiderShiftIntent(),
                    phrases: ["End shift in \(.applicationName)", "End my \(.applicationName) shift"],
                    shortTitle: LocalizedStringResource("intent.endShift.title", defaultValue: "End shift", table: "AppIntents"),
                    systemImageName: "house")
    }
}
