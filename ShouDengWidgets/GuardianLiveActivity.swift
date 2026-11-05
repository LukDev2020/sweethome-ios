import WidgetKit
import SwiftUI
import ActivityKit

/// Lock screen Live Activity for the **关怀者 (Guardian)**.
/// Shows: each protected person's status, city, battery, and a call button.
struct GuardianLiveActivity: Widget {

    private func L(_ key: String) -> String { WidgetDataStore.localized(key) }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuardianActivityAttributes.self) { context in
            GuardianLockScreenCard(state: context.state)
                .activityBackgroundTint(SharedColors.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "shield.checkered")
                                .font(.caption2)
                                .foregroundStyle(SharedColors.lamp)
                            Text(WidgetDataStore.appName)
                                .font(.caption.bold())
                        }
                        Text("\(context.state.persons.count)\(L("la.persons.count"))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(context.state.overallStatusText)
                            .font(.caption.bold())
                            .foregroundStyle(overallStatusColor(context.state.overallStatus))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // Show priority person rows
                    let sorted = prioritySorted(context.state.persons)
                    VStack(spacing: 6) {
                        ForEach(Array(sorted.prefix(2))) { person in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(personStatusColor(person.status).opacity(0.3))
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Text(person.initial)
                                            .lineLimit(1).minimumScaleFactor(0.4)
                                            .font(.system(size: 9).bold())
                                            .foregroundStyle(.white)
                                    )
                                Text(person.displayName)
                                    .font(.caption2.bold())
                                Text(personStatusLabel(person))
                                    .font(.caption2)
                                    .foregroundStyle(personStatusColor(person.status))
                                Spacer()
                            }
                        }
                        // Call button
                        if !context.state.priorityPersonPhone.isEmpty,
                           let url = URL(string: "tel:\(context.state.priorityPersonPhone)") {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Image(systemName: "phone.fill")
                                        .font(.caption)
                                    Text(L("la.call") + context.state.priorityPersonName)
                                        .font(.caption.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(SharedColors.lamp)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "shield.checkered")
                        .font(.caption2)
                        .foregroundStyle(SharedColors.lamp)
                    Text(WidgetDataStore.appName)
                        .font(.caption2.bold())
                }
            } compactTrailing: {
                switch context.state.overallStatus {
                case .allSafe:
                    Text("\(context.state.persons.count)\(L("la.people.safe"))")
                        .font(.caption2.bold())
                        .foregroundStyle(SharedColors.safe)
                case .needsAttention:
                    let name = context.state.priorityPersonName
                    Text("\(name)")
                        .font(.caption2.bold())
                        .foregroundStyle(SharedColors.warning)
                case .sosAlert:
                    let name = context.state.priorityPersonName
                    Text("SOS \(name)")
                        .font(.caption2.bold())
                        .foregroundStyle(SharedColors.alert)
                }
            } minimal: {
                ZStack {
                    Circle()
                        .fill(overallStatusColor(context.state.overallStatus).opacity(0.3))
                    Image(systemName: "shield.checkered")
                        .font(.caption2)
                        .foregroundStyle(overallStatusColor(context.state.overallStatus))
                }
            }
        }
    }

    // MARK: - Helpers

    private func overallStatusColor(_ status: GuardianActivityAttributes.OverallStatus) -> Color {
        switch status {
        case .allSafe: return SharedColors.safe
        case .needsAttention: return SharedColors.warning
        case .sosAlert: return SharedColors.alert
        }
    }

    private func personStatusColor(_ status: GuardianActivityAttributes.PersonStatus) -> Color {
        switch status {
        case .normal: return SharedColors.safe
        case .overdue: return SharedColors.warning
        case .alert: return SharedColors.alert
        case .unreachable: return SharedColors.offline
        }
    }

    private func personStatusLabel(_ person: GuardianActivityAttributes.PersonInfo) -> String {
        switch person.status {
        case .normal: return L("la.safe")
        case .overdue: return L("la.overdue")
        case .alert: return L("la.alert")
        case .unreachable: return L("la.offline")
        }
    }

    private func callButtonColor(_ status: GuardianActivityAttributes.OverallStatus) -> Color {
        status == .sosAlert ? .red : SharedColors.lamp
    }

    private func batteryIcon(_ level: Double) -> String {
        if level > 0.75 { return "battery.100" }
        if level > 0.50 { return "battery.75" }
        if level > 0.25 { return "battery.50" }
        return "battery.25"
    }

    private func prioritySorted(_ persons: [GuardianActivityAttributes.PersonInfo]) -> [GuardianActivityAttributes.PersonInfo] {
        persons.sorted { a, b in
            statusPriority(a.status) > statusPriority(b.status)
        }
    }

    private func statusPriority(_ status: GuardianActivityAttributes.PersonStatus) -> Int {
        switch status {
        case .alert: return 3
        case .overdue: return 2
        case .unreachable: return 1
        case .normal: return 0
        }
    }
}
