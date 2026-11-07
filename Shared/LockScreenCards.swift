import SwiftUI

// MARK: - Lock-screen cards (Live Activity)
//
// The lock-screen layouts of both Live Activities. They live here, compiled into the
// widget *and* the app, so the app can show them in a Debug preview gallery
// (`-la-gallery`) exactly as the widget draws them.
//
// Fixed layout: every row is always there, with "—" when there is no data yet, so a
// card keeps the same size whether or not the family is set up.

/// The app's logo on a small white disc (readable on every card background). The
/// widget has its own small copy of "AppLogo" in its asset catalog.
struct CardLogo: View {
    let size: CGFloat
    var body: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFit()
            .padding(size * 0.08)
            .frame(width: size, height: size)
            .background(Circle().fill(.white))
            .accessibilityHidden(true)
    }
}

/// Protected person: who guards me, last check-in, home countdown, latest family
/// activity, emergency medical info, and SOS / OK / Location — the rows chosen in
/// Settings → Lock screen card, at the chosen text size and colours.
struct ProtectedLockScreenCard: View {
    let state: ProtectedActivityAttributes.ContentState
    /// Settings preview passes the style being edited; the widget uses the card's own
    var style: LockScreenCardStyle? = nil

    private func L(_ key: String) -> String { WidgetDataStore.localized(key) }
    private let dash = "—"
    private var st: LockScreenCardStyle { style ?? state.cardStyle ?? .stored }
    private var s: CGFloat { st.s }
    private var primary: Color { st.theme.primary }
    private var secondary: Color { st.theme.secondary }
    private var accent: Color { st.accent.color }

