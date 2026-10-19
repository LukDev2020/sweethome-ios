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
                        HStack(spacing: 4) {
                            Image(systemName: "shield.checkered")
                                .font(.caption2)
                                .foregroundStyle(SharedColors.lamp)
                            Text(WidgetDataStore.appName)
                                .font(.caption.bold())
                        }
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
                    Image(systemName: "shield.checkered")
                        .font(.caption2)
                        .foregroundStyle(SharedColors.lamp)
                    Text(WidgetDataStore.appName)
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
        VStack(spacing: 8) {
            // Header row: app name + status + guardians
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "shield.checkered")
                        .font(.caption2)
                        .foregroundStyle(SharedColors.lamp)
                    Text(WidgetDataStore.appName)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }

                Spacer()

                // Guardian avatars (compact inline)
                HStack(spacing: -6) {
                    ForEach(Array(context.state.guardians.prefix(3).enumerated()), id: \.offset) { _, guardian in
                        ZStack {
                            Circle()
                                .fill(guardian.isOnline ? SharedColors.safe.opacity(0.4) : SharedColors.offline.opacity(0.3))
                                .frame(width: 24, height: 24)
                            Text(guardian.initial)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if guardian.isOnline {
                                Circle()
                                    .fill(SharedColors.safe)
                                    .frame(width: 7, height: 7)
                                    .overlay(Circle().stroke(SharedColors.ink, lineWidth: 1.5))
                            }
                        }
                    }
                }

                // Status badge
                HStack(spacing: 3) {
                    Circle()
                        .fill(protectedStatusColor(context.state.status))
                        .frame(width: 6, height: 6)
                    Text(context.state.statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(protectedStatusColor(context.state.status))
                }
            }

            // Timer or check-in (if applicable, compact single line)
            if let timer = context.state.homeTimerDeadline {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("回家倒计时")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(timer, style: .timer)
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.white)
                }
            } else if let lastCI = context.state.lastCheckIn {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("上次报平安")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(lastCI, style: .relative)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                }
            }

            // Emergency Medical Info — compact 2-line layout
            if hasEmergencyInfo(context.state) {
                VStack(alignment: .leading, spacing: 4) {
                    // Line 1: blood type + allergies + conditions
                    HStack(spacing: 6) {
                        Image(systemName: "staroflife.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)

                        if let blood = context.state.bloodType, !blood.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "drop.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.red)
                                Text(blood)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        if !context.state.allergies.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.yellow)
                                Text("过敏: " + context.state.allergies.prefix(2).joined(separator: "、"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                        }
                        if !context.state.conditions.isEmpty {
                            Text(context.state.conditions.prefix(2).joined(separator: "、"))
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }

                    // Line 2: emergency medications + note
                    if !context.state.emergencyMedications.isEmpty || (context.state.emergencyNote != nil && !(context.state.emergencyNote?.isEmpty ?? true)) {
                        HStack(spacing: 6) {
                            ForEach(Array(context.state.emergencyMedications.prefix(2).enumerated()), id: \.offset) { _, med in
                                HStack(spacing: 2) {
                                    Image(systemName: "cross.circle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.orange)
                                    Text(med.name)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                    if !med.location.isEmpty {
                                        Text("(\(med.location))")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.white.opacity(0.6))
                                    }
                                }
                            }
                            if let note = context.state.emergencyNote, !note.isEmpty {
                                Text(note)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Action buttons (compact, 3 buttons)
            HStack(spacing: 6) {
                Link(destination: URL(string: "shoudeng://sos")!) {
                    HStack(spacing: 2) {
                        Image(systemName: "sos")
                            .font(.system(size: 9))
                        Text("求助")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(context.state.status == .sosActive ? .red : SharedColors.lamp)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                Link(destination: URL(string: "shoudeng://checkin")!) {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                        Text("平安")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(SharedColors.safe.opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                Link(destination: URL(string: "shoudeng://share-location")!) {
                    HStack(spacing: 2) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9))
                        Text("位置")
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(.blue.opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func hasEmergencyInfo(_ state: ProtectedActivityAttributes.ContentState) -> Bool {
        (state.bloodType != nil && !(state.bloodType?.isEmpty ?? true))
        || !state.allergies.isEmpty
        || !state.conditions.isEmpty
        || !state.emergencyMedications.isEmpty
        || (state.emergencyNote != nil && !(state.emergencyNote?.isEmpty ?? true))
    }

    private func protectedStatusColor(_ status: ProtectedActivityAttributes.OverallStatus) -> Color {
        switch status {
        case .normal: return SharedColors.safe
        case .sosActive: return SharedColors.alert
        case .timerRunning: return .blue
        case .pendingCheckIn: return SharedColors.warning
        }
    }
}
