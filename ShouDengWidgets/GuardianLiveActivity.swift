import WidgetKit
import SwiftUI
import ActivityKit

struct GuardianLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuardianActivityAttributes.self) { context in
            // MARK: - Lock Screen Banner
            lockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.086, green: 0.129, blue: 0.235))

        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded — Leading
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("守灯守护中")
                            .font(.caption.bold())
                        if let acc = context.state.locationAccuracy {
                            Text("精度 \(acc)m")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // MARK: Expanded — Trailing
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(context.state.protectionLayers) 层守护")
                            .font(.caption.bold())
                        Text(context.state.guardianName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: Expanded — Bottom
                DynamicIslandExpandedRegion(.bottom) {
                    Link(destination: URL(string: "tel:\(context.state.emergencyPhone)")!) {
                        HStack(spacing: 6) {
                            Image(systemName: "phone.fill")
                                .font(.caption)
                            Text("紧急呼叫 \(context.state.emergencyLabel)")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(callButtonColor(context.state.status))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                }

            } compactLeading: {
                // MARK: Compact — Leading
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor(context.state.status))
                        .frame(width: 8, height: 8)
                    Text("守灯")
                        .font(.caption2.bold())
                }
            } compactTrailing: {
                // MARK: Compact — Trailing
                Text("\(context.state.protectionLayers)层")
                    .font(.caption2.bold())
                    .foregroundStyle(Color(red: 0.914, green: 0.271, blue: 0.376))
            } minimal: {
                // MARK: Minimal
                ZStack {
                    Circle()
                        .fill(statusColor(context.state.status).opacity(0.3))
                    Image(systemName: "shield.checkered")
                        .font(.caption2)
                        .foregroundStyle(statusColor(context.state.status))
                }
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<GuardianActivityAttributes>) -> some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 0.914, green: 0.271, blue: 0.376))
                    Text("守灯守护中")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor(context.state.status))
                        .frame(width: 8, height: 8)
                    Text(context.state.statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor(context.state.status))
                }
            }

            // Info rows
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    if let acc = context.state.locationAccuracy {
                        Label("精度 \(acc)m", systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Label {
                        Text(context.state.guardianName)
                            + Text(context.state.guardianOnline ? " · 在线" : " · 离线")
                    } icon: {
                        Image(systemName: "person.fill.checkmark")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(context.state.protectionLayers)")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("层守护")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // Emergency call button
            Link(destination: URL(string: "tel:\(context.state.emergencyPhone)")!) {
                HStack(spacing: 6) {
                    Image(systemName: "phone.fill")
                    Text("紧急呼叫 \(context.state.emergencyLabel)")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(callButtonColor(context.state.status))
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func statusColor(_ status: GuardianActivityAttributes.GuardianStatus) -> Color {
        switch status {
        case .normal: return .green
        case .pendingCheckIn: return .orange
        case .sos: return .red
        case .locationLost: return .yellow
        }
    }

    private func callButtonColor(_ status: GuardianActivityAttributes.GuardianStatus) -> Color {
        status == .sos ? .red : Color(red: 0.914, green: 0.271, blue: 0.376)
    }
}
