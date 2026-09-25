import AppIntents
import Foundation

@available(iOS 17.0, *)
struct DismissTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "我到了"
    static var description: IntentDescription = "告知守护者已安全到达"

    func perform() async throws -> some IntentResult {
        guard let defaults = UserDefaults(suiteName: WidgetDataStore.appGroupId),
              let data = defaults.data(forKey: "widget_state"),
              let state = try? JSONDecoder().decode(WidgetState.self, from: data),
              state.isLoggedIn else {
            return .result()
        }

        var updated = state
        updated.homeTimerActive = false
        updated.homeTimerDeadline = nil
        updated.updatedAt = Date()
        WidgetDataStore.write(updated)

        return .result()
    }
}
