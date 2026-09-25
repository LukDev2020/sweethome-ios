import Foundation

/// Reads/writes WidgetState to App Group shared UserDefaults.
/// Used by both the main app (write) and widget extension (read).
enum WidgetDataStore {

    static let appGroupId = "group.com.shoudeng.app"
    private static let stateKey = "widget_state"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    static func write(_ state: WidgetState) {
        guard let defaults = sharedDefaults else { return }
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: stateKey)
        }
    }

    static func read() -> WidgetState {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(WidgetState.self, from: data) else {
            return .empty
        }
        return state
    }

    static func clear() {
        sharedDefaults?.removeObject(forKey: stateKey)
    }
}
