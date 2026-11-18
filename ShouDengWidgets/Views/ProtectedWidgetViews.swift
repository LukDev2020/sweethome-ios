import SwiftUI
import WidgetKit

private func L(_ key: String) -> String { WidgetDataStore.localized(key) }

// MARK: - Accessory Inline

struct ProtectedInlineView: View {
    let entry: ProtectedStatusEntry

    var body: some View {
        switch entry.scenario {
        case .loggedOut:
            Text(WidgetHelpers.branded(L("widget.login.required")))
        case .sosActive:
            Text(WidgetHelpers.branded(L("la.sos.active")))
        case .timerRunning:
            if let deadline = entry.timerDeadline {
                WidgetHelpers.text("widget.timer.home", Text(deadline, style: .timer))
            } else {
                Text(WidgetHelpers.branded(L("la.home.timer")))
            }
        case .overdue:
            Text(WidgetHelpers.branded(L("widget.checkin.due")))
        case .noGuardians:
            Text(WidgetHelpers.branded(L("widget.guardians.setup")))
        case .normal:
            Text(WidgetHelpers.branded(WidgetDataStore.localized("widget.guardians.count", count: entry.guardianCount)))
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
                Label(WidgetDataStore.appName, systemImage: "shield.slash")
                    .font(.headline)
                Text(L("widget.signIn.toSeeStatus"))
                    .font(.caption)
            }
        case .sosActive:
            VStack(alignment: .leading, spacing: 2) {
                Label(L("la.sos.active"), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                if let triggered = entry.sosTriggeredAt {
                    WidgetHelpers.text("widget.sos.elapsed", Text(triggered, style: .relative))
                        .font(.caption)
                }
            }
        case .timerRunning:
            VStack(alignment: .leading, spacing: 2) {
                Label(L("la.home.timer"), systemImage: "house.fill")
                    .font(.headline)
                if let deadline = entry.timerDeadline {
                    WidgetHelpers.text("widget.timer.remaining", Text(deadline, style: .timer))
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
                Label(L("widget.checkin.due"), systemImage: "exclamationmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(WidgetDataStore.localizedFormat("widget.last.short", WidgetHelpers.relativeTimeString(from: entry.lastCheckIn)))
                    .font(.caption)
            }
        case .noGuardians:
            VStack(alignment: .leading, spacing: 2) {
                Label(WidgetDataStore.appName, systemImage: "shield.checkered")
                    .font(.headline)
                Text(L("widget.network.setup"))
                    .font(.caption)
                Text(L("widget.invite.guardians"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .normal:
            VStack(alignment: .leading, spacing: 2) {
                Label(WidgetDataStore.localizedFormat("widget.protected.active", WidgetDataStore.appName), systemImage: "shield.checkered")
                    .font(.headline)
                Text(WidgetDataStore.localized("widget.guardians.protecting", count: entry.guardianCount))
                    .font(.caption)
                Text(WidgetDataStore.localizedFormat("widget.last.checkin", WidgetHelpers.relativeTimeString(from: entry.lastCheckIn)))
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
        case .loggedOut: Text(WidgetDataStore.localizedFormat("widget.signIn.app", WidgetDataStore.appName))
        case .sosActive: Text(L("la.sos.active"))
        case .timerRunning: Text(L("la.home.timer"))
        case .overdue: Text(L("widget.checkin.due"))
        case .noGuardians: Text(L("widget.guardians.setup"))
        case .normal: Text(WidgetDataStore.localizedFormat("widget.protected.active", WidgetDataStore.appName))
        }
    }

    @ViewBuilder
    private var statusSubtitle: some View {
        switch entry.scenario {
        case .loggedOut: Text(L("widget.tapToOpen"))
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
                Text(L("widget.timer.running"))
            }
        case .overdue: Text(WidgetHelpers.relativeTimeString(from: entry.lastCheckIn))
        case .noGuardians: Text(L("widget.invite.family"))
        case .normal: Text(WidgetDataStore.localized("widget.guardians.count", count: entry.guardianCount))
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
                        Text(WidgetDataStore.localizedFormat("widget.updated", WidgetHelpers.relativeTimeString(from: entry.updatedAt)))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
                // Right: guardian count ring OR emergency meds
                if !entry.emergencyMedications.isEmpty {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(Array(entry.emergencyMedications.prefix(2).enumerated()), id: \.offset) { _, med in
                            HStack(spacing: 4) {
                                Image(systemName: "cross.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.orange)
                                Text(med.name)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        if let loc = entry.emergencyMedications.first, !loc.location.isEmpty {
                            Text(loc.location)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                } else {
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
                        Text(L("widget.guardians.label"))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
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
        case .loggedOut: return WidgetDataStore.localizedFormat("widget.signIn.app", WidgetDataStore.appName)
        case .sosActive: return L("la.sos.active")
        case .timerRunning: return L("la.home.timer")
        case .overdue: return L("widget.checkin.due")
        case .noGuardians: return L("widget.network.setup")
        case .normal: return WidgetDataStore.localizedFormat("widget.protected.active", WidgetDataStore.appName)
        }
    }

    private var scenarioDetail: String {
        switch entry.scenario {
        case .loggedOut: return L("widget.tapToSignIn")
        case .sosActive:
            if let t = entry.sosTriggeredAt {
                return WidgetDataStore.localizedFormat("widget.sos.triggeredAgo", WidgetHelpers.relativeTimeString(from: t))
            }
            return L("widget.sos.triggered")
        case .timerRunning: return entry.timerLabel ?? L("widget.timer.inProgress")
        case .overdue: return WidgetDataStore.localizedFormat("widget.last.checkin", WidgetHelpers.relativeTimeString(from: entry.lastCheckIn))
        case .noGuardians: return L("widget.invite.guardians")
        case .normal: return WidgetDataStore.localized("widget.guardians.protecting", count: entry.guardianCount)
        }
    }
}
