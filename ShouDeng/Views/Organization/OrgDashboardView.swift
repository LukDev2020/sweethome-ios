import SwiftUI

// MARK: - Organization Dashboard View
//
// Compliance dashboard for institutional clients.
// Shows: "320 members, 298 activated, 12 permissions abnormal, 10 not installed"
// This is literally what institutions pay for — proof of duty of care.

struct OrgDashboardView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let ink = Color.appInk
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
            .navigationTitle(langManager.localized("org.navTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label(langManager.localized("org.close"), systemImage: "xmark") }
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
                            .font(.scaled(size: 18, weight: .bold))
                        Text(data.orgType)
                            .font(.scaled(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)

                // Riders who joined through our partner link (totals only)
                OrgRidersPanel()
                    .environmentObject(coordinator)

                // Summary cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12) {
                    summaryCard(
                        value: "\(data.summary.totalMembers)",
                        label: langManager.localized("org.totalMembers"),
                        color: ink
                    )
                    summaryCard(
                        value: "\(data.summary.activated)",
                        label: langManager.localized("org.activated"),
                        color: safe
                    )
                    summaryCard(
                        value: "\(data.summary.notInstalled)",
                        label: langManager.localized("org.notInstalled"),
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
                        label: langManager.localized("org.permissionsAbnormal"),
                        color: data.summary.permissionsAbnormal > 0 ? warning : .secondary
                    )
                    summaryCard(
                        value: "\(data.summary.recentCheckIns)",
                        label: langManager.localized("org.recentCheckIns"),
                        color: safe
                    )
                    summaryCard(
                        value: "\(data.summary.overdueCheckIns)",
                        label: langManager.localized("org.overdueCheckIns"),
                        color: data.summary.overdueCheckIns > 0 ? alert : .secondary
                    )
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button { showAlert = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "megaphone.fill")
                            Text(langManager.localized("org.sendAlert"))
                        }
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(alert)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button { showReport = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                            Text(langManager.localized("org.exportReport"))
                        }
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                // Member list
                VStack(alignment: .leading, spacing: 8) {
                    Text(langManager.localized("org.memberStatus"))
                        .font(.scaled(size: 12))
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
                .font(.scaled(size: 24, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.scaled(size: 12))
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
                .font(.scaled(size: 14))
                .foregroundStyle(ink)

            Spacer()

            if let city = member.cityName {
                Text(city)
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(statusLabel(member.status))
                .font(.scaled(size: 12, weight: .medium))
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
        case "normal": return langManager.localized("org.statusNormal")
        case "overdue": return langManager.localized("org.statusOverdue")
        case "permissions_abnormal": return langManager.localized("org.statusPermissions")
        case "not_installed": return langManager.localized("org.statusNotInstalled")
        default: return status
        }
    }

    // MARK: - No Org

    private var noOrgView: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2.fill")
                .font(.scaled(size: 40))
                .foregroundStyle(safe.opacity(0.4))
            Text(langManager.localized("org.noOrgTitle"))
                .font(.scaled(size: 16, weight: .medium))
                .foregroundStyle(ink.opacity(0.6))
            Text(langManager.localized("org.noOrgDesc"))
                .font(.scaled(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { showCreateOrg = true } label: {
                Text(langManager.localized("org.createOrg"))
                    .font(.scaled(size: 14, weight: .medium))
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
        // Show "no org" state after 5 seconds if API hasn't responded
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if isLoading {
                await MainActor.run { isLoading = false }
            }
        }
        defer {
            timeoutTask.cancel()
            isLoading = false
        }
        do {
            let data: OrgDashboard = try await coordinator.apiClient.get("/v1/org/dashboard")
            await MainActor.run { dashboard = data }
        } catch {
            #if DEBUG
            print("[Org] dashboard load error: \(error)")
            #endif
        }
    }

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
                TextField(LanguageManager.shared.localized("org.orgName"), text: $name)
                Picker(LanguageManager.shared.localized("org.orgType"), selection: $type) {
                    Text(LanguageManager.shared.localized("org.typeUniversity")).tag("university")
                    Text(LanguageManager.shared.localized("org.typeAgency")).tag("agency")
                    Text(LanguageManager.shared.localized("org.typeEmployer")).tag("employer")
                    Text(LanguageManager.shared.localized("org.typeLabor")).tag("labor")
                    Text("NGO").tag("ngo")
                    Text(LanguageManager.shared.localized("org.typeOther")).tag("other")
                }
                TextField(LanguageManager.shared.localized("org.contactEmail"), text: $email)
            }
            .navigationTitle(LanguageManager.shared.localized("org.createOrg"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Label(LanguageManager.shared.localized("org.cancel"), systemImage: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await create() }
                    } label: {
                        if isSaving { ProgressView() } else { Label(LanguageManager.shared.localized("org.create"), systemImage: "checkmark") }
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
                        .font(.scaled(size: 48))
                        .foregroundStyle(.green)
                    Text(LanguageManager.shared.localized("org.alertSent"))
                        .font(.scaled(size: 18, weight: .bold))
                    Text(String(format: LanguageManager.shared.localized("org.alertNotified"), result.sentCount))
                        .foregroundStyle(.secondary)
                    Button(LanguageManager.shared.localized("org.done")) {
                        onSent()
                        dismiss()
                    }
                    .padding(.top, 8)
                    Spacer()
                }
            } else {
                Form {
                    TextField(LanguageManager.shared.localized("org.alertTitle"), text: $title)
                    TextField(LanguageManager.shared.localized("org.alertDesc"), text: $body_, axis: .vertical)
                        .lineLimit(3...6)
                    Picker(LanguageManager.shared.localized("org.alertSeverity"), selection: $severity) {
                        Text(LanguageManager.shared.localized("org.severityInfo")).tag("info")
                        Text(LanguageManager.shared.localized("org.severityWarning")).tag("warning")
                        Text(LanguageManager.shared.localized("org.severityCritical")).tag("critical")
                    }
                }
                .navigationTitle(LanguageManager.shared.localized("org.sendRegionAlert"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Label(LanguageManager.shared.localized("org.cancel"), systemImage: "xmark") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await send() }
                        } label: {
                            if isSending { ProgressView() } else { Label(LanguageManager.shared.localized("org.send"), systemImage: "paperplane").foregroundStyle(alert) }
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
            print("[Org] send alert error: \(error)")
            #endif
        }
    }
}

// MARK: - Riders (partner link)

struct OrgRiderStats: Decodable {
    let orgName: String
    let partnerCode: String?
    let riders: Int
    let notCounted: Int
    let activeLast7d: Int
    let onShiftNow: Int
    let sosLast30d: Int
}

struct OrgPartnerCode: Decodable { let code: String; let name: String; let link: String }

/// A delivery platform, union or rider community: the link riders sign up with, and
/// totals over riders who agreed to be counted — never names or positions.
struct OrgRidersPanel: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var stats: OrgRiderStats?
    @State private var link: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(lang.localized("org.riders.title"), systemImage: "bicycle")
                .font(.scaled(size: 15, weight: .semibold))
            if let stats {
                HStack(spacing: 8) {
                    tile("\(stats.riders)", "org.riders.count")
                    tile("\(stats.activeLast7d)", "org.riders.active")
                    tile("\(stats.onShiftNow)", "org.riders.onShift")
                    tile("\(stats.sosLast30d)", "org.riders.sos")
                }
                if stats.notCounted > 0 {
                    Text(String(format: lang.localized("org.riders.notCounted"), stats.notCounted))
                        .font(.scaled(size: 12)).foregroundStyle(.secondary)
                }
            }
            if let link {
                ShareLink(item: URL(string: link)!, message: Text(lang.localized("org.riders.shareMessage"))) {
                    Label(lang.localized("org.riders.share"), systemImage: "square.and.arrow.up")
                        .font(.scaled(size: 14, weight: .semibold))
                }
                Text(link).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            } else {
                Button(lang.localized("org.riders.getLink")) { Task { await loadLink() } }
                    .font(.scaled(size: 14, weight: .semibold))
            }
            Text(lang.localized("org.riders.privacy"))
                .font(.scaled(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        .task { await loadStats() }
    }

    private func tile(_ value: String, _ key: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.scaled(size: 20, weight: .bold))
            Text(lang.localized(key)).font(.scaled(size: 10)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadStats() async {
        stats = try? await coordinator.apiClient.get("/v1/org/riders")
        if let code = stats?.partnerCode { link = "https://shoudeng.app/start?for=rider&org=\(code)" }
    }

    private func loadLink() async {
        let r: OrgPartnerCode? = try? await coordinator.apiClient.post("/v1/org/partner-code", body: EmptyBody())
        link = r?.link
    }
}