    var body: some View {
        if let rider = state.rider {
            // The SOS version has four rows: it keeps the standard size to fit 160 pt
            RiderLockScreenCard(state: state, rider: rider,
                                style: state.status == .sosActive ? st.with(textSize: .standard) : st)
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        VStack(alignment: .leading, spacing: LockScreenCardStyle.rowSpacing) {
            header
            ForEach(st.visibleSections, id: \.self) { section in
                switch section {
                case .checkIn: checkInRow
                case .latest: latestRow
                case .medical: medicalRow
                case .actions: actionsRow
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, LockScreenCardStyle.verticalPadding)
    }

    // 1. Logo · app · who is guarding me · status
    private var header: some View {
        HStack(spacing: 7 * s) {
            CardLogo(size: 22 * s)
            Text(WidgetDataStore.appName)
                .font(.system(size: 15 * s, weight: .bold))
                .foregroundStyle(primary)
                .lineLimit(1)
                .layoutPriority(1)
            HStack(spacing: -5 * s) {
                ForEach(0..<3, id: \.self) { i in
                    guardianSlot(i < state.guardians.count ? state.guardians[i] : nil)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8 * s, height: 8 * s)
                Text(state.statusText)
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(height: st.headerHeight)
    }

    // 2. Last check-in · home countdown
    private var checkInRow: some View {
        HStack(spacing: 12) {
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
        .frame(height: st.height(of: .checkIn))
    }

    // 3. Latest family activity (or the location just sent)
    private var latestRow: some View {
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
        .frame(height: st.height(of: .latest))
    }

    // 4. Emergency medical info — for first responders
    private var medicalRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "staroflife.fill")
                .font(.system(size: 12 * s))
                .foregroundStyle(.orange)
            Text(medicalLine(state))
                .font(.system(size: 13 * s, weight: .medium))
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: st.height(of: .medical))
        .background(Color.orange.opacity(st.theme.isLight ? 0.18 : 0.2))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    // 5. Actions. SOS opens the app to confirm and count down; "OK" and "Location"
    // act right here without opening the app.
    private var actionsRow: some View {
        HStack(spacing: 6) {
            Link(destination: URL(string: "shoudeng://sos")!) {
                actionLabel("exclamationmark.triangle.fill", L("la.sos.button"))
                    .background(SharedColors.alert)
                    .clipShape(Capsule())
            }
            Button(intent: LockScreenCheckInIntent()) {
                actionLabel("checkmark.circle.fill", L("la.checkin.button"))
                    .background(SharedColors.safe.opacity(0.9))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Button(intent: LockScreenShareLocationIntent()) {
                actionLabel("location.fill", L("la.location.button"))
                    .background(accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(height: st.height(of: .actions))
    }

    private func guardianSlot(_ guardian: ProtectedActivityAttributes.GuardianInfo?) -> some View {
        ZStack {
            if let guardian {
                Circle()
                    .fill(guardian.isOnline ? SharedColors.safe.opacity(0.75) : SharedColors.offline.opacity(0.6))
                Text(guardian.initial)
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .font(.system(size: 11 * s, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .strokeBorder(secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .background(Circle().fill(st.theme.background))
            }
        }
        .frame(width: 22 * s, height: 22 * s)
    }

    private func field<V: View>(icon: String, label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12 * s))
                .foregroundStyle(accent)
            // The label gives way first; the value (time, countdown) is what matters
            Text(label)
                .font(.system(size: 13 * s))
                .foregroundStyle(secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            value()
                .font(.system(size: 15 * s, weight: .semibold))
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionLabel(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13 * s, weight: .semibold))
            Text(title)
                .font(.system(size: 14 * s, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: st.height(of: .actions))
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

    private var statusColor: Color {
        switch state.status {
        case .normal: return SharedColors.safe
        case .sosActive: return SharedColors.alert
        case .timerRunning: return st.theme.isLight ? .blue : Color(red: 0.45, green: 0.7, blue: 1)
        case .pendingCheckIn: return SharedColors.warning
        }
    }
}

/// Rider mode. On shift: shift time, crew nearby, planned end; SOS · OK · Report.
/// During an SOS it is written for whoever picks up the phone: the street, who is
/// coming, "press hard on the wound", and Call 000 / I'm safe (both open the app —
/// ending an SOS asks for Face ID or the passcode).
struct RiderLockScreenCard: View {
    let state: ProtectedActivityAttributes.ContentState
    let rider: RiderCardInfo
    let style: LockScreenCardStyle

    private func L(_ key: String) -> String { WidgetDataStore.localized(key) }
    private var s: CGFloat { style.s }
    private var primary: Color { style.theme.primary }
    private var secondary: Color { style.theme.secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: LockScreenCardStyle.rowSpacing) {
            if state.status == .sosActive { sosBody } else { shiftBody }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, LockScreenCardStyle.verticalPadding)
    }

    // MARK: On / off shift

    @ViewBuilder
    private var shiftBody: some View {
        HStack(spacing: 7 * s) {
            CardLogo(size: 22 * s)
            Image(systemName: "bicycle").font(.system(size: 14 * s, weight: .semibold)).foregroundStyle(style.accent.color)
            if let started = rider.shiftStartedAt {
                Text(L("la.rider.onShift")).font(.system(size: 15 * s, weight: .bold)).foregroundStyle(primary)
                Text(started, style: .timer).font(.system(size: 15 * s, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(primary).lineLimit(1).frame(maxWidth: 70 * s, alignment: .leading)
            } else {
                Text(L("la.rider.offShift")).font(.system(size: 15 * s, weight: .bold)).foregroundStyle(primary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Circle().fill(rider.crewOnShiftNearby > 0 ? SharedColors.safe : SharedColors.offline).frame(width: 8 * s, height: 8 * s)
                Text(rider.crewOnShiftNearby > 0 ? "\(rider.crewOnShiftNearby)\(L("la.rider.crewNearby"))" : L("la.rider.noCrew"))
                    .font(.system(size: 13 * s, weight: .semibold)).foregroundStyle(secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(height: style.headerHeight)

        HStack(spacing: 12) {
            row(icon: "clock.badge.checkmark") {
                if let end = rider.checkDueAt { Text(L("la.rider.checkAt")) + Text(end, style: .time) } else { Text("—") }
            }
            row(icon: "checkmark.circle") {
                if let ci = state.lastCheckIn { Text(L("la.last.checkin") + " ") + Text(ci, style: .time) } else { Text("—") }
            }
        }
        .frame(height: style.height(of: .checkIn))

        HStack(spacing: 6) {
            Link(destination: URL(string: "shoudeng://sos")!) {
                button("exclamationmark.triangle.fill", L("la.sos.button"), SharedColors.alert)
            }
            Button(intent: LockScreenCheckInIntent()) {
                button("checkmark.circle.fill", L("la.checkin.button"), SharedColors.safe.opacity(0.9))
            }
            .buttonStyle(.plain)
            Link(destination: URL(string: "shoudeng://rider-report")!) {
                button("exclamationmark.shield.fill", L("la.rider.report"), style.accent.color)
            }
        }
        .frame(height: style.height(of: .actions))
    }

    // MARK: SOS — for the rider or a bystander

    @ViewBuilder
    private var sosBody: some View {
        HStack(spacing: 7 * s) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15 * s)).foregroundStyle(.white)
            Text(L("la.sos.active")).font(.system(size: 15 * s, weight: .bold)).foregroundStyle(.white)
            Spacer(minLength: 4)
            Group {
                if let helper = rider.helperName {
                    Text(helper + L("la.rider.onTheWay")) + Text(rider.helperDistanceM.map { " · \(Self.distance($0))" } ?? "")
                } else {
                    Text(L("la.rider.crewAlerted"))
                }
            }
            .font(.system(size: 13 * s, weight: .semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .frame(height: style.headerHeight)
        .background(RoundedRectangle(cornerRadius: 8).fill(SharedColors.alert))

        Label(rider.sosAddress ?? "—", systemImage: "mappin.and.ellipse")
            .font(.system(size: 17 * s, weight: .bold)).foregroundStyle(primary)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(height: style.height(of: .medical))

        Text(L("la.rider.helping") + state.emergencyPhone)
            .font(.system(size: 13 * s, weight: .semibold)).foregroundStyle(SharedColors.alert)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(height: style.height(of: .latest))

        HStack(spacing: 6) {
            Link(destination: URL(string: "shoudeng://call-emergency")!) {
                button("phone.fill", L("la.rider.call") + state.emergencyPhone, SharedColors.alert)
            }
            Link(destination: URL(string: "shoudeng://open")!) {
                button("checkmark.shield.fill", L("la.rider.safe"), SharedColors.safe.opacity(0.9))
            }
        }
        .frame(height: style.height(of: .actions))
    }

    private func row<V: View>(icon: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12 * s)).foregroundStyle(style.accent.color)
            value().font(.system(size: 14 * s, weight: .semibold)).foregroundStyle(primary).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func button(_ icon: String, _ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 13 * s, weight: .semibold))
            Text(title).font(.system(size: 14 * s, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: style.height(of: .actions))
        .background(color)
        .clipShape(Capsule())
    }

    static func distance(_ meters: Int) -> String {
        meters >= 1000 ? String(format: "%.1f km", Double(meters) / 1000) : "\(max(10, (meters / 10) * 10)) m"
    }
}

/// Guardian: family rows (status, city, last check-in, battery) — as many as fit at
/// the chosen text size — and a call button.
struct GuardianLockScreenCard: View {
    let state: GuardianActivityAttributes.ContentState
    var style: LockScreenCardStyle? = nil

    private func L(_ key: String) -> String { WidgetDataStore.localized(key) }
    private let dash = "—"
    private var st: LockScreenCardStyle { style ?? state.cardStyle ?? .stored }
    private var s: CGFloat { st.s }
    private var primary: Color { st.theme.primary }
    private var secondary: Color { st.theme.secondary }

    var body: some View {
        let sorted = prioritySorted(state.persons)
        let rows = st.guardianPersonRows

        VStack(spacing: LockScreenCardStyle.rowSpacing) {
            // Header
            HStack(spacing: 7 * s) {
                CardLogo(size: 20 * s)
                Text(sorted.isEmpty
                     ? "\(WidgetDataStore.appName) · \(L("la.persons.none"))"
                     : "\(WidgetDataStore.appName) · \(sorted.count)\(L("la.persons.count"))")
                    .font(.system(size: 15 * s, weight: .bold))
                    .foregroundStyle(primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if sorted.count > rows {
                    // More people than rows at this text size
                    Text("+\(sorted.count - rows)")
                        .font(.system(size: 13 * s, weight: .semibold))
                        .foregroundStyle(secondary)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(sorted.isEmpty ? SharedColors.offline : overallStatusColor(state.overallStatus))
                        .frame(width: 8 * s, height: 8 * s)
                    Text(sorted.isEmpty ? dash : state.overallStatusText)
                        .font(.system(size: 13 * s, weight: .semibold))
                        .foregroundStyle(sorted.isEmpty ? secondary : overallStatusColor(state.overallStatus))
                        .lineLimit(1)
                }
            }
            .frame(height: st.guardianHeaderHeight)

            // Person rows, empty slots included
            ForEach(0..<rows, id: \.self) { i in
                personRow(i < sorted.count ? sorted[i] : nil)
            }

            // Bottom button: call whoever needs attention most, else open the app
            if !state.priorityPersonPhone.isEmpty,
               let url = URL(string: "tel:\(state.priorityPersonPhone)") {
                Link(destination: url) {
                    bottomButton(icon: "phone.fill",
                                 title: L("la.call") + state.priorityPersonName,
                                 color: state.overallStatus == .sosAlert ? .red : st.accent.color)
                }
            } else {
                Link(destination: URL(string: "shoudeng://open")!) {
                    bottomButton(icon: "arrow.up.forward.app", title: L("la.open.app"),
                                 color: st.theme.isLight ? SharedColors.ink.opacity(0.75) : .white.opacity(0.18))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, LockScreenCardStyle.verticalPadding)
    }

    @ViewBuilder
    private func personRow(_ person: GuardianActivityAttributes.PersonInfo?) -> some View {
        HStack(spacing: 7) {
            ZStack {
                if let person {
                    Circle().fill(personStatusColor(person.status).opacity(0.75))
                    Text(person.initial)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .font(.system(size: 10 * s, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(secondary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            .frame(width: 20 * s, height: 20 * s)

            if let person {
                Text(person.displayName)
                    .font(.system(size: 15 * s, weight: .semibold))
                    .foregroundStyle(primary)
                    .lineLimit(1)
                Text(personStatusLabel(person))
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(personStatusColor(person.status))
                    .lineLimit(1)
                if s < 1.2 {
                    Text(person.cityName.isEmpty ? dash : person.cityName)
                        .font(.system(size: 13 * s))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            } else {
                Text(L("la.slot.empty"))
                    .font(.system(size: 13 * s))
                    .foregroundStyle(secondary)
            }

            Spacer(minLength: 4)

            // Last check-in time
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 11 * s))
                if let ci = person?.lastCheckIn {
                    Text(ci, style: .time)
                } else {
                    Text(dash)
                }
            }
            .font(.system(size: 13 * s))
            .foregroundStyle(secondary)
            .lineLimit(1)
            .fixedSize()

            // Battery
            HStack(spacing: 2) {
                let battery = person?.batteryLevel
                Image(systemName: battery.map(batteryIcon) ?? "battery.0")
                    .font(.system(size: 11 * s))
                Text(battery.map { "\(Int($0 * 100))%" } ?? dash)
            }
            .font(.system(size: 13 * s))
            .foregroundStyle((person?.batteryLevel ?? 1) < 0.2 ? SharedColors.alert : secondary)
            .lineLimit(1)
            .fixedSize()
        }
        .frame(height: st.guardianRowHeight)
    }

    private func bottomButton(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .font(.system(size: 15 * s))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: st.guardianButtonHeight)
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
                .background(LockScreenCardStyle.stored.theme.background)
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
