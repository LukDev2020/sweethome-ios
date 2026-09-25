import SwiftUI
import WidgetKit

// MARK: - Accessory Inline

struct ProtectedInlineView: View {
    let entry: ProtectedStatusEntry

    var body: some View {
        switch entry.scenario {
        case .loggedOut:
            Text("守灯 · 请登录")
        case .sosActive:
            Text("守灯 · 紧急求助中")
        case .timerRunning:
            if let deadline = entry.timerDeadline {
                Text("回家 \(deadline, style: .timer)")
            } else {
                Text("守灯 · 计时中")
            }
        case .overdue:
            Text("守灯 · 请报平安")
        case .noGuardians:
            Text("守灯 · 设置守护者")
        case .normal:
            Text("守灯 · \(entry.guardianCount)位守护者")
        }
    }
}

// MARK: - Accessory Circular

struct ProtectedCircularView: View {
    let entry: ProtectedStatusEntry

    var body: some View {
        switch entry.scenario {
        case .loggedOut:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "shield.slash")
                    .font(.title3)
            }
        case .sosActive:
            Gauge(value: 1.0) {
                Text("!!")
                    .font(.caption.bold())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.red)
        case .timerRunning:
            if let deadline = entry.timerDeadline {
                let total = max(deadline.timeIntervalSince(entry.date), 1)
                let progress = min(max(Date().timeIntervalSince(entry.date) / total, 0), 1)
                Gauge(value: 1.0 - progress) {
                    Image(systemName: "house.fill")
                        .font(.caption2)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.blue)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "timer")
                        .font(.title3)
                }
            }
        case .overdue:
            Gauge(value: 0.0) {
                Text("!")
                    .font(.caption.bold())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.orange)
        case .noGuardians:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "person.badge.plus")
                    .font(.title3)
            }
        case .normal:
            Gauge(value: Double(min(entry.guardianCount, 5)) / 5.0) {
                Image(systemName: "shield.checkered")
                    .font(.caption2)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.green)
        }
    }
}

// MARK: - Accessory Rectangular

struct ProtectedRectangularView: View {
    let entry: ProtectedStatusEntry

