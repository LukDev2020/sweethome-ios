import AppIntents
import Foundation

@available(iOS 17.0, *)
struct CheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "报平安"
    static var description: IntentDescription = "向守护者发送报平安信号"

    /// The extension has no session token: the app sends the check-in (and the
    /// guardians' "home safe" push) as soon as it opens.
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Read auth token from shared keychain / UserDefaults
        guard let defaults = UserDefaults(suiteName: WidgetDataStore.appGroupId),
              let data = defaults.data(forKey: "widget_state"),
              let state = try? JSONDecoder().decode(WidgetState.self, from: data),
              state.isLoggedIn else {
            return .result()
        }

        WidgetDataStore.enqueuePendingAction(.checkIn)
        var updated = state
        updated.lastCheckInDate = Date()
        updated.updatedAt = Date()
        WidgetDataStore.write(updated)

        return .result()
    }
}
