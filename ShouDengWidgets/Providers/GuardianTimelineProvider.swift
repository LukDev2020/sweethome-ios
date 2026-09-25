import WidgetKit

struct GuardianTimelineProvider: TimelineProvider {
    typealias Entry = GuardianStatusEntry

    func placeholder(in context: Context) -> GuardianStatusEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (GuardianStatusEntry) -> Void) {
        completion(entry(from: WidgetDataStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GuardianStatusEntry>) -> Void) {
        let state = WidgetDataStore.read()
        let current = entry(from: state)

        let hasUrgent = state.protectedPersons.contains { $0.status == "alert" }
        let refreshInterval: TimeInterval = hasUrgent ? 60 : 900
        let nextUpdate = Date().addingTimeInterval(refreshInterval)

        completion(Timeline(entries: [current], policy: .after(nextUpdate)))
    }

    private func entry(from state: WidgetState) -> GuardianStatusEntry {
        let scenario: GuardianScenario
        if !state.isLoggedIn {
            scenario = .loggedOut
        } else if state.protectedPersons.isEmpty {
            scenario = .noPersons
        } else if state.protectedPersons.contains(where: { $0.status == "alert" }) {
            scenario = .sosAlert
        } else if state.protectedPersons.contains(where: { $0.status == "overdue" }) {
            scenario = .someoneOverdue
        } else if state.protectedPersons.contains(where: { $0.status == "unreachable" }) {
            scenario = .deviceOffline
        } else {
            scenario = .allSafe
        }

        return GuardianStatusEntry(
            date: Date(),
            scenario: scenario,
            persons: state.protectedPersons,
            updatedAt: state.updatedAt
        )
    }
}

struct GuardianStatusEntry: TimelineEntry {
    let date: Date
    let scenario: GuardianScenario
    let persons: [WidgetProtectedPerson]
    let updatedAt: Date

    static let placeholder = GuardianStatusEntry(
        date: Date(),
        scenario: .allSafe,
        persons: [
            WidgetProtectedPerson(id: "1", displayName: "小雨", initial: "雨", status: "normal", lastCheckIn: Date().addingTimeInterval(-1800), batteryLevel: 0.72, homeTimerDeadline: nil),
        ],
        updatedAt: Date()
    )
}

enum GuardianScenario {
    case allSafe
    case sosAlert
    case someoneOverdue
    case timerExpired
    case deviceOffline
    case noPersons
    case loggedOut
}
