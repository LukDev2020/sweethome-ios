import SwiftUI

// MARK: - Guardian Records, Schedule & Contacts
//
// Combined view with segmented control:
//   - Timeline: my own events plus those of everyone I look after (GET /v1/timeline?personId=)
//   - Duty Schedule: 24-hour coverage track + shifts (GET /v1/guardian/circle)
//   - Contacts: the guardian circle + emergency contacts

struct GuardianRecordsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let ink = Color.appInk
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let creamBg = Color.paper(254, 252, 247)
    private let offWhiteBg = Color.paper(251, 248, 241, elevated: true)
    private let paneBorder = Color(red: 1/255, green: 69/255, blue: 129/255).opacity(0.13)

    @State private var selectedTab: RecordTab = .timeline
    @State private var routeToCenter = true
    @State private var handoffReminder = true

    // Contacts tab state
    @State private var showInviteSheet = false
    @State private var showAddEmergency = false
    @State private var guardianMembers: [GuardianMember] = []
    /// Who looks after the first person I guard, and when (Schedule tab)
    @State private var scheduleCircle: [Guardian] = []
    /// Events of the people I look after (their SOS, check-ins…), with their name
    @State private var personEntries: [TimelineEntry] = []
    @AppStorage("local_emergency_contacts_v2") private var emergencyData: Data = Data()
    @State private var localEmergencyContacts: [LocalEmergencyContact] = []
    @State private var contactToDelete: LocalEmergencyContact?

    private var scheduleSubtitle: String {
        let name = coordinator.protectedPersons.first?.user.displayName ?? langManager.localized("guardian.records.protected.person")
        let city = coordinator.protectedPersons.first?.user.cityName ?? ""
        let dayText = String(format: langManager.localized("guardian.records.person.day"), name)
        return city.isEmpty ? dayText : "\(dayText) · \(String(format: langManager.localized("guardian.records.city.time"), city))"
    }

    /// My own entries and those of the people I look after, newest first.
    private var records: [TimelineEntry] {
        let mine = coordinator.timeline
        let ids = Set(mine.map(\.id))
        return (mine + personEntries.filter { !ids.contains($0.id) }).sorted { $0.timestamp > $1.timestamp }
    }

    enum RecordTab: String, CaseIterable {
        case timeline = "时间线"
        case schedule = "排班"
        case contacts = "联络人"
    }

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    recordsDuoPane
                } else {
                    recordsCompact
                }
            }
            .navigationTitle(langManager.localized("guardian.records.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(sizeClass == .regular ? .hidden : .visible, for: .navigationBar)
            .onAppear {
                loadEmergencyContacts()
                loadGuardianMembers()
                Task { await loadFromServer() }
            }
            .onChange(of: coordinator.protectedPersons.map(\.id)) { Task { await loadFromServer() } }
            // An SOS started or ended: it belongs in the timeline now
            .onChange(of: coordinator.guardianSOS.keys.sorted()) { Task { await loadPersonEntries() } }
            .sheet(isPresented: $showInviteSheet) {
                InviteGuardianSheet()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showAddEmergency) {
                AddEmergencyContactView(
                    contacts: $localEmergencyContacts,
                    countryCode: coordinator.currentUser?.countryCode ?? "CN"
                )
            }
            .confirmDeletingContact($contactToDelete) { contact in
                localEmergencyContacts.removeAll { $0.id == contact.id }
            }
            .onChange(of: localEmergencyContacts) { saveEmergencyContacts() }
        }
    }

    // MARK: - Compact Layout

    private var recordsCompact: some View {
        VStack(spacing: 0) {
            ReadableSegmentedTabs(selection: $selectedTab,
                                   options: RecordTab.allCases.map { ($0, langManager.localized("guardian.records.tab.\($0)")) })
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView {
                switch selectedTab {
                case .timeline:
                    timelineContent
                case .schedule:
                    scheduleContent
                case .contacts:
                    contactsContentInner
                }
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Duo Pane Layout

    private var recordsDuoPane: some View {
        FoldSplitView(dividerColor: paneBorder) {
            // Left: header + picker + stats
            ScrollView {
                VStack(spacing: 12) {
                    Text(langManager.localized("guardian.records.title"))
                        .font(.scaled(size: 20, weight: .bold))
                        .padding(.top, 8)

                    ReadableSegmentedTabs(selection: $selectedTab,
                                           options: RecordTab.allCases.map { ($0, langManager.localized("guardian.records.tab.\($0)")) })

                    // Stats for current tab
                    switch selectedTab {
                    case .timeline:
                        timelineStatBadges
                    case .schedule:
                        VStack(spacing: 2) {
                            Text(scheduleSubtitle)
                                .font(.scaled(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        coverageTrack
                    case .contacts:
                        contactsStatBadges
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(creamBg)
        } trailing: {
            // Right: content for selected tab
            ScrollView {
                switch selectedTab {
                case .timeline:
                    timelineListAndExport
                case .schedule:
                    VStack(spacing: 12) {
                        todayShiftsPanel
                        gapHandlingPanel
                        upsellCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                case .contacts:
                    VStack(spacing: 16) {
                        guardianMembersPanel
                        emergencyContactsPanel
                        inviteCTA
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
            .background(offWhiteBg)
        }
    }

    // MARK: - Extracted Stats

    private var timelineStatBadges: some View {
        HStack(spacing: 16) {
            statBadge(value: "\(records.count)", label: langManager.localized("guardian.records.events"), color: ink)
            statBadge(
                value: "\(records.filter { $0.type == .checkIn }.count)",
                label: langManager.localized("guardian.records.checkins"), color: safe
            )
            statBadge(
                value: "\(records.filter { $0.type == .sosTriggered }.count)",
                label: "SOS", color: alert
            )
        }
    }

    private var contactsStatBadges: some View {
        HStack(spacing: 16) {
            statBadge(
                value: "\(guardianMembers.filter { $0.status == .active }.count)",
                label: langManager.localized("guardian.records.guardians"), color: safe
            )
            statBadge(
                value: "\(guardianMembers.filter { $0.status == .pending }.count)",
                label: langManager.localized("guardian.records.pending"), color: lamp
            )
            statBadge(
                value: "\(localEmergencyContacts.count)",
                label: langManager.localized("guardian.records.emergency"), color: alert
            )
        }
    }

    // Timeline list + export (right pane content for duo)
    private var timelineListAndExport: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                if records.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.scaled(size: 28))
                                .foregroundStyle(.tertiary)
                            Text(langManager.localized("guardian.records.empty"))
                                .font(.scaled(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(langManager.localized("guardian.records.empty.subtitle"))
                                .font(.scaled(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 32)
                        Spacer()
                    }
                } else {
                    ForEach(records.prefix(30)) { entry in
                        timelineRow(
                            icon: iconForType(entry.type),
                            iconColor: colorForType(entry.type),
                            date: formatDate(entry.timestamp),
                            event: "\(formatTime(entry.timestamp)) \(entry.description)",
                            isHighlight: entry.type == .sosTriggered
                        )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text(langManager.localized("guardian.records.export"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
                exportRow(langManager.localized("guardian.records.export.pdf"), value: langManager.localized("guardian.records.export.upgrade"))
                exportRow(langManager.localized("guardian.records.export.gpx"), value: langManager.localized("guardian.records.export.upgrade"))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 16)

            // Emergency Yellow Pages
            sectionHeader(langManager.localized("coverage_emergency", fallback: "Emergency Yellow Pages"))
                .padding(.horizontal, 16)
            EmergencyYellowPagesView(country: coordinator.emergencyCountryCode)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .padding(.top, 8)
    }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        VStack(spacing: 12) {
            // Summary
            HStack(spacing: 16) {
                statBadge(value: "\(records.count)", label: langManager.localized("guardian.records.events"), color: ink)
                statBadge(
                    value: "\(records.filter { $0.type == .checkIn }.count)",
                    label: langManager.localized("guardian.records.checkins"), color: safe
                )
                statBadge(
                    value: "\(records.filter { $0.type == .sosTriggered }.count)",
                    label: "SOS", color: alert
                )
            }
            .padding(.horizontal, 16)

            if !coordinator.protectedPersons.isEmpty {
                IncidentReportButton()
                    .environmentObject(coordinator)
                    .padding(.horizontal, 16)
            }

            // Timeline list
            VStack(alignment: .leading, spacing: 0) {
                if records.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.scaled(size: 28))
                                .foregroundStyle(.tertiary)
                            Text(langManager.localized("guardian.records.empty"))
                                .font(.scaled(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(langManager.localized("guardian.records.empty.subtitle"))
                                .font(.scaled(size: 13))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 32)
                        Spacer()
                    }
                } else {
                    ForEach(records.prefix(30)) { entry in
                        timelineRow(
                            icon: iconForType(entry.type),
                            iconColor: colorForType(entry.type),
                            date: formatDate(entry.timestamp),
                            event: "\(formatTime(entry.timestamp)) \(entry.description)",
                            isHighlight: entry.type == .sosTriggered
                        )
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 16)

            // Emergency Yellow Pages
            sectionHeader(langManager.localized("coverage_emergency", fallback: "Emergency Yellow Pages"))
                .padding(.horizontal, 16)
            EmergencyYellowPagesView(country: coordinator.emergencyCountryCode)
                .padding(.horizontal, 16)

            // Export
            VStack(alignment: .leading, spacing: 8) {
                Text(langManager.localized("guardian.records.export"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
                exportRow(langManager.localized("guardian.records.export.pdf"), value: langManager.localized("guardian.records.export.upgrade"))
                exportRow(langManager.localized("guardian.records.export.gpx"), value: langManager.localized("guardian.records.export.upgrade"))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .padding(.top, 4)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundColor(ink.opacity(0.55))
            Rectangle().fill(ink.opacity(0.06)).frame(height: 1)
        }
        .padding(.top, 12)
    }

    private func statBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.scaled(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func timelineRow(icon: String, iconColor: Color, date: String, event: String, isHighlight: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.scaled(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(event)
                    .font(.scaled(size: 12.5))
                    .lineLimit(2)
                Text(date)
                    .font(.scaled(size: 12))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isHighlight ? lamp.opacity(0.06) : Color.clear)
        .overlay(
            Rectangle()
                .fill(Color(.separator).opacity(0.15))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func iconForType(_ type: TimelineEntryType) -> String {
        switch type {
        case .checkIn: return "checkmark.circle.fill"
        case .sosTriggered: return "exclamationmark.triangle.fill"
        case .sosResolved: return "checkmark.shield.fill"
        case .enteredSafeZone: return "house.fill"
        case .leftSafeZone: return "location.fill"
        case .missedCheckIn: return "clock.badge.exclamationmark"
        case .guardianAlert: return "bell.fill"
        case .batteryLow: return "battery.25"
        case .phoneInactive: return "iphone.slash"
        case .fallDetected: return "figure.fall"
        case .locationUpdate: return "mappin"
        case .homeTimerSet: return "house.fill"
        case .homeTimerDismissed: return "checkmark.circle.fill"
        case .homeTimerExpired: return "clock.badge.exclamationmark"
        case .arrivalReport: return "mappin.circle.fill"
        case .itineraryAdded: return "airplane"
        case .trackingPaused: return "location.slash"
        case .trackingResumed: return "location.fill"
        case .bleSeparation: return "sensor.tag.radiowaves.forward"
        case .silentAlarmConfirmed: return "checkmark.circle.fill"
        case .silentAlarmMissed, .silentAlarmEscalated: return "bell.badge.fill"
        case .voiceNote: return "waveform"
        case .crashReported: return "car.side.rear.and.collision.and.car.side.front"
        case .other: return "circle.fill"
        }
    }

    private func colorForType(_ type: TimelineEntryType) -> Color {
        switch type {
        case .checkIn, .sosResolved, .enteredSafeZone: return safe
        case .sosTriggered, .fallDetected, .silentAlarmEscalated, .crashReported: return alert
        case .missedCheckIn, .batteryLow, .leftSafeZone, .bleSeparation, .silentAlarmMissed: return lamp
        default: return .secondary
        }
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return langManager.localized("guardian.records.today") }
        if cal.isDateInYesterday(date) { return langManager.localized("guardian.records.yesterday") }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        return String(format: langManager.localized("guardian.records.days.ago"), days)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func exportRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.scaled(size: 13))
            Spacer()
            Text(value)
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Schedule Content

    private var scheduleContent: some View {
        Group {
            if coordinator.storeKitManager.canAccessFeature("duty_schedule") {
                VStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text(scheduleSubtitle)
                            .font(.scaled(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    coverageTrack
                    todayShiftsPanel
                    gapHandlingPanel
                    upsellCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            } else {
                SubscriptionGateView(
                    feature: "duty_schedule",
                    featureName: langManager.localized("guardian.records.duty.schedule"),
                    onDismiss: { selectedTab = .timeline }
                )
            }
        }
    }

    // MARK: - 24h Coverage Track

    /// Today's coverage of the first person I look after, from everyone's duty hours
    /// (a guardian without set hours counts for their usual waking hours).
    private var coverage: DutyScheduler.DayCoverage? {
        guard let person = coordinator.protectedPersons.first, !scheduleCircle.isEmpty else { return nil }
        return coordinator.dutyScheduler.buildDayCoverage(protectedPerson: person, guardians: scheduleCircle)
    }

    private var coverageTrack: some View {
        VStack(spacing: 5) {
            Group {
                if let coverage {
                    HStack(spacing: 1) {
                        ForEach(coverage.slots, id: \.hour) { slot in
                            Rectangle().fill(slotColor(slot))
                        }
                    }
                    .background(ink.opacity(0.08))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(format: langManager.localized("guardian.records.coverage"), coverage.totalCoveredHours))
                } else {
                    ZStack {
                        Rectangle().fill(pro.opacity(0.15))
                        Text(langManager.localized("guardian.records.no.schedule"))
                            .font(.scaled(size: 12, weight: .medium))
                            .foregroundStyle(pro)
                    }
                }
            }
            .frame(height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ink.opacity(0.13), lineWidth: 1)
            )

            HStack {
                ForEach(["00", "04", "08", "12", "16", "20", "24"], id: \.self) { hour in
                    Text(hour)
                        .font(.scaled(size: 11))
                        .foregroundStyle(ink.opacity(0.55))
                    if hour != "24" { Spacer() }
                }
            }
            .accessibilityHidden(true)

            if let coverage {
                Text(String(format: langManager.localized("guardian.records.coverage"), coverage.totalCoveredHours))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }
        }
    }

    private func slotColor(_ slot: DutyScheduler.CoverageSlot) -> Color {
        if slot.isGap { return lamp.opacity(0.35) }
        return slot.coveredBy.contains { $0.isConfirmed } ? safe : safe.opacity(0.45)
    }

    private var todayShiftsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("guardian.records.today.shifts"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            if let coverage {
                ForEach(scheduleCircle, id: \.id) { guardian in
                    let hours = coverage.slots.filter { $0.coveredBy.contains { $0.guardianId == guardian.id } }.map(\.hour)
                    shiftRow(guardian.user.displayName + (guardian.id == coordinator.currentUser?.id ? " (\(langManager.localized("guardian.records.me")))" : ""),
                             value: hours.isEmpty ? langManager.localized("guardian.records.shift.none") : Self.hourRanges(hours),
                             note: guardian.dutySchedule == nil ? langManager.localized("guardian.records.shift.awake") : nil,
                             isOk: !hours.isEmpty)
                }
                ForEach(coverage.gaps, id: \.startHour) { gap in
                    shiftRow(langManager.localized("guardian.records.shift.gap"),
                             value: Self.hourRanges(Array(gap.startHour..<gap.endHour)), note: nil, isOk: false)
                }
            } else {
                HStack {
                    Spacer()
                    Text(langManager.localized("guardian.records.no.shifts"))
                        .font(.scaled(size: 13))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ink.opacity(0.13), lineWidth: 1)
        )
    }

    /// [8, 9, 10, 20, 21] → "08:00–11:00, 20:00–22:00"
    static func hourRanges(_ hours: [Int]) -> String {
        var ranges: [(Int, Int)] = []
        for h in hours.sorted() {
            if let last = ranges.last, last.1 == h { ranges[ranges.count - 1].1 = h + 1 } else { ranges.append((h, h + 1)) }
        }
        return ranges.map { String(format: "%02d:00–%02d:00", $0.0, $0.1) }.joined(separator: ", ")
    }

    private func shiftRow(_ label: String, value: String, note: String?, isOk: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.scaled(size: 13))
                if let note {
                    Text(note).font(.scaled(size: 11)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text(value)
                .font(.scaled(size: 12))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(isOk ? safe : lamp)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var gapHandlingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("guardian.records.gap.handling"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            toggleRow(langManager.localized("guardian.records.route.to.center"), isOn: $routeToCenter)
            toggleRow(langManager.localized("guardian.records.handoff.reminder"), isOn: $handoffReminder)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ink.opacity(0.13), lineWidth: 1)
        )
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.scaled(size: 13))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(safe)
        }
        .padding(.vertical, 2)
    }

    private var upsellCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("guardian.records.upsell.text"))
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
            NavigationLink {
                GuardianPlanBillingView()
                    .environmentObject(coordinator)
            } label: {
                Text(langManager.localized("guardian.records.view.center.log"))
                    .font(.scaled(size: 13, weight: .medium))
                    .foregroundStyle(pro)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(pro.opacity(0.06))
        )
    }

    // MARK: - Contacts Content

    private var contactsContentInner: some View {
        VStack(spacing: 16) {
            // Summary stats
            HStack(spacing: 16) {
                statBadge(
                    value: "\(guardianMembers.filter { $0.status == .active }.count)",
                    label: langManager.localized("guardian.records.guardians"), color: safe
                )
                statBadge(
                    value: "\(guardianMembers.filter { $0.status == .pending }.count)",
                    label: langManager.localized("guardian.records.pending"), color: lamp
                )
                statBadge(
                    value: "\(localEmergencyContacts.count)",
                    label: langManager.localized("guardian.records.emergency"), color: alert
                )
            }
            .padding(.horizontal, 16)

            // Guardian members
            guardianMembersPanel

            // Emergency contacts
            emergencyContactsPanel

            // Invite CTA
            inviteCTA
        }
        .padding(.top, 4)
        .padding(.bottom, 24)
    }

    // MARK: - Guardian Members Panel

    private var guardianMembersPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(langManager.localized("guardian.records.circle.members"))
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(ink)
                Spacer()
                Button {
                    showInviteSheet = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "person.badge.plus")
                            .font(.scaled(size: 12))
                        Text(langManager.localized("guardian.records.invite"))
                            .font(.scaled(size: 12, weight: .medium))
                    }
                    .foregroundStyle(safe)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Member list
            ForEach(guardianMembers) { member in
                guardianMemberRow(member)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func guardianMemberRow(_ member: GuardianMember) -> some View {
        HStack(spacing: 10) {
            // Avatar
            ZStack {
                Circle()
                    .fill(statusColor(member.status).opacity(0.12))
                    .frame(width: 36, height: 36)
                Text(AvatarInitial.make(for: member.name))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .font(.scaled(size: 14, weight: .medium))
                    .foregroundStyle(statusColor(member.status))
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(member.name)
                        .font(.scaled(size: 13, weight: .medium))
                        .foregroundStyle(ink)
                    if member.isMe {
                        Text(langManager.localized("guardian.records.me"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Text(member.role.label)
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                    if !member.city.isEmpty {
                        Text("·")
                            .font(.scaled(size: 12))
                            .foregroundStyle(.quaternary)
                        Text(member.city)
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Status badge
            statusBadge(member.status)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(Color(.separator).opacity(0.15))
                .frame(height: 1),
            alignment: .bottom
        )
        // Guardians can't change or remove each other (only the person can), so
        // co-guardian rows have no actions: they failed silently before.
        .accessibilityElement(children: .combine)
    }

    private func statusColor(_ status: GuardianMember.Status) -> Color {
        switch status {
        case .active: return safe
        case .pending: return lamp
        case .declined: return alert
        }
    }

    private func statusBadge(_ status: GuardianMember.Status) -> some View {
        Text(status.label)
            .font(.scaled(size: 12, weight: .medium))
            .foregroundStyle(statusColor(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor(status).opacity(0.1))
            .clipShape(Capsule())
    }

    // MARK: - Emergency Contacts Panel

    private var emergencyContactsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(langManager.localized("guardian.records.emergency.contacts"))
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(ink)
                Spacer()
                Button {
                    showAddEmergency = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus.circle")
                            .font(.scaled(size: 12))
                        Text(langManager.localized("guardian.records.add"))
                            .font(.scaled(size: 12, weight: .medium))
                    }
                    .foregroundStyle(safe)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if localEmergencyContacts.isEmpty {
                // Empty state
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.scaled(size: 24))
                            .foregroundStyle(.tertiary)
                        Text(langManager.localized("guardian.records.no.emergency"))
                            .font(.scaled(size: 13))
                            .foregroundStyle(.tertiary)
                        Text(langManager.localized("guardian.records.emergency.hint"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
            } else {
                ForEach(Array(localEmergencyContacts.enumerated()), id: \.element.id) { index, contact in
                    emergencyContactRow(contact: contact, index: index)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func emergencyContactRow(contact: LocalEmergencyContact, index: Int) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(alert.opacity(0.1))
                    .frame(width: 32, height: 32)
                Text(AvatarInitial.make(for: contact.name))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .font(.scaled(size: 12, weight: .medium))
                    .foregroundStyle(alert)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.scaled(size: 13, weight: .medium))
                HStack(spacing: 4) {
                    Text(contact.relationship)
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                    if !contact.phone.isEmpty {
                        Text("·")
                            .font(.scaled(size: 12))
                            .foregroundStyle(.quaternary)
                        Text(contact.phone)
                            .font(.scaled(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if !contact.phone.isEmpty {
                Button {
                    let cleaned = contact.phone.replacingOccurrences(of: " ", with: "")
                    if let url = URL(string: "tel://\(cleaned)") {
                        ExternalURL.open(url)
                    }
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.scaled(size: 13))
                        .foregroundStyle(safe)
                        .frame(width: 32, height: 32)
                        .background(safe.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(
            Rectangle()
                .fill(Color(.separator).opacity(0.15))
                .frame(height: 1),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        // Not in a List, so swipe actions never fired: long-press, then confirm
        .contextMenu {
            Button(role: .destructive) {
                contactToDelete = contact
            } label: {
                Label(langManager.localized("guardian.records.delete"), systemImage: "trash")
            }
        }
    }

    // MARK: - Invite CTA

    private var inviteCTA: some View {
        Button {
            showInviteSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .font(.scaled(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(langManager.localized("guardian.records.invite.new"))
                        .font(.scaled(size: 14, weight: .medium))
                    Text(langManager.localized("guardian.records.invite.subtitle"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(ink)
            .padding(14)
            .background(safe.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(safe.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func loadGuardianMembers() {
        // Me first, until the circle arrives from the server
        guard guardianMembers.isEmpty, let user = coordinator.currentUser else { return }
        guardianMembers = [member(id: user.id, name: user.displayName, city: user.cityName, since: user.createdAt)]
    }

    private func member(id: String, name: String, city: String, since: Date) -> GuardianMember {
        let isMe = id == coordinator.currentUser?.id
        return GuardianMember(
            id: id,
            name: isMe && name.isEmpty ? langManager.localized("guardian.records.me.name") : name,
            city: city, phone: "", role: .primary, status: .active, isMe: isMe, joinedAt: since)
    }

    private func loadFromServer() async {
        await loadCircle()
        await loadPersonEntries()
    }

    /// Everyone who looks after the people I look after (each once, me first).
    private func loadCircle() async {
        var circles: [[Guardian]] = []
        for person in coordinator.protectedPersons {
            circles.append(await coordinator.fetchGuardianCircle(personId: person.id))
        }
        scheduleCircle = circles.first ?? []
        var seen = Set<String>()
        var members: [GuardianMember] = []
        if let user = coordinator.currentUser {
            members.append(member(id: user.id, name: user.displayName, city: user.cityName, since: user.createdAt))
            seen.insert(user.id)
        }
        for guardian in circles.flatMap({ $0 }) where seen.insert(guardian.id).inserted {
            members.append(member(id: guardian.id, name: guardian.user.displayName,
                                  city: guardian.user.cityName, since: guardian.linkedSince))
        }
        if !members.isEmpty { guardianMembers = members }
    }

    /// Each person's own events (an SOS, a check-in…), named so it's clear whose they are.
    private func loadPersonEntries() async {
        var entries: [TimelineEntry] = []
        for person in coordinator.protectedPersons {
            let name = person.user.displayName
            entries += await coordinator.fetchTimeline(of: person.id, limit: 30).map {
                TimelineEntry(id: $0.id, timestamp: $0.timestamp, type: $0.type,
                              description: name.isEmpty ? $0.description : "\(name) · \($0.description)", detail: $0.detail)
            }
        }
        personEntries = entries
    }

    private func loadEmergencyContacts() {
        if let decoded = try? JSONDecoder().decode([LocalEmergencyContact].self, from: emergencyData) {
            localEmergencyContacts = decoded
        }
    }

    private func saveEmergencyContacts() {
        if let encoded = try? JSONEncoder().encode(localEmergencyContacts) {
            emergencyData = encoded
        }
    }
}

// MARK: - Guardian Member Model

struct GuardianMember: Identifiable {
    let id: String
    var name: String
    var city: String
    var phone: String
    var role: Role
    var status: Status
    var isMe: Bool
    var joinedAt: Date

    enum Role: String, CaseIterable {
        case primary = "主要守护者"
        case backup = "备用守护者"
        case observer = "观察者"

        /// rawValue is what the backend stores; label is for display.
        var label: String { LanguageManager.shared.localized("member.role.\(self)") }
    }

    enum Status: String {
        case active = "已加入"
        case pending = "待接受"
        case declined = "已拒绝"

        var label: String { LanguageManager.shared.localized("member.status.\(self)") }
    }
}

// MARK: - Invite Guardian Sheet
//
// A guardian invites someone to be looked after (inviterRole "guardian"): the
// person who accepts becomes protected and sees what they are agreeing to first.
// Inviting another guardian to share the care of someone (primary / backup /
// observer) is a later phase, so the role picker is not shown.

struct InviteGuardianSheet: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color.appInk

    @State private var invitePhone = ""
    @State private var inviteMethod: InviteMethod = .sms
    @State private var showCopied = false
    @State private var inviteError: String?

    enum InviteMethod: String, CaseIterable {
        case sms = "短信"
        case wechat = "微信"
        case link = "复制链接"

        var label: String { LanguageManager.shared.localized("invite.method.\(self)") }

        var icon: String {
            switch self {
            case .sms: return "message.fill"
            case .wechat: return "bubble.left.and.text.bubble.right.fill"
            case .link: return "link"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(LanguageManager.shared.localized("invite.sheet.invitee")) {
                    TextField(LanguageManager.shared.localized("invite.sheet.phone"), text: $invitePhone)
                        .keyboardType(.phonePad)
                }

                Section(LanguageManager.shared.localized("invite.sheet.method")) {
                    ForEach(InviteMethod.allCases, id: \.self) { method in
                        Button {
                            inviteMethod = method
                            sendInvite(via: method)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: method.icon)
                                    .font(.scaled(size: 15))
                                    .foregroundStyle(safe)
                                    .frame(width: 24)
                                Text(method.label)
                                    .font(.scaled(size: 14))
                                    .foregroundStyle(ink)
                                Spacer()
                                if method == .link && showCopied {
                                    Text(LanguageManager.shared.localized("invite.sheet.copied"))
                                        .font(.scaled(size: 12))
                                        .foregroundStyle(safe)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.scaled(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Text(LanguageManager.shared.localized("invite.sheet.protectFooter"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle(LanguageManager.shared.localized("invite.sheet.protectTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .alert(LanguageManager.shared.localized("invite.sheet.errorTitle"), isPresented: Binding(
                get: { inviteError != nil },
                set: { if !$0 { inviteError = nil } }
            )) {
                Button(LanguageManager.shared.localized("invite.sheet.ok"), role: .cancel) {}
            } message: {
                Text(inviteError ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label(LanguageManager.shared.localized("invite.sheet.cancel"), systemImage: "xmark") }
                }
            }
        }
    }

    private func sendInvite(via method: InviteMethod) {
        Task {
            // Create invite on server. A code that only exists locally can never
            // be accepted, so on failure tell the user instead of sharing it.
            let inviteCode: String
            do {
                let response: CreateInviteResponse = try await coordinator.createInviteCode(inviterRole: .guardian)
                inviteCode = response.code
            } catch {
                inviteError = LanguageManager.shared.localized("invite.sheet.errorBody")
                return
            }

            // The invitee will be someone I protect, not a member of the guardian
            // team, so they are not added to `members`.
            let inviteLink = "https://shoudeng.app/invite?code=\(inviteCode)"

            switch method {
            case .link:
                UIPasteboard.general.string = inviteLink
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showCopied = false
                }
            case .sms:
                let message = String(format: LanguageManager.shared.localized("invite.sheet.protectShareText"), inviteLink)
                let encoded = message.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? inviteLink
                // The phone number (optional) becomes the message recipient
                let recipient = invitePhone.filter { $0.isNumber || $0 == "+" }
                if let url = URL(string: "sms:\(recipient)&body=\(encoded)") {
                    ExternalURL.open(url)
                }
                dismiss()
            case .wechat:
                // Use system share sheet as fallback
                let activityVC = UIActivityViewController(
                    activityItems: [String(format: LanguageManager.shared.localized("invite.sheet.protectShareText"), inviteLink)],
                    applicationActivities: nil
                )
                AppCoordinator.topViewController()?.present(activityVC, animated: true)
                dismiss()
            }
        }
    }
}
