import SwiftUI
import WidgetKit

private func L(_ key: String) -> String { WidgetDataStore.localized(key) }

// MARK: - Accessory Inline

struct GuardianInlineView: View {
    let entry: GuardianStatusEntry

    var body: some View {
        switch entry.scenario {
        case .loggedOut:
            Text(WidgetHelpers.branded(L("widget.login.required")))
        case .sosAlert:
            if let person = alertPerson {
                Text(WidgetHelpers.branded(WidgetDataStore.localizedFormat("widget.person.sos", person.displayName)))
            } else {
                Text(WidgetHelpers.branded(L("widget.sos.alert")))
            }
        case .someoneOverdue:
            if let person = overduePerson {
                Text(WidgetHelpers.branded(WidgetDataStore.localizedFormat("widget.person.overdue", person.displayName)))
            } else {
                Text(WidgetHelpers.branded(L("widget.someone.overdue")))
            }
        case .deviceOffline:
            if let person = offlinePerson {
                Text(WidgetHelpers.branded(WidgetDataStore.localizedFormat("widget.person.offline", person.displayName)))
            } else {
                Text(WidgetHelpers.branded(L("widget.device.offline")))
            }
        case .noPersons:
            Text(WidgetHelpers.branded(L("widget.invite.family")))
        case .allSafe, .timerExpired:
            Text(WidgetHelpers.branded(WidgetDataStore.localizedFormat("widget.people.safe", entry.persons.count)))
        }
    }

    private var alertPerson: WidgetProtectedPerson? {
        entry.persons.first { $0.status == "alert" }
    }
    private var overduePerson: WidgetProtectedPerson? {
        entry.persons.first { $0.status == "overdue" }
    }
    private var offlinePerson: WidgetProtectedPerson? {
        entry.persons.first { $0.status == "unreachable" }
    }
}

// MARK: - Accessory Circular

struct GuardianCircularView: View {
    let entry: GuardianStatusEntry

    var body: some View {
        switch entry.scenario {
        case .loggedOut:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "shield.slash")
                    .font(.title3)
            }
        case .sosAlert:
            Gauge(value: 1.0) {
                Text("!")
                    .font(.caption.bold())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.red)
        case .someoneOverdue:
            Gauge(value: 0.5) {
                Text("!")
                    .font(.caption.bold())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.orange)
        case .deviceOffline:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.caption)
            }
        case .noPersons:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "person.badge.plus")
                    .font(.title3)
            }
        case .allSafe, .timerExpired:
            let safeCount = entry.persons.filter { $0.status == "normal" }.count
            let total = max(entry.persons.count, 1)
            Gauge(value: Double(safeCount) / Double(total)) {
                Text("\(entry.persons.count)")
                    .font(.caption.bold())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.green)
        }
    }
}

// MARK: - Accessory Rectangular

struct GuardianRectangularView: View {
    let entry: GuardianStatusEntry

