import WidgetKit

struct TimerTimelineProvider: TimelineProvider {
    typealias Entry = TimerEntry

    func placeholder(in context: Context) -> TimerEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        completion(entry(from: WidgetDataStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let state = WidgetDataStore.read()
        let current = entry(from: state)

        let refreshInterval: TimeInterval = state.homeTimerActive ? 60 : 900
        let nextUpdate = Date().addingTimeInterval(refreshInterval)

        completion(Timeline(entries: [current], policy: .after(nextUpdate)))
    }

    private func entry(from state: WidgetState) -> TimerEntry {
        TimerEntry(
            date: Date(),
            isActive: state.homeTimerActive,
            deadline: state.homeTimerDeadline,
            label: state.homeTimerLabel ?? "回家倒计时",
            isLoggedIn: state.isLoggedIn
        )
    }
}

struct TimerEntry: TimelineEntry {
    let date: Date
    let isActive: Bool
    let deadline: Date?
    let label: String
    let isLoggedIn: Bool

    static let placeholder = TimerEntry(
        date: Date(),
        isActive: true,
        deadline: Date().addingTimeInterval(3600),
        label: "回家倒计时",
        isLoggedIn: true
    )
}
