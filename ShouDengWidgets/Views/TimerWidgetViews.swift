import SwiftUI
import WidgetKit

private func L(_ key: String) -> String { WidgetDataStore.localized(key) }

// MARK: - Accessory Inline

struct TimerInlineView: View {
    let entry: TimerEntry

    var body: some View {
        if !entry.isLoggedIn {
            Text(WidgetHelpers.branded(L("widget.login.required")))
        } else if entry.isActive, let deadline = entry.deadline {
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                Text(deadline, style: .timer)
            }
        } else {
            Text(WidgetHelpers.branded(L("widget.timer.none")))
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
                Label(WidgetDataStore.appName, systemImage: "house")
                    .font(.headline)
                Text(L("widget.login.required"))
                    .font(.caption)
            }
        } else if entry.isActive, let deadline = entry.deadline {
            VStack(alignment: .leading, spacing: 2) {
                Label(entry.label, systemImage: "house.fill")
                    .font(.headline)
                Text(deadline, style: .timer)
                    .font(.caption)
                if deadline < Date() {
                    Text(L("widget.timer.overdue"))
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Label(L("widget.timer.title"), systemImage: "house")
                    .font(.headline)
                Text(L("widget.timer.notSet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