    var body: some View {
        switch entry.scenario {
        case .loggedOut:
            VStack(alignment: .leading, spacing: 2) {
                Label(WidgetDataStore.appName, systemImage: "shield.slash")
                    .font(.headline)
                Text(L("widget.signIn.toSeeStatus"))
                    .font(.caption)
            }
        case .sosAlert:
            if let person = entry.persons.first(where: { $0.status == "alert" }) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(L("widget.sos.title"), systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(WidgetDataStore.localizedFormat("widget.person.sentSOS", person.displayName))
                        .font(.caption)
                }
            }
        case .someoneOverdue:
            if let person = entry.persons.first(where: { $0.status == "overdue" }) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(L("la.overdue"), systemImage: "exclamationmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("\(person.displayName) \(WidgetHelpers.relativeTimeString(from: person.lastCheckIn))")
                        .font(.caption)
                }
            }
        case .deviceOffline:
            if let person = entry.persons.first(where: { $0.status == "unreachable" }) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(L("widget.device.offline"), systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.headline)
                    Text(WidgetDataStore.localizedFormat("widget.person.offline", person.displayName))
                        .font(.caption)
                }
            }
        case .noPersons:
            VStack(alignment: .leading, spacing: 2) {
                Label(WidgetDataStore.appName, systemImage: "shield.checkered")
                    .font(.headline)
                Text(L("widget.invite.join"))
                    .font(.caption)
            }
        case .allSafe, .timerExpired:
            VStack(alignment: .leading, spacing: 2) {
                Label(WidgetDataStore.localizedFormat("widget.people.safe", entry.persons.count), systemImage: "shield.checkered")
                    .font(.headline)
                Text(WidgetDataStore.localizedFormat("widget.updated", WidgetHelpers.relativeTimeString(from: entry.updatedAt)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - System Small

struct GuardianSmallView: View {
    let entry: GuardianStatusEntry

    var body: some View {
        ZStack {
            SharedColors.ink
            VStack(spacing: 8) {
                Image(systemName: scenarioIcon)
                    .font(.largeTitle)
                    .foregroundStyle(scenarioColor)
                Text(scenarioTitle)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Text(scenarioSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding()
        }
    }

    private var scenarioIcon: String {
        switch entry.scenario {
        case .loggedOut: return "shield.slash"
        case .sosAlert: return "exclamationmark.triangle.fill"
        case .someoneOverdue: return "exclamationmark.circle.fill"
        case .timerExpired: return "timer"
        case .deviceOffline: return "antenna.radiowaves.left.and.right.slash"
        case .noPersons: return "person.badge.plus"
        case .allSafe: return "shield.checkered"
        }
    }

    private var scenarioColor: Color {
        switch entry.scenario {
        case .loggedOut: return SharedColors.offline
        case .sosAlert: return SharedColors.alert
        case .someoneOverdue: return SharedColors.warning
        case .timerExpired: return SharedColors.warning
        case .deviceOffline: return SharedColors.offline
        case .noPersons: return SharedColors.lamp
        case .allSafe: return SharedColors.safe
        }
    }

    private var scenarioTitle: String {
        switch entry.scenario {
        case .loggedOut: return WidgetDataStore.localizedFormat("widget.signIn.app", WidgetDataStore.appName)
        case .sosAlert: return L("widget.sos.title")
        case .someoneOverdue: return L("la.overdue")
        case .timerExpired: return L("widget.timer.expired")
        case .deviceOffline: return L("widget.device.offline")
        case .noPersons: return L("widget.invite.family")
        case .allSafe: return WidgetDataStore.localizedFormat("widget.people.safe", entry.persons.count)
        }
    }

    private var scenarioSubtitle: String {
        switch entry.scenario {
        case .loggedOut: return L("widget.tapToOpen")
        case .sosAlert:
            return entry.persons.first(where: { $0.status == "alert" })?.displayName ?? ""
        case .someoneOverdue:
            return entry.persons.first(where: { $0.status == "overdue" })?.displayName ?? ""
        case .timerExpired: return ""
        case .deviceOffline:
            return entry.persons.first(where: { $0.status == "unreachable" })?.displayName ?? ""
        case .noPersons: return L("widget.invite.join")
        case .allSafe: return WidgetHelpers.relativeTimeString(from: entry.updatedAt)
        }
    }
}

// MARK: - System Medium

struct GuardianMediumView: View {
    let entry: GuardianStatusEntry

    var body: some View {
        ZStack {
            SharedColors.ink
            if entry.scenario == .loggedOut || entry.scenario == .noPersons {
                emptyStateView
            } else {
                personListView
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: entry.scenario == .loggedOut ? "shield.slash" : "person.badge.plus")
                .font(.title)
                .foregroundStyle(SharedColors.lamp)
            Text(entry.scenario == .loggedOut ? WidgetDataStore.localizedFormat("widget.signIn.app", WidgetDataStore.appName) : L("widget.invite.join"))
                .font(.subheadline.bold())
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var personListView: some View {
        let sorted = WidgetHelpers.prioritySorted(entry.persons)
        let displayPersons = Array(sorted.prefix(3))
        let remaining = max(entry.persons.count - 3, 0)

        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundStyle(SharedColors.lamp)
                Text(L("widget.status.header"))
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Spacer()
                Text(WidgetHelpers.relativeTimeString(from: entry.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }

            // Person rows
            ForEach(displayPersons) { person in
                HStack(spacing: 8) {
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(WidgetHelpers.statusColor(for: person.status).opacity(0.3))
                            .frame(width: 28, height: 28)
                        Text(person.initial)
                            .lineLimit(1).minimumScaleFactor(0.4)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                    // Name + status
                    VStack(alignment: .leading, spacing: 1) {
                        Text(person.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        Text(personStatusText(person))
                            .font(.caption2)
                            .foregroundStyle(WidgetHelpers.statusColor(for: person.status))
                    }
                    Spacer()
                    // Battery
                    if let battery = person.batteryLevel {
                        Text("\(Int(battery * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }

            if remaining > 0 {
                Text(WidgetDataStore.localized("widget.more", count: remaining))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding()
    }

    private func personStatusText(_ person: WidgetProtectedPerson) -> String {
        switch person.status {
        case "alert": return L("widget.sos.title")
        case "overdue": return "\(L("la.overdue")) \(WidgetHelpers.relativeTimeString(from: person.lastCheckIn))"
        case "unreachable": return L("widget.device.offline")
        default: return "\(L("la.safe")) · \(WidgetHelpers.relativeTimeString(from: person.lastCheckIn))"
        }
    }
}
