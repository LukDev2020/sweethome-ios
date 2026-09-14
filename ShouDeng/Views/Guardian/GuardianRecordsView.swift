import SwiftUI

// MARK: - Guardian Records, Schedule & Contacts
//
// Combined view with segmented control:
//   - Timeline: activity log from all protected persons
//   - Duty Schedule: 24-hour coverage track + shifts
//   - Contacts: manage guardian circle members + emergency contacts

struct GuardianRecordsView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var selectedTab: RecordTab = .timeline
    @State private var routeToCenter = true
    @State private var handoffReminder = true

    // Contacts tab state
    @State private var showInviteSheet = false
    @State private var showAddEmergency = false
    @State private var editingMember: GuardianMember? = nil
    @State private var guardianMembers: [GuardianMember] = []
    @AppStorage("local_emergency_contacts_v2") private var emergencyData: Data = Data()
    @State private var localEmergencyContacts: [LocalEmergencyContact] = []

    private var scheduleSubtitle: String {
        let name = coordinator.protectedPersons.first?.user.displayName ?? "被守护者"
        let city = coordinator.protectedPersons.first?.user.cityName ?? ""
        return "\(name)的一天\(city.isEmpty ? "" : " · \(city)时间")"
    }

    enum RecordTab: String, CaseIterable {
        case timeline = "时间线"
        case schedule = "排班"
        case contacts = "联络人"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented picker
                Picker("", selection: $selectedTab) {
                    ForEach(RecordTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                // Content
                ScrollView {
                    switch selectedTab {
                    case .timeline:
                        timelineContent
                    case .schedule:
                        scheduleContent
                    case .contacts:
                        contactsContent
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("记录")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadEmergencyContacts()
                loadGuardianMembers()
            }
        }
    }

    // MARK: - Timeline Content

    private var timelineContent: some View {
        VStack(spacing: 12) {
            // Summary
            HStack(spacing: 16) {
                statBadge(value: "\(coordinator.timeline.count)", label: "事件", color: ink)
                statBadge(
                    value: "\(coordinator.timeline.filter { $0.type == .checkIn }.count)",
                    label: "报平安", color: safe
                )
                statBadge(
                    value: "\(coordinator.timeline.filter { $0.type == .sosTriggered }.count)",
                    label: "SOS", color: alert
                )
            }
            .padding(.horizontal, 16)

            // Timeline list
            VStack(alignment: .leading, spacing: 0) {
                if coordinator.timeline.isEmpty {
                    timelineRow(icon: "exclamationmark.triangle.fill", iconColor: lamp, date: "今天", event: "14:07 小雨触发 SOS，4 分 12 秒后确认安全", isHighlight: true)
                    timelineRow(icon: "checkmark.circle.fill", iconColor: safe, date: "今天", event: "09:12 小雨报平安", isHighlight: false)
                    timelineRow(icon: "location.fill", iconColor: .secondary, date: "昨天", event: "21:40 小雨离开安全区「住所」", isHighlight: false)
                    timelineRow(icon: "checkmark.circle.fill", iconColor: safe, date: "昨天", event: "08:55 弟弟报平安", isHighlight: false)
                    timelineRow(icon: "battery.25", iconColor: lamp, date: "3天前", event: "16:30 奶奶手机电量低于 20%", isHighlight: false)
                    timelineRow(icon: "checkmark.circle.fill", iconColor: safe, date: "5天前", event: "07:30 奶奶报平安", isHighlight: false)
                } else {
                    ForEach(coordinator.timeline.prefix(30)) { entry in
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

            // Export
            VStack(alignment: .leading, spacing: 8) {
                Text("导出")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                exportRow("带时间戳的 PDF", value: "需升级")
                exportRow("位置轨迹 GPX", value: "需升级")
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

    private func statBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
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
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(event)
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                Text(date)
                    .font(.system(size: 10))
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
        }
    }

    private func colorForType(_ type: TimelineEntryType) -> Color {
        switch type {
        case .checkIn, .sosResolved, .enteredSafeZone: return safe
        case .sosTriggered, .fallDetected: return alert
        case .missedCheckIn, .batteryLow, .leftSafeZone: return lamp
        default: return .secondary
        }
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        return "\(days)天前"
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func exportRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Schedule Content

    private var scheduleContent: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(scheduleSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            coverageTrack
            todayShiftsPanel
            gapHandlingPanel
            upsellCard
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    // MARK: - 24h Coverage Track

    private var coverageTrack: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let total: CGFloat = 24
                let w = geo.size.width
                HStack(spacing: 0) {
                    segmentBlock(label: "妈妈", width: w * 7 / total, bgColor: safe, textColor: .white)
                    segmentBlock(label: "爸爸", width: w * 6 / total, bgColor: Color(red: 44/255, green: 70/255, blue: 112/255), textColor: .white)
                    segmentBlock(label: "无人", width: w * 4 / total, bgColor: pro.opacity(0.3), textColor: pro)
                    segmentBlock(label: "姑姑", width: w * 7 / total, bgColor: lamp, textColor: ink)
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
                        .font(.system(size: 9.5))
                        .foregroundStyle(ink.opacity(0.45))
                    if hour != "24" { Spacer() }
                }
            }
        }
    }

    private func segmentBlock(label: String, width: CGFloat, bgColor: Color, textColor: Color) -> some View {
        ZStack {
            Rectangle().fill(bgColor)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
        .frame(width: width)
    }

    private var todayShiftsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日班次")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            shiftRow("你 · 多伦多", value: "08:00 – 20:00 值班中", isOk: true)
            shiftRow("爸爸 · 多伦多", value: "20:00 – 02:00 已确认", isOk: false)
            shiftRow("姑姑 · 悉尼", value: "02:00 – 08:00 已确认", isOk: false)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ink.opacity(0.13), lineWidth: 1)
        )
    }

    private func shiftRow(_ label: String, value: String, isOk: Bool) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(isOk ? safe : .primary)
        }
        .padding(.vertical, 2)
    }

    private var gapHandlingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("缺口处理")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            toggleRow("无人时段转响应中心", isOn: $routeToCenter)
            toggleRow("交接前提醒", isOn: $handoffReminder)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ink.opacity(0.13), lineWidth: 1)
        )
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(safe)
        }
        .padding(.vertical, 2)
    }

    private var upsellCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("凌晨两点到六点三地家人都在睡。这四小时目前由专员补上——订阅的价值就是这块空缺。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {} label: {
                Text("查看响应中心记录")
                    .font(.system(size: 13, weight: .medium))
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

    private var contactsContent: some View {
        VStack(spacing: 16) {
            // Summary stats
            HStack(spacing: 16) {
                statBadge(
                    value: "\(guardianMembers.filter { $0.status == .active }.count)",
                    label: "守护者", color: safe
                )
                statBadge(
                    value: "\(guardianMembers.filter { $0.status == .pending }.count)",
                    label: "待接受", color: lamp
                )
                statBadge(
                    value: "\(localEmergencyContacts.count)",
                    label: "紧急联络", color: alert
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
        .sheet(isPresented: $showInviteSheet) {
            InviteGuardianSheet(members: $guardianMembers)
                .environmentObject(coordinator)
        }
        .sheet(isPresented: $showAddEmergency) {
            AddEmergencyContactView(
                contacts: $localEmergencyContacts,
                countryCode: coordinator.currentUser?.countryCode ?? "CN"
            )
        }
        .sheet(item: $editingMember) { member in
            EditGuardianMemberSheet(member: member, members: $guardianMembers)
                .environmentObject(coordinator)
        }
        .onChange(of: localEmergencyContacts) { saveEmergencyContacts() }
    }

    // MARK: - Guardian Members Panel

    private var guardianMembersPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("守护圈成员")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink)
                Spacer()
                Button {
                    showInviteSheet = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 12))
                        Text("邀请")
                            .font(.system(size: 12, weight: .medium))
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
                Text(String(member.name.prefix(1)))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(statusColor(member.status))
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(member.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ink)
                    if member.isMe {
                        Text("(我)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Text(member.role.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if !member.city.isEmpty {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(.quaternary)
                        Text(member.city)
                            .font(.system(size: 11))
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
        .contentShape(Rectangle())
        .contextMenu {
            if !member.isMe {
                Button {
                    editingMember = member
                } label: {
                    Label("编辑角色", systemImage: "pencil")
                }
                if member.status == .pending {
                    Button {
                        resendInvite(member)
                    } label: {
                        Label("重发邀请", systemImage: "arrow.clockwise")
                    }
                }
                Button(role: .destructive) {
                    removeMember(member)
                } label: {
                    Label("移除", systemImage: "person.badge.minus")
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !member.isMe {
                Button(role: .destructive) {
                    removeMember(member)
                } label: {
                    Label("移除", systemImage: "trash")
                }
                Button {
                    editingMember = member
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .tint(safe)
            }
        }
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
            .font(.system(size: 10, weight: .medium))
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
                Text("紧急联络人")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink)
                Spacer()
                Button {
                    showAddEmergency = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 12))
                        Text("添加")
                            .font(.system(size: 12, weight: .medium))
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
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("暂无紧急联络人")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Text("录入邻居、社区、当地医院、大使馆等")
                            .font(.system(size: 11))
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
                Text(String(contact.name.prefix(1)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(alert)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 4) {
                    Text(contact.relationship)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if !contact.phone.isEmpty {
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                        Text(contact.phone)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if !contact.phone.isEmpty {
                Button {
                    let cleaned = contact.phone.replacingOccurrences(of: " ", with: "")
                    if let url = URL(string: "tel://\(cleaned)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 13))
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                localEmergencyContacts.remove(at: index)
            } label: {
                Label("删除", systemImage: "trash")
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
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text("邀请新守护者加入")
                        .font(.system(size: 14, weight: .medium))
                    Text("通过短信、微信或链接邀请家人加入守护圈")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
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

    private func removeMember(_ member: GuardianMember) {
        guardianMembers.removeAll { $0.id == member.id }
        Task {
            do {
                let _: EmptyResponse = try await coordinator.apiClient.delete(
                    "/v1/protected/guardians/\(member.id)"
                )
            } catch {
                #if DEBUG
                print("[GuardianRecords] Remove member failed: \(error)")
                #endif
            }
        }
    }

    private func resendInvite(_ member: GuardianMember) {
        Task {
            do {
                let _: EmptyResponse = try await coordinator.apiClient.post(
                    "/v1/invite/create",
                    body: ["role": "guardian"]
                )
            } catch {
                #if DEBUG
                print("[GuardianRecords] Resend invite failed: \(error)")
                #endif
            }
        }
    }

    private func loadGuardianMembers() {
        // If we already have members loaded (e.g. from invite), keep them
        guard guardianMembers.isEmpty else { return }

        // Build from real data: current user + any known guardians
        var members: [GuardianMember] = []

        // Add self (the current guardian user)
        if let user = coordinator.currentUser {
            members.append(GuardianMember(
                id: user.id,
                name: user.displayName.isEmpty ? "我" : user.displayName,
                city: user.cityName,
                phone: "",
                role: .primary,
                status: .active,
                isMe: true,
                joinedAt: user.createdAt
            ))
        }

        // If no real data yet, show demo to indicate what populated state looks like
        if members.count <= 1 && coordinator.protectedPersons.isEmpty {
            members.append(contentsOf: GuardianMember.demoData.filter { !$0.isMe })
        }

        guardianMembers = members
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

        var label: String { rawValue }
    }

    enum Status: String {
        case active = "已加入"
        case pending = "待接受"
        case declined = "已拒绝"

        var label: String { rawValue }
    }

    static let demoData: [GuardianMember] = [
        GuardianMember(id: "me", name: "妈妈", city: "多伦多", phone: "+1 416-xxx-xxxx", role: .primary, status: .active, isMe: true, joinedAt: Date().addingTimeInterval(-90 * 86400)),
        GuardianMember(id: "dad", name: "爸爸", city: "多伦多", phone: "+1 416-xxx-xxxx", role: .primary, status: .active, isMe: false, joinedAt: Date().addingTimeInterval(-90 * 86400)),
        GuardianMember(id: "aunt", name: "姑姑", city: "悉尼", phone: "+61 4xx-xxx-xxx", role: .backup, status: .active, isMe: false, joinedAt: Date().addingTimeInterval(-60 * 86400)),
        GuardianMember(id: "uncle", name: "叔叔", city: "北京", phone: "+86 138-xxxx-xxxx", role: .observer, status: .pending, isMe: false, joinedAt: Date()),
    ]
}

// MARK: - Invite Guardian Sheet

struct InviteGuardianSheet: View {
    @Binding var members: [GuardianMember]
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)

    @State private var inviteName = ""
    @State private var invitePhone = ""
    @State private var inviteRole: GuardianMember.Role = .backup
    @State private var inviteMethod: InviteMethod = .sms
    @State private var showCopied = false

    enum InviteMethod: String, CaseIterable {
        case sms = "短信"
        case wechat = "微信"
        case link = "复制链接"

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
                Section("被邀请人") {
                    TextField("姓名", text: $inviteName)
                    TextField("手机号 (含区号)", text: $invitePhone)
                        .keyboardType(.phonePad)
                }

                Section("角色") {
                    Picker("分配角色", selection: $inviteRole) {
                        ForEach(GuardianMember.Role.allCases, id: \.self) { role in
                            Text(role.label).tag(role)
                        }
                    }
                    .pickerStyle(.menu)

                    // Role descriptions
                    VStack(alignment: .leading, spacing: 6) {
                        roleDescription("主要守护者", desc: "可查看位置、接收 SOS、参与值班")
                        roleDescription("备用守护者", desc: "在主要守护者无法响应时接替")
                        roleDescription("观察者", desc: "仅接收通知，不参与值班排班")
                    }
                    .padding(.vertical, 4)
                }

                Section("发送方式") {
                    ForEach(InviteMethod.allCases, id: \.self) { method in
                        Button {
                            inviteMethod = method
                            sendInvite(via: method)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: method.icon)
                                    .font(.system(size: 15))
                                    .foregroundStyle(safe)
                                    .frame(width: 24)
                                Text(method.rawValue)
                                    .font(.system(size: 14))
                                    .foregroundStyle(ink)
                                Spacer()
                                if method == .link && showCopied {
                                    Text("已复制")
                                        .font(.system(size: 12))
                                        .foregroundStyle(safe)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .disabled(inviteName.isEmpty)
                    }
                }

                Section {
                    Text("邀请链接 24 小时内有效。对方接受后将自动加入守护圈。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("邀请守护者")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func roleDescription(_ title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(safe.opacity(0.3))
                .frame(width: 5, height: 5)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sendInvite(via method: InviteMethod) {
        Task {
            // Create invite on server
            let inviteCode: String
            do {
                let response: CreateInviteResponse = try await coordinator.apiClient.post(
                    "/v1/invite/create",
                    body: ["role": "guardian"]
                )
                inviteCode = response.code
            } catch {
                inviteCode = String(format: "%06d", Int.random(in: 100000...999999))
            }

            let newMember = GuardianMember(
                id: UUID().uuidString,
                name: inviteName,
                city: "",
                phone: invitePhone,
                role: inviteRole,
                status: .pending,
                isMe: false,
                joinedAt: Date()
            )
            members.append(newMember)

            let inviteLink = "https://shoudeng.app/invite?code=\(inviteCode)"

            switch method {
            case .link:
                UIPasteboard.general.string = inviteLink
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showCopied = false
                }
            case .sms:
                let encoded = inviteLink.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? inviteLink
                if let url = URL(string: "sms:&body=\(encoded)") {
                    await UIApplication.shared.open(url)
                }
                dismiss()
            case .wechat:
                // Use system share sheet as fallback
                let activityVC = UIActivityViewController(
                    activityItems: ["加入守灯守护圈：\(inviteLink)"],
                    applicationActivities: nil
                )
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root = scene.windows.first?.rootViewController {
                    root.present(activityVC, animated: true)
                }
                dismiss()
            }
        }
    }
}

// MARK: - Edit Guardian Member Sheet

struct EditGuardianMemberSheet: View {
    let member: GuardianMember
    @Binding var members: [GuardianMember]
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    @State private var selectedRole: GuardianMember.Role = .backup

    var body: some View {
        NavigationStack {
            Form {
                Section("成员信息") {
                    HStack {
                        Text("姓名")
                        Spacer()
                        Text(member.name)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("城市")
                        Spacer()
                        Text(member.city.isEmpty ? "未知" : member.city)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("电话")
                        Spacer()
                        Text(member.phone)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("状态")
                        Spacer()
                        Text(member.status.label)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("角色设置") {
                    Picker("角色", selection: $selectedRole) {
                        ForEach(GuardianMember.Role.allCases, id: \.self) { role in
                            Text(role.label).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if member.status == .active {
                    Section("加入时间") {
                        HStack {
                            Text("加入于")
                            Spacer()
                            Text(member.joinedAt, style: .date)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("编辑成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        if let idx = members.firstIndex(where: { $0.id == member.id }) {
                            members[idx].role = selectedRole
                        }
                        Task {
                            do {
                                let _: EmptyResponse = try await coordinator.apiClient.put(
                                    "/v1/protected/guardians/\(member.id)/permissions",
                                    body: ["role": selectedRole.rawValue]
                                )
                            } catch {
                                #if DEBUG
                                print("[EditMember] Update role failed: \(error)")
                                #endif
                            }
                        }
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(safe)
                }
            }
            .onAppear { selectedRole = member.role }
        }
    }
}