    var body: some View {
        switch entry.scenario {
        case .loggedOut:
            VStack(alignment: .leading, spacing: 2) {
                Label("守灯", systemImage: "shield.slash")
                    .font(.headline)
                Text("请登录查看守护状态")
                    .font(.caption)
            }
        case .sosActive:
            VStack(alignment: .leading, spacing: 2) {
                Label("紧急求助中", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                if let triggered = entry.sosTriggeredAt {
                    Text("已进行 \(triggered, style: .relative)")
                        .font(.caption)
                }
            }
        case .timerRunning:
            VStack(alignment: .leading, spacing: 2) {
                Label("回家计时中", systemImage: "house.fill")
                    .font(.headline)
                if let deadline = entry.timerDeadline {
                    Text("剩余 \(deadline, style: .timer)")
                        .font(.caption)
                }
                if let label = entry.timerLabel {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        case .overdue:
            VStack(alignment: .leading, spacing: 2) {
                Label("请报平安", systemImage: "exclamationmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("上次: \(WidgetHelpers.relativeTimeString(from: entry.lastCheckIn))")
                    .font(.caption)
            }
        case .noGuardians:
            VStack(alignment: .leading, spacing: 2) {
                Label("守灯", systemImage: "shield.checkered")
                    .font(.headline)
                Text("设置守护网络")
                    .font(.caption)
                Text("邀请家人成为守护者")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .normal:
            VStack(alignment: .leading, spacing: 2) {
                Label("守灯守护中", systemImage: "shield.checkered")
                    .font(.headline)
                Text("\(entry.guardianCount)位守护者正在保护你")
                    .font(.caption)
                Text("上次报平安: \(WidgetHelpers.relativeTimeString(from: entry.lastCheckIn))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - System Small

struct ProtectedSmallView: View {
    let entry: ProtectedStatusEntry

    var body: some View {
        ZStack {
            SharedColors.ink
            VStack(spacing: 8) {
                statusIcon
                    .font(.largeTitle)
                statusTitle
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                statusSubtitle
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding()
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch entry.scenario {
        case .loggedOut:
            Image(systemName: "shield.slash")
                .foregroundStyle(SharedColors.offline)
        case .sosActive:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SharedColors.alert)
        case .timerRunning:
            Image(systemName: "house.fill")
                .foregroundStyle(.blue)
        case .overdue:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(SharedColors.warning)
        case .noGuardians:
            Image(systemName: "person.badge.plus")
                .foregroundStyle(SharedColors.lamp)
        case .normal:
            Image(systemName: "shield.checkered")
                .foregroundStyle(SharedColors.safe)
        }
    }

    @ViewBuilder
    private var statusTitle: some View {
        switch entry.scenario {
        case .loggedOut: Text("登录守灯")
        case .sosActive: Text("紧急求助中")
        case .timerRunning: Text("回家计时中")
        case .overdue: Text("请报平安")
        case .noGuardians: Text("设置守护者")
        case .normal: Text("守灯守护中")
        }
    }

    @ViewBuilder
    private var statusSubtitle: some View {
        switch entry.scenario {
        case .loggedOut: Text("点击打开")
        case .sosActive:
            if let t = entry.sosTriggeredAt {
                Text(t, style: .relative)
            } else {
                Text("")
            }
        case .timerRunning:
            if let d = entry.timerDeadline {
                Text(d, style: .timer)
            } else {
                Text("计时中")
            }
        case .overdue: Text(WidgetHelpers.relativeTimeString(from: entry.lastCheckIn))
        case .noGuardians: Text("邀请家人")
        case .normal: Text("\(entry.guardianCount)位守护者")
        }
    }
}

// MARK: - System Medium

struct ProtectedMediumView: View {
    let entry: ProtectedStatusEntry

    var body: some View {
        ZStack {
            SharedColors.ink
            HStack(spacing: 16) {
                // Left: status
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: scenarioIcon)
                            .foregroundStyle(scenarioColor)
                        Text(scenarioTitle)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                    }
                    Text(scenarioDetail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    if WidgetHelpers.isStale(entry.updatedAt) {
                        Text("更新于 \(WidgetHelpers.relativeTimeString(from: entry.updatedAt))")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
                // Right: guardian count ring
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(scenarioColor.opacity(0.3), lineWidth: 4)
                            .frame(width: 48, height: 48)
                        Circle()
                            .trim(from: 0, to: Double(min(entry.guardianCount, 5)) / 5.0)
                            .stroke(scenarioColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 48, height: 48)
                            .rotationEffect(.degrees(-90))
                        Text("\(entry.guardianCount)")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    }
                    Text("守护者")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding()
        }
    }

    private var scenarioIcon: String {
        switch entry.scenario {
        case .loggedOut: return "shield.slash"
        case .sosActive: return "exclamationmark.triangle.fill"
        case .timerRunning: return "house.fill"
        case .overdue: return "exclamationmark.circle.fill"
        case .noGuardians: return "person.badge.plus"
        case .normal: return "shield.checkered"
        }
    }

    private var scenarioColor: Color {
        switch entry.scenario {
        case .loggedOut: return SharedColors.offline
        case .sosActive: return SharedColors.alert
        case .timerRunning: return .blue
        case .overdue: return SharedColors.warning
        case .noGuardians: return SharedColors.lamp
        case .normal: return SharedColors.safe
        }
    }

    private var scenarioTitle: String {
        switch entry.scenario {
        case .loggedOut: return "登录守灯"
        case .sosActive: return "紧急求助中"
        case .timerRunning: return "回家计时中"
        case .overdue: return "请报平安"
        case .noGuardians: return "设置守护网络"
        case .normal: return "守灯守护中"
        }
    }

    private var scenarioDetail: String {
        switch entry.scenario {
        case .loggedOut: return "点击登录查看守护状态"
        case .sosActive:
            if let t = entry.sosTriggeredAt {
                return "已持续 \(WidgetHelpers.relativeTimeString(from: t))"
            }
            return "已触发紧急求助"
        case .timerRunning: return entry.timerLabel ?? "回家倒计时进行中"
        case .overdue: return "上次报平安: \(WidgetHelpers.relativeTimeString(from: entry.lastCheckIn))"
        case .noGuardians: return "邀请家人成为你的守护者"
        case .normal: return "\(entry.guardianCount)位守护者正在保护你"
        }
    }
}
