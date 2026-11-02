import WidgetKit
import SwiftUI
import ActivityKit

/// Lock screen Live Activity for the **被关怀者 (Protected Person)**.
/// Shows: who is guarding you, your status, SOS + check-in buttons.
struct ProtectedLiveActivity: Widget {

    private func L(_ key: String) -> String { WidgetDataStore.localized(key) }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProtectedActivityAttributes.self) { context in
            ProtectedLockScreenCard(state: context.state)
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
                            Text("\(onDuty.first!.name) \(L("la.on.duty"))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(context.state.guardians.count)\(L("la.guardians"))")
                            .font(.caption.bold())
                        let online = context.state.guardians.filter(\.isOnline).count
                        Text("\(online)\(L("la.online"))")
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
                                Text(L("la.sos.button"))
                                    .font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                        // Check-in button (acts without opening the app)
                        Button(intent: LockScreenCheckInIntent()) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                Text(L("la.checkin.button"))
                                    .font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(SharedColors.safe.opacity(0.8))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
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
                    Text("\(g.name) \(L("la.on.duty"))")
                        .font(.caption2.bold())
                        .foregroundStyle(SharedColors.lamp)
                } else {
                    Text("\(context.state.guardians.count)\(L("la.guardians"))")
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
