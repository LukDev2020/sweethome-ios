import SwiftUI
import WidgetKit

// MARK: - Accessory Inline

struct TimerInlineView: View {
    let entry: TimerEntry

    var body: some View {
        if !entry.isLoggedIn {
            Text("守灯 · 请登录")
        } else if entry.isActive, let deadline = entry.deadline {
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                Text(deadline, style: .timer)
            }
        } else {
            Text("守灯 · 无计时")
        }
    }
}

// MARK: - Accessory Circular

struct TimerCircularView: View {
    let entry: TimerEntry

    var body: some View {
        if !entry.isLoggedIn || !entry.isActive {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "house")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        } else if let deadline = entry.deadline {
            let remaining = max(deadline.timeIntervalSince(Date()), 0)
            let total = max(deadline.timeIntervalSince(entry.date), 1)
            Gauge(value: remaining / total) {
                Image(systemName: "house.fill")
                    .font(.caption2)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(remaining > 0 ? .blue : .red)
        }
    }
}

// MARK: - Accessory Rectangular

struct TimerRectangularView: View {
    let entry: TimerEntry

    var body: some View {
        if !entry.isLoggedIn {
            VStack(alignment: .leading, spacing: 2) {
                Label("守灯", systemImage: "house")
                    .font(.headline)
                Text("请登录")
                    .font(.caption)
            }
        } else if entry.isActive, let deadline = entry.deadline {
            VStack(alignment: .leading, spacing: 2) {
                Label(entry.label, systemImage: "house.fill")
                    .font(.headline)
                Text(deadline, style: .timer)
                    .font(.caption)
                if deadline < Date() {
                    Text("已超时")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label("回家计时", systemImage: "house")
                    .font(.headline)
                Text("未设置计时器")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
