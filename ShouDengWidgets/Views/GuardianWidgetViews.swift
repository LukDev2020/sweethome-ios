import SwiftUI
import WidgetKit

// MARK: - Accessory Inline

struct GuardianInlineView: View {
    let entry: GuardianStatusEntry

    var body: some View {
        switch entry.scenario {
        case .loggedOut:
            Text("守灯 · 请登录")
        case .sosAlert:
            if let person = alertPerson {
                Text("守灯 · \(person.displayName) SOS")
            } else {
                Text("守灯 · SOS 警报")
            }
        case .someoneOverdue:
            if let person = overduePerson {
                Text("守灯 · \(person.displayName) 未报平安")
            } else {
                Text("守灯 · 有人未报平安")
            }
        case .deviceOffline:
            if let person = offlinePerson {
                Text("守灯 · \(person.displayName) 离线")
            } else {
                Text("守灯 · 设备离线")
            }
        case .noPersons:
            Text("守灯 · 邀请家人")
        case .allSafe, .timerExpired:
            Text("守灯 · \(entry.persons.count)人安全")
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
                Label("守灯", systemImage: "shield.slash")
                    .font(.headline)
                Text("请登录查看守护状态")
                    .font(.caption)
            }
        case .sosAlert:
            if let person = entry.persons.first(where: { $0.status == "alert" }) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("紧急求助", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text("\(person.displayName) 发出求助")
                        .font(.caption)
                }
            }
        case .someoneOverdue:
            if let person = entry.persons.first(where: { $0.status == "overdue" }) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("未报平安", systemImage: "exclamationmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("\(person.displayName) \(WidgetHelpers.relativeTimeString(from: person.lastCheckIn))")
                        .font(.caption)
                }
            }
        case .deviceOffline:
            if let person = entry.persons.first(where: { $0.status == "unreachable" }) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("设备离线", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .font(.headline)
                    Text("\(person.displayName) 设备离线")
                        .font(.caption)
                }
            }
        case .noPersons:
            VStack(alignment: .leading, spacing: 2) {
                Label("守灯", systemImage: "shield.checkered")
                    .font(.headline)
                Text("邀请家人加入守护")
                    .font(.caption)
            }
        case .allSafe, .timerExpired:
            VStack(alignment: .leading, spacing: 2) {
                Label("\(entry.persons.count)人安全", systemImage: "shield.checkered")
                    .font(.headline)
                Text("最近更新 \(WidgetHelpers.relativeTimeString(from: entry.updatedAt))")
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
        case .loggedOut: return "登录守灯"
        case .sosAlert: return "紧急求助"
        case .someoneOverdue: return "未报平安"
        case .timerExpired: return "回家超时"
        case .deviceOffline: return "设备离线"
        case .noPersons: return "邀请家人"
        case .allSafe: return "\(entry.persons.count)人安全"
        }
    }

    private var scenarioSubtitle: String {
        switch entry.scenario {
        case .loggedOut: return "点击打开"
        case .sosAlert:
            return entry.persons.first(where: { $0.status == "alert" })?.displayName ?? ""
        case .someoneOverdue:
            return entry.persons.first(where: { $0.status == "overdue" })?.displayName ?? ""
        case .timerExpired: return ""
        case .deviceOffline:
            return entry.persons.first(where: { $0.status == "unreachable" })?.displayName ?? ""
        case .noPersons: return "邀请家人加入"
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
            Text(entry.scenario == .loggedOut ? "登录守灯" : "邀请家人加入守护")
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
                Text("守护状态")
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
                Text("+\(remaining)人")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding()
    }

    private func personStatusText(_ person: WidgetProtectedPerson) -> String {
        switch person.status {
        case "alert": return "紧急求助"
        case "overdue": return "未报平安 \(WidgetHelpers.relativeTimeString(from: person.lastCheckIn))"
        case "unreachable": return "设备离线"
        default: return "安全 · \(WidgetHelpers.relativeTimeString(from: person.lastCheckIn))"
        }
    }
}
