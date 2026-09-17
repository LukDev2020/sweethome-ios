import SwiftUI

// MARK: - Organization Dashboard View
//
// Compliance dashboard for institutional clients.
// Shows: "320 members, 298 activated, 12 permissions abnormal, 10 not installed"
// This is literally what institutions pay for — proof of duty of care.

struct OrgDashboardView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let warning = Color.orange

    @State private var dashboard: OrgDashboard?
    @State private var isLoading = true
    @State private var showCreateOrg = false
    @State private var showAlert = false
    @State private var showReport = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let dashboard {
                    dashboardContent(dashboard)
                } else {
                    noOrgView
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("合规看板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreateOrg) {
                CreateOrgSheet(onCreated: { Task { await loadDashboard() } })
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showAlert) {
                if let dashboard {
                    SendAlertSheet(orgId: dashboard.orgId, onSent: { Task { await loadDashboard() } })
                        .environmentObject(coordinator)
                }
            }
            .task { await loadDashboard() }
        }
    }

    // MARK: - Dashboard Content

    private func dashboardContent(_ data: OrgDashboard) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Org header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(data.orgName)
                            .font(.system(size: 18, weight: .bold))
                        Text(data.orgType)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)

                // Summary cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    summaryCard(
                        value: "\(data.summary.totalMembers)",
                        label: "总成员",
                        color: ink
                    )
                    summaryCard(
                        value: "\(data.summary.activated)",
                        label: "已激活",
                        color: safe
                    )
                    summaryCard(
                        value: "\(data.summary.notInstalled)",
                        label: "未安装",
                        color: data.summary.notInstalled > 0 ? alert : .secondary
                    )
                }

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    summaryCard(
                        value: "\(data.summary.permissionsAbnormal)",
                        label: "权限异常",
                        color: data.summary.permissionsAbnormal > 0 ? warning : .secondary
                    )
                    summaryCard(
                        value: "\(data.summary.recentCheckIns)",
                        label: "近期签到",
                        color: safe
                    )
                    summaryCard(
                        value: "\(data.summary.overdueCheckIns)",
                        label: "超时未签",
                        color: data.summary.overdueCheckIns > 0 ? alert : .secondary
                    )
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button { showAlert = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "megaphone.fill")
                            Text("发送预警")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(alert)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button { showReport = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                            Text("导出报告")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                // Member list
                VStack(alignment: .leading, spacing: 8) {
                    Text("成员状态")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    ForEach(data.members) { member in
                        memberRow(member)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Components

    private func summaryCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
    }

    private func memberRow(_ member: OrgMemberStatus) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor(member.status))
                .frame(width: 8, height: 8)

            Text(member.displayName)
                .font(.system(size: 14))
                .foregroundStyle(ink)

            Spacer()

            if let city = member.cityName {
                Text(city)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(statusLabel(member.status))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(statusColor(member.status))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor(member.status).opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
        )
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "normal": return safe
        case "overdue": return alert
        case "permissions_abnormal": return warning
        case "not_installed": return .secondary
        default: return .secondary
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "normal": return "正常"
        case "overdue": return "超时"
        case "permissions_abnormal": return "权限异常"
        case "not_installed": return "未安装"
        default: return status
        }
    }

    // MARK: - No Org

    private var noOrgView: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(safe.opacity(0.4))
            Text("还没有创建机构")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ink.opacity(0.6))
            Text("机构版可以批量管理成员安全状态，\n一键发送预警，生成合规报告。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { showCreateOrg = true } label: {
                Text("创建机构")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(safe)
                    .clipShape(Capsule())
            }
        }
        .padding(32)
    }

    // MARK: - Load

    private func loadDashboard() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data: OrgDashboard = try await coordinator.apiClient.get("/v1/org/dashboard")
            await MainActor.run { dashboard = data }
        } catch {
            #if DEBUG
            // In dev mode, show mock dashboard data so the UI is demonstrable
            if coordinator.devBypassLogin {
                await MainActor.run { dashboard = Self.devMockDashboard }
            }
            #endif
        }
    }

    #if DEBUG
    private static let devMockDashboard = OrgDashboard(
        orgId: "mock-org-1",
        orgName: "北京大学国际处",
        orgType: "university",
        summary: OrgDashboardSummary(
            totalMembers: 320,
            activated: 298,
            permissionsAbnormal: 12,
            notInstalled: 10,
            recentCheckIns: 245,
            overdueCheckIns: 8
        ),
        members: [
            OrgMemberStatus(userId: "m1", displayName: "张三", status: "normal", lastCheckIn: Date().addingTimeInterval(-1800), cityName: "多伦多", countryCode: "CA"),
            OrgMemberStatus(userId: "m2", displayName: "李四", status: "normal", lastCheckIn: Date().addingTimeInterval(-3600), cityName: "伦敦", countryCode: "GB"),
            OrgMemberStatus(userId: "m3", displayName: "王五", status: "overdue", lastCheckIn: Date().addingTimeInterval(-86400 * 3), cityName: "悉尼", countryCode: "AU"),
            OrgMemberStatus(userId: "m4", displayName: "赵六", status: "permissions_abnormal", lastCheckIn: Date().addingTimeInterval(-7200), cityName: "东京", countryCode: "JP"),
            OrgMemberStatus(userId: "m5", displayName: "孙七", status: "not_installed", lastCheckIn: nil, cityName: "基辅", countryCode: "UA"),
            OrgMemberStatus(userId: "m6", displayName: "周八", status: "normal", lastCheckIn: Date().addingTimeInterval(-900), cityName: "上海", countryCode: "CN"),
        ]
    )
    #endif
}

