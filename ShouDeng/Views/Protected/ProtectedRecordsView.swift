import SwiftUI

// MARK: - Screen A4: My Records / Timeline + Emergency Contacts
//
// Two-tab view:
//   Tab 0 "时间线": timeline events, export, upsell
//   Tab 1 "紧急联系人": regional emergency numbers + custom contact cards

struct ProtectedRecordsView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)
    private let border: Color = Color(red: 0.7, green: 0.7, blue: 0.72)
    private let divider: Color = Color(red: 0.85, green: 0.85, blue: 0.86)

    @State private var selectedTab = 0
    @State private var showAddContact = false
    @State private var showUpgradeHint = false
    @AppStorage("custom_emergency_contacts") private var customContactsData: Data = Data()
    @State private var customContacts: [LocalEmergencyContact] = []

    private var userCountry: String {
        coordinator.currentUser?.countryCode ?? "UA"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Segmented picker
            Picker("", selection: $selectedTab) {
                Text("时间线").tag(0)
                Text("紧急联系人").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Content
            if selectedTab == 0 {
                timelineTab
            } else {
                emergencyContactsTab
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("我的记录")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddContact) {
            AddEmergencyContactView(contacts: $customContacts, countryCode: userCountry)
        }
        .onAppear { loadCustomContacts() }
        .onChange(of: customContacts) { saveCustomContacts() }
    }

    // MARK: - Tab 0: Timeline

    private var timelineTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text("我的记录")
                        .font(.system(size: 20, weight: .bold))
                    Text("90 天可查 · 专业版永久保存")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                timelineSection
                exportPanel
                upsellCard
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Tab 1: Emergency Contacts

    private var emergencyContactsTab: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Regional emergency numbers
                regionalNumbersSection

                // Custom contacts
                customContactsSection

                // Add button
                Button {
                    showAddContact = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text("添加紧急联络人")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(safe)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(safe.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Tip
                Text("紧急情况下，优先拨打当地急救电话。自定义联络人可提前录入邻居、社区、当地医院等信息。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    // MARK: - Regional Emergency Numbers

    private var regionalNumbersSection: some View {
        let info = RegionalEmergencyInfo.forCountry(userCountry)
        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "phone.arrow.up.right.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(alert)
                Text("当地紧急服务")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(info.regionName) \(info.areaCode)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(alert.opacity(0.05))

            ForEach(Array(info.numbers.enumerated()), id: \.offset) { _, number in
                HStack(spacing: 10) {
                    Image(systemName: number.icon)
                        .font(.system(size: 13))
                        .foregroundStyle(number.color)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(number.label)
                            .font(.system(size: 12.5, weight: .medium))
                        if let note = number.note {
                            Text(note)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button { callNumber(number.number) } label: {
                        Text(number.number)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(alert)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .overlay(
                    Rectangle()
                        .foregroundStyle(divider)
                        .frame(height: 1),
                    alignment: .bottom
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(alert.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Custom Contacts

    private var customContactsSection: some View {
        CustomContactsPanel(
            contacts: $customContacts,
            onCall: { callNumber($0) }
        )
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if coordinator.timeline.isEmpty {
                timelineRow(date: "今天", event: "14:07 触发 SOS，4 分 12 秒后由妈妈确认安全", isBlurred: false)
                timelineRow(date: "今天", event: "09:12 报平安", isBlurred: false)
                timelineRow(date: "昨天", event: "21:40 离开安全区「住所」", isBlurred: false)
                timelineRow(date: "昨天", event: "08:55 报平安", isBlurred: false)
                timelineRow(date: "3天前", event: "18:20 在未知区域停留超过两小时", isBlurred: true)
                timelineRow(date: "5天前", event: "07:30 报平安", isBlurred: true)
            } else {
                ForEach(coordinator.timeline.prefix(20)) { entry in
                    timelineRow(
                        date: formatDate(entry.timestamp),
                        event: "\(formatTime(entry.timestamp)) \(entry.description)",
                        isBlurred: false
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(border, lineWidth: 1)
        )
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

    private func timelineRow(date: String, event: String, isBlurred: Bool) -> some View {
        HStack(alignment: .top) {
            Text(date)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
            Text(event)
                .font(.system(size: 12.5))
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .opacity(isBlurred ? 0.4 : 1.0)
        .overlay(
            Rectangle()
                .foregroundStyle(divider)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Export Panel

    private var exportPanel: some View {
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
                .stroke(border, lineWidth: 1)
        )
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

    // MARK: - Upsell

    private var upsellCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("免费版仅保留 24 小时。升级后可查看 90 天完整时间线并导出——向警方、保险或律师说明情况时用得上。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button { showUpgradeHint = true } label: {
                Text("升级查看全部记录")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(pro)
            }
            .alert("如何升级？", isPresented: $showUpgradeHint) {
                Button("好的") {}
            } message: {
                Text("请联系您的守护者升级订阅方案，升级后您将自动解锁完整时间线。")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(pro.opacity(0.06))
        )
    }

    // MARK: - Helpers

    private func callNumber(_ number: String) {
        let cleaned = number.replacingOccurrences(of: " ", with: "")
        if let url = URL(string: "tel://\(cleaned)") {
            UIApplication.shared.open(url)
        }
    }

    private func loadCustomContacts() {
        if let decoded = try? JSONDecoder().decode([LocalEmergencyContact].self, from: customContactsData) {
            customContacts = decoded
        }
    }

    private func saveCustomContacts() {
        if let encoded = try? JSONEncoder().encode(customContacts) {
            customContactsData = encoded
        }
    }
}

// MARK: - Emergency Contact Card Row (extracted for type-checker)

private struct EmergencyContactCardRow: View {
    let contact: LocalEmergencyContact
    let onDelete: () -> Void
    let onCall: () -> Void

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    var body: some View {
        VStack(spacing: 0) {
            contactInfo
            deleteRow
        }
        .overlay(alignment: .bottom) {
            Color.gray.opacity(0.15).frame(height: 1)
        }
    }

    private var contactInfo: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            ZStack {
                Circle().fill(safe.opacity(0.12)).frame(width: 38, height: 38)
                Text(String(contact.name.prefix(1)))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(safe)
            }

            // Details
            VStack(alignment: .leading, spacing: 3) {
                nameRow
                phoneRow
                emailRow
                addressRow
            }

            Spacer()

            // Call
            if !contact.phone.isEmpty {
                Button(action: onCall) {
                    Image(systemName: "phone.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(safe)
                }
            }
        }
        .padding(12)
    }

    private var nameRow: some View {
        HStack(spacing: 6) {
            Text(contact.name)
                .font(.system(size: 14, weight: .medium))
            Text(contact.relationship)
                .font(.system(size: 10))
                .foregroundStyle(safe)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(safe.opacity(0.1))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var phoneRow: some View {
        if !contact.phone.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "phone.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(contact.phone).font(.system(size: 12, design: .monospaced)).foregroundStyle(ink.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var emailRow: some View {
        if !contact.email.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "envelope.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(contact.email).font(.system(size: 11)).foregroundStyle(ink.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private var addressRow: some View {
        if !contact.address.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(contact.address).font(.system(size: 11)).foregroundStyle(ink.opacity(0.6)).lineLimit(2)
            }
        }
    }

    private var deleteRow: some View {
        HStack {
            Spacer()
            Button(role: .destructive, action: onDelete) {
                HStack(spacing: 3) {
                    Image(systemName: "trash").font(.system(size: 10))
                    Text("删除").font(.system(size: 11))
                }
                .foregroundStyle(.red.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Custom Contacts Panel (extracted for type-checker)

private struct CustomContactsPanel: View {
    @Binding var contacts: [LocalEmergencyContact]
    let onCall: (String) -> Void

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let borderColor: Color = Color(red: 0.7, green: 0.7, blue: 0.72)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Image(systemName: "person.2.fill")
                .font(.system(size: 12))
                .foregroundStyle(safe)
            Text("自定义紧急联络人")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(contacts.count) 人")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(safe.opacity(0.05))
    }

    @ViewBuilder
    private var content: some View {
        if contacts.isEmpty {
            emptyState
        } else {
            contactsList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("暂无紧急联络人")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("录入邻居、社区工作人员、当地医院等")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var contactsList: some View {
        let items = contacts
        return VStack(spacing: 0) {
            ForEach(items) { contact in
                EmergencyContactCardRow(
                    contact: contact,
                    onDelete: {
                        withAnimation {
                            contacts.removeAll { $0.id == contact.id }
                        }
                    },
                    onCall: { onCall(contact.phone) }
                )
            }
        }
    }
}
