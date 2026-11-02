import SwiftUI

// MARK: - Lock-screen cards (Live Activity)
//
// The lock-screen layouts of both Live Activities. They live here, compiled into the
// widget *and* the app, so the app can show them in a Debug preview gallery
// (`-la-gallery`) exactly as the widget draws them.
//
// Fixed layout: every row is always there, with "—" when there is no data yet, so a
// card keeps the same size whether or not the family is set up.

/// Protected person: who guards me, last check-in, home countdown, latest family
/// activity, emergency medical info, and SOS / OK / Location.
struct ProtectedLockScreenCard: View {
    let state: ProtectedActivityAttributes.ContentState

    private func L(_ key: String) -> String { WidgetDataStore.localized(key) }
    private let dash = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // 1. App · who is guarding me (3 slots) · status
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "shield.checkered")
                        .font(.caption2)
                        .foregroundStyle(SharedColors.lamp)
                    Text(WidgetDataStore.appName)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                HStack(spacing: -5) {
                    ForEach(0..<3, id: \.self) { i in
                        guardianSlot(i < state.guardians.count ? state.guardians[i] : nil)
                    }
                }
                Text(state.guardians.isEmpty
                     ? L("la.guardians.none")
                     : "\(state.guardians.count)\(L("la.guardians"))")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    Circle()
                        .fill(protectedStatusColor(state.status))
                        .frame(width: 6, height: 6)
                    Text(state.statusText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(protectedStatusColor(state.status))
                        .lineLimit(1)
                }
            }
            .frame(height: 22)

            // 2. Last check-in · home countdown
            HStack(spacing: 10) {
                field(icon: "checkmark.circle", label: L("la.last.checkin")) {
                    if let ci = state.lastCheckIn {
                        Text(ci, style: .time)
                    } else {
                        Text(dash)
                    }
                }
                field(icon: "timer", label: L("la.home.countdown")) {
                    if let deadline = state.homeTimerDeadline {
                        Text(deadline, style: .timer).monospacedDigit()
                    } else {
                        Text(dash)
                    }
                }
            }

            // 3. Latest family activity (or the location just sent)
            field(icon: "bubble.left", label: L("la.latest")) {
                if let shared = state.lastLocationShare,
                   shared > (state.latestUpdateAt ?? .distantPast) {
                    Text("\(L("la.location.sent")) · ") + Text(shared, style: .time)
                } else if let latest = state.latestUpdate, !latest.isEmpty {
                    Text(latest)
                } else {
                    Text(dash)
                }
            }

            // 4. Emergency medical info — for first responders
            HStack(spacing: 6) {
                Image(systemName: "staroflife.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                Text(medicalLine(state))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Color.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // 5. Actions. SOS opens the app to confirm and count down; "OK" and
            // "Location" act right here without opening the app.
            HStack(spacing: 6) {
                Link(destination: URL(string: "shoudeng://sos")!) {
                    actionLabel("sos", L("la.sos.button"))
                        .background(state.status == .sosActive ? .red : SharedColors.alert)
                        .clipShape(Capsule())
                }
                Button(intent: LockScreenCheckInIntent()) {
                    actionLabel("checkmark.circle.fill", L("la.checkin.button"))
                        .background(SharedColors.safe.opacity(0.85))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button(intent: LockScreenShareLocationIntent()) {
                    actionLabel("location.fill", L("la.location.button"))
                        .background(Color.blue.opacity(0.8))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func guardianSlot(_ guardian: ProtectedActivityAttributes.GuardianInfo?) -> some View {
        ZStack {
            if let guardian {
                Circle()
                    .fill(guardian.isOnline ? SharedColors.safe.opacity(0.45) : SharedColors.offline.opacity(0.35))
                Text(guardian.initial)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .background(Circle().fill(SharedColors.ink))
            }
        }
        .frame(width: 20, height: 20)
    }

    private func field<V: View>(icon: String, label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.55))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .layoutPriority(1)
            value()
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 15)
    }

    private func actionLabel(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }

    /// "Blood A+ · Allergies: Penicillin · Meds Nitroglycerin (bag)", "—" for anything missing.
    private func medicalLine(_ state: ProtectedActivityAttributes.ContentState) -> String {
        let blood = state.bloodType.flatMap { $0.isEmpty ? nil : $0 } ?? dash
        let allergies = state.allergies.isEmpty ? dash : state.allergies.prefix(2).joined(separator: ", ")
        let meds: String = state.emergencyMedications.first.map { med in
            med.location.isEmpty ? med.name : "\(med.name) (\(med.location))"
        } ?? dash
        return "\(L("la.blood"))\(blood) · \(L("la.allergy"))\(allergies) · \(L("la.meds"))\(meds)"
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

/// Guardian: three family rows (status, city, last check-in, battery) and a call button.
struct GuardianLockScreenCard: View {
    let state: GuardianActivityAttributes.ContentState

    private func L(_ key: String) -> String { WidgetDataStore.localized(key) }
    private let dash = "—"

    var body: some View {
        let sorted = prioritySorted(state.persons)

        VStack(spacing: 6) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    // (The app's logo image isn't in the widget's asset catalog.)
                    Image(systemName: "shield.checkered")
                        .font(.caption)
                        .foregroundStyle(SharedColors.lamp)
                    Text(sorted.isEmpty
                         ? "\(WidgetDataStore.appName) · \(L("la.persons.none"))"
                         : "\(WidgetDataStore.appName) · \(sorted.count)\(L("la.persons.count"))")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(sorted.isEmpty ? SharedColors.offline : overallStatusColor(state.overallStatus))
                        .frame(width: 7, height: 7)
                    Text(sorted.isEmpty ? dash : state.overallStatusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(sorted.isEmpty ? .white.opacity(0.5) : overallStatusColor(state.overallStatus))
                }
            }
            .frame(height: 20)

            // Three person rows, empty slots included
            ForEach(0..<3, id: \.self) { i in
                personRow(i < sorted.count ? sorted[i] : nil)
            }

            // Bottom button: call whoever needs attention most, else open the app
            if !state.priorityPersonPhone.isEmpty,
               let url = URL(string: "tel:\(state.priorityPersonPhone)") {
                Link(destination: url) {
                    bottomButton(icon: "phone.fill",
                                 title: L("la.call") + state.priorityPersonName,
                                 color: callButtonColor(state.overallStatus))
                }
            } else {
                Link(destination: URL(string: "shoudeng://open")!) {
                    bottomButton(icon: "arrow.up.forward.app", title: L("la.open.app"), color: .white.opacity(0.15))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func personRow(_ person: GuardianActivityAttributes.PersonInfo?) -> some View {
        HStack(spacing: 7) {
            ZStack {
                if let person {
                    Circle().fill(personStatusColor(person.status).opacity(0.35))
                    Text(person.initial)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            .frame(width: 20, height: 20)

            if let person {
                Text(person.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(personStatusLabel(person))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(personStatusColor(person.status))
                    .lineLimit(1)
                Text(person.cityName.isEmpty ? dash : person.cityName)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            } else {
                Text(L("la.slot.empty"))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer(minLength: 4)

            // Last check-in time
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 9))
                if let ci = person?.lastCheckIn {
                    Text(ci, style: .time)
                } else {
                    Text(dash)
                }
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(person == nil ? 0.3 : 0.6))
            .frame(width: 62, alignment: .trailing)

            // Battery
            HStack(spacing: 2) {
                let battery = person?.batteryLevel
                Image(systemName: battery.map(batteryIcon) ?? "battery.0")
                    .font(.system(size: 9))
                Text(battery.map { "\(Int($0 * 100))%" } ?? dash)
            }
            .font(.caption2)
            .foregroundStyle((person?.batteryLevel ?? 1) < 0.2 ? SharedColors.alert : .white.opacity(person == nil ? 0.3 : 0.6))
            .frame(width: 44, alignment: .trailing)
        }
        .frame(height: 22)
    }

    private func bottomButton(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .font(.footnote)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(color)
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func overallStatusColor(_ status: GuardianActivityAttributes.OverallStatus) -> Color {
        switch status {
        case .allSafe: return SharedColors.safe
        case .needsAttention: return SharedColors.warning
        case .sosAlert: return SharedColors.alert
        }
    }

    private func personStatusColor(_ status: GuardianActivityAttributes.PersonStatus) -> Color {
        switch status {
        case .normal: return SharedColors.safe
        case .overdue: return SharedColors.warning
        case .alert: return SharedColors.alert
        case .unreachable: return SharedColors.offline
        }
    }

    private func personStatusLabel(_ person: GuardianActivityAttributes.PersonInfo) -> String {
        switch person.status {
        case .normal: return L("la.safe")
        case .overdue: return L("la.overdue")
        case .alert: return L("la.alert")
        case .unreachable: return L("la.offline")
        }
    }

    private func callButtonColor(_ status: GuardianActivityAttributes.OverallStatus) -> Color {
        status == .sosAlert ? .red : SharedColors.lamp
    }

    private func batteryIcon(_ level: Double) -> String {
        if level > 0.75 { return "battery.100" }
        if level > 0.50 { return "battery.75" }
        if level > 0.25 { return "battery.50" }
        return "battery.25"
    }

    private func prioritySorted(_ persons: [GuardianActivityAttributes.PersonInfo]) -> [GuardianActivityAttributes.PersonInfo] {
        persons.sorted { a, b in
            statusPriority(a.status) > statusPriority(b.status)
        }
    }

    private func statusPriority(_ status: GuardianActivityAttributes.PersonStatus) -> Int {
        switch status {
        case .alert: return 3
        case .overdue: return 2
        case .unreachable: return 1
        case .normal: return 0
        }
    }
}

#if DEBUG
// MARK: - Preview gallery (Debug only)
//
// Launch with `-la-gallery` (optionally `-app_language zh-Hans`) to see all four states
// at lock-screen size: full / empty, for each role.

extension ProtectedActivityAttributes.ContentState {
    static func sample(full: Bool, now: Date = Date()) -> Self {
        .init(
            status: full ? .timerRunning : .normal,
            statusText: WidgetDataStore.localized(full ? "la.home.timer" : "la.normal"),
            guardians: full ? [
                .init(name: "Sarah", initial: "S", isOnDuty: true, isOnline: true),
                .init(name: "Kevin", initial: "K", isOnDuty: false, isOnline: false),
            ] : [],
            lastCheckIn: full ? now.addingTimeInterval(-25 * 60) : nil,
            homeTimerDeadline: full ? now.addingTimeInterval(18 * 60) : nil,
            homeTimerLabel: nil,
            emergencyPhone: "120",
            emergencyLabel: "120",
            bloodType: full ? "A+" : nil,
            allergies: full ? ["青霉素"] : [],
            conditions: [],
            emergencyNote: nil,
            emergencyMedications: full ? [.init(name: "硝酸甘油", location: "包里", dosage: "")] : [],
            latestUpdate: full ? "Sarah：妈，到家了吗？" : nil,
            latestUpdateAt: full ? now.addingTimeInterval(-6 * 60) : nil
        )
    }
}

extension GuardianActivityAttributes.ContentState {
    static func sample(full: Bool, now: Date = Date()) -> Self {
        .init(
            overallStatus: full ? .needsAttention : .allSafe,
            overallStatusText: WidgetDataStore.localized(full ? "la.needs.attention" : "la.all.safe"),
            persons: full ? [
                .init(id: "1", displayName: "妈妈", initial: "妈", status: .normal, cityName: "成都",
                      lastCheckIn: now.addingTimeInterval(-25 * 60), batteryLevel: 0.82),
                .init(id: "2", displayName: "爸爸", initial: "爸", status: .overdue, cityName: "成都",
                      lastCheckIn: now.addingTimeInterval(-9 * 3600), batteryLevel: 0.15),
            ] : [],
            priorityPersonName: full ? "爸爸" : "",
            priorityPersonPhone: full ? "+8613800138000" : "",
            updatedAt: now
        )
    }
}

/// The four cards on a lock-screen-like background, at the system's card width
/// (screen − 2 × 14 pt) and within its 160 pt height limit (red outline = limit).
struct LockScreenCardGallery: View {
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    item("被守护者 · 有数据", ProtectedLockScreenCard(state: .sample(full: true)), width: geo.size.width - 28)
                    item("被守护者 · 空白", ProtectedLockScreenCard(state: .sample(full: false)), width: geo.size.width - 28)
                    item("守护者 · 有数据", GuardianLockScreenCard(state: .sample(full: true)), width: geo.size.width - 28)
                    item("守护者 · 空白", GuardianLockScreenCard(state: .sample(full: false)), width: geo.size.width - 28)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 20)
            }
            .background(
                LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
        }
    }

    private func item<V: View>(_ title: String, _ card: V, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            card
                .frame(width: width)
                .background(SharedColors.ink)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .top) {
                    // The lock screen cuts a card off at 160 pt
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.red.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: width, height: 160)
                }
        }
    }
}
#endif