// MARK: - Create Org Sheet

struct CreateOrgSheet: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    @State private var name = ""
    @State private var type = "university"
    @State private var email = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("机构名称", text: $name)
                Picker("类型", selection: $type) {
                    Text("大学国际处").tag("university")
                    Text("留学中介").tag("agency")
                    Text("外派雇主").tag("employer")
                    Text("劳务派遣").tag("labor")
                    Text("NGO").tag("ngo")
                    Text("其他").tag("other")
                }
                TextField("联系邮箱 (可选)", text: $email)
            }
            .navigationTitle("创建机构")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await create() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("创建").bold() }
                    }
                    .disabled(name.isEmpty || isSaving)
                }
            }
        }
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let _: OrgCreateResponse = try await coordinator.apiClient.post(
                "/v1/org",
                body: OrgCreateRequest(
                    name: name,
                    type: type,
                    contactEmail: email.isEmpty ? nil : email,
                    contactPhone: nil
                )
            )
        } catch {
            #if DEBUG
            print("[Org] create error (using local fallback): \(error)")
            #endif
        }
        onCreated()
        dismiss()
    }
}

// MARK: - Send Alert Sheet

struct SendAlertSheet: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    let orgId: String
    let onSent: () -> Void

    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var title = ""
    @State private var body_ = ""
    @State private var severity = "warning"
    @State private var isSending = false
    @State private var sentResult: OrgAlertResponse?

    var body: some View {
        NavigationStack {
            if let result = sentResult {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("预警已发送")
                        .font(.system(size: 18, weight: .bold))
                    Text("已通知 \(result.sentCount) 人")
                        .foregroundStyle(.secondary)
                    Button("完成") {
                        onSent()
                        dismiss()
                    }
                    .padding(.top, 8)
                    Spacer()
                }
            } else {
                Form {
                    TextField("预警标题", text: $title)
                    TextField("详细描述", text: $body_, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("严重程度", selection: $severity) {
                        Text("提醒").tag("info")
                        Text("警告").tag("warning")
                        Text("紧急").tag("critical")
                    }
                }
                .navigationTitle("发送区域预警")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await send() }
                        } label: {
                            if isSending { ProgressView() } else { Text("发送").bold().foregroundStyle(alert) }
                        }
                        .disabled(title.isEmpty || body_.isEmpty || isSending)
                    }
                }
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            let result: OrgAlertResponse = try await coordinator.apiClient.post(
                "/v1/org/alert",
                body: OrgAlertRequest(
                    orgId: orgId,
                    title: title,
                    body: body_,
                    countryCode: nil,
                    severity: severity
                )
            )
            await MainActor.run { sentResult = result }
        } catch {
            #if DEBUG
            print("[Org] send alert error (using local fallback): \(error)")
            // Show mock result so UI is demonstrable
            let mockResult = OrgAlertResponse(success: true, alertId: UUID().uuidString, sentCount: 298)
            await MainActor.run { sentResult = mockResult }
            #endif
        }
    }
}
