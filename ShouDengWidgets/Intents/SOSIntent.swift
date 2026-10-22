import AppIntents
import Foundation

/// One-tap SOS from home screen widget (SafeTap pattern).
/// Writes intent to shared App Group state; the main app picks it up
/// on foreground and triggers the real SOS via API.
@available(iOS 17.0, *)
struct SOSIntent: AppIntent {
    static var title: LocalizedStringResource = "紧急求助"
    static var description: IntentDescription = "一键触发紧急求助"

    /// Open the main app immediately so the SOS confirmation screen appears
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        guard let defaults = UserDefaults(suiteName: WidgetDataStore.appGroupId),
              let data = defaults.data(forKey: "widget_state"),
              let state = try? JSONDecoder().decode(WidgetState.self, from: data),
              state.isLoggedIn else {
            return .result()
        }

        // Write SOS intent to shared state — main app reads this on launch
        var updated = state
        updated.sosActive = true
        updated.sosTriggeredAt = Date()
        updated.updatedAt = Date()
        WidgetDataStore.write(updated)

        // Also write a direct flag for the main app to detect widget-triggered SOS
        defaults.set(true, forKey: "widget_sos_pending")
        defaults.set(Date().timeIntervalSince1970, forKey: "widget_sos_timestamp")

        return .result()
    }
}
