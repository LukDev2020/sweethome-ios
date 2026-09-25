import WidgetKit

struct ProtectedTimelineProvider: TimelineProvider {
    typealias Entry = ProtectedStatusEntry

    func placeholder(in context: Context) -> ProtectedStatusEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ProtectedStatusEntry) -> Void) {
        completion(entry(from: WidgetDataStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProtectedStatusEntry>) -> Void) {
        let state = WidgetDataStore.read()
        let current = entry(from: state)

        let refreshInterval: TimeInterval = state.sosActive || state.homeTimerActive ? 60 : 900
        let nextUpdate = Date().addingTimeInterval(refreshInterval)

        completion(Timeline(entries: [current], policy: .after(nextUpdate)))
    }

    private func entry(from state: WidgetState) -> ProtectedStatusEntry {
        let scenario: ProtectedScenario
        if !state.isLoggedIn {
            scenario = .loggedOut
        } else if state.sosActive {
            scenario = .sosActive
        } else if state.homeTimerActive {
            scenario = .timerRunning
        } else if let lastCheckIn = state.lastCheckInDate,
                  Date().timeIntervalSince(lastCheckIn) > 8 * 3600 {
            scenario = .overdue
        } else if state.guardianCount == 0 {
            scenario = .noGuardians
        } else {
            scenario = .normal
        }

        return ProtectedStatusEntry(
            date: Date(),
            scenario: scenario,
            guardianCount: state.guardianCount,
            lastCheckIn: state.lastCheckInDate,
            sosTriggeredAt: state.sosTriggeredAt,
            timerDeadline: state.homeTimerDeadline,
            timerLabel: state.homeTimerLabel,
            updatedAt: state.updatedAt
        )
    }
}

struct ProtectedStatusEntry: TimelineEntry {
    let date: Date
    let scenario: ProtectedScenario
    let guardianCount: Int
    let lastCheckIn: Date?
    let sosTriggeredAt: Date?
    let timerDeadline: Date?
    let timerLabel: String?
    let updatedAt: Date

    static let placeholder = ProtectedStatusEntry(
        date: Date(),
        scenario: .normal,
        guardianCount: 3,
        lastCheckIn: Date().addingTimeInterval(-1800),
        sosTriggeredAt: nil,
        timerDeadline: nil,
        timerLabel: nil,
        updatedAt: Date()
    )
}

enum ProtectedScenario {
    case normal
    case sosActive
    case timerRunning
    case overdue
    case noGuardians
    case loggedOut
}
