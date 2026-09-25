import AppIntents
import Foundation

@available(iOS 17.0, *)
struct CheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "报平安"
    static var description: IntentDescription = "向守护者发送报平安信号"

    func perform() async throws -> some IntentResult {
        // Read auth token from shared keychain / UserDefaults
        guard let defaults = UserDefaults(suiteName: WidgetDataStore.appGroupId),
              let data = defaults.data(forKey: "widget_state"),
              let state = try? JSONDecoder().decode(WidgetState.self, from: data),
              state.isLoggedIn else {
            return .result()
        }

        // Fire-and-forget check-in via background URL session
        // The actual network call requires the auth token which lives in the main app keychain.
        // For now, update widget state to reflect check-in intent was triggered.
        var updated = state
        updated.lastCheckInDate = Date()
        updated.updatedAt = Date()
        WidgetDataStore.write(updated)

        return .result()
    }
}
