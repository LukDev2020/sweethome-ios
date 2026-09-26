import WidgetKit
import SwiftUI
import ActivityKit

/// Lock screen Live Activity for the **被关怀者 (Protected Person)**.
/// Shows: who is guarding you, your status, SOS + check-in buttons.
struct ProtectedLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProtectedActivityAttributes.self) { context in
            protectedLockScreenView(context: context)
                .activityBackgroundTint(SharedColors.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("守灯守护中")
                            .font(.caption.bold())
                        let onDuty = context.state.guardians.filter(\.isOnDuty)
                        if !onDuty.isEmpty {
                            Text("\(onDuty.first!.name)值班中")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(context.state.guardians.count)位守护者")
                            .font(.caption.bold())
                        let online = context.state.guardians.filter(\.isOnline).count
                        Text("\(online)人在线")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        // SOS button
                        Link(destination: URL(string: "shoudeng://sos")!) {
                            HStack(spacing: 4) {
                                Image(systemName: "sos")
                                    .font(.caption)
                                Text("紧急求助")
                                    .font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                        // Check-in button
                        Link(destination: URL(string: "shoudeng://checkin")!) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                Text("报平安")
                                    .font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(SharedColors.safe.opacity(0.8))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(protectedStatusColor(context.state.status))
                        .frame(width: 8, height: 8)
                    Text("守灯")
                        .font(.caption2.bold())
                }
            } compactTrailing: {
                let onDuty = context.state.guardians.first(where: \.isOnDuty)
                if let g = onDuty {
                    Text("\(g.name)值班")
                        .font(.caption2.bold())
                        .foregroundStyle(SharedColors.lamp)
                } else {
                    Text("\(context.state.guardians.count)位守护")
                        .font(.caption2.bold())
                        .foregroundStyle(SharedColors.lamp)
                }
            } minimal: {
                ZStack {
                    Circle()
                        .fill(protectedStatusColor(context.state.status).opacity(0.3))
                    Image(systemName: "shield.checkered")
                        .font(.caption2)
                        .foregroundStyle(protectedStatusColor(context.state.status))
                }
            }
        }
    }

    // MARK: - Lock Screen Banner

    @ViewBuilder
    private func protectedLockScreenView(context: ActivityViewContext<ProtectedActivityAttributes>) -> some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                        .font(.subheadline)
                        .foregroundStyle(SharedColors.lamp)
                    Text("守灯守护中")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(protectedStatusColor(context.state.status))
                        .frame(width: 8, height: 8)
                    Text(context.state.statusText)
                        .font(.caption)
                        .foregroundStyle(protectedStatusColor(context.state.status))
                }
            }

            // Guardian avatars row
            HStack(spacing: 12) {
                ForEach(Array(context.state.guardians.prefix(3).enumerated()), id: \.offset) { _, guardian in
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(guardian.isOnline ? SharedColors.safe.opacity(0.3) : SharedColors.offline.opacity(0.3))
                                .frame(width: 36, height: 36)
                            Text(guardian.initial)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                            // Online indicator dot
                            if guardian.isOnline {
                                Circle()
                                    .fill(SharedColors.safe)
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(SharedColors.ink, lineWidth: 2))
                                    .offset(x: 12, y: 12)
                            }
                        }
                        Text(guardian.name)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(guardian.isOnDuty ? "值班中" : "离线")
                            .font(.system(size: 9))
                            .foregroundStyle(guardian.isOnDuty ? SharedColors.safe : .white.opacity(0.4))
                    }
                }
                Spacer()
                // Last check-in info
                VStack(alignment: .trailing, spacing: 2) {
                    if let timer = context.state.homeTimerDeadline {
                        Text("回家倒计时")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(timer, style: .timer)
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(.white)
                    } else if let lastCI = context.state.lastCheckIn {
                        Text("上次报平安")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(lastCI, style: .relative)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                Link(destination: URL(string: "shoudeng://sos")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "sos")
                            .font(.caption)
                        Text("紧急求助")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(context.state.status == .sosActive ? .red : SharedColors.lamp)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                Link(destination: URL(string: "shoudeng://checkin")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("报平安")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SharedColors.safe.opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func protectedStatusColor(_ status: ProtectedActivityAttributes.OverallStatus) -> Color {
        switch status {
        case .normal: return SharedColors.safe
        case .sosActive: return SharedColors.alert
        case .timerRunning: return .blue
        case .pendingCheckIn: return SharedColors.warning
        }
    }
}
