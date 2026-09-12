import SwiftUI

// MARK: - Guardian Settings View
//
// Settings for the guardian portal: profile, language, notifications,
// data, legal, logout, and account deletion.

struct GuardianSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var showProfileEdit = false
    @State private var showPrivacy = false
    @State private var showAbout = false
    @State private var showDeleteConfirm = false
    @State private var showExportAlert = false

    @AppStorage("notif_sos_alerts") private var notifSOS = true
    @AppStorage("notif_checkin_overdue") private var notifCheckinOverdue = true
    @AppStorage("notif_family_feed") private var notifFamilyFeed = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Header
                    VStack(spacing: 2) {
                        Text("设置")
                            .font(.system(size: 20, weight: .bold))
                        Text("守护者偏好")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Profile
                    profilePanel

                    // Subscription
                    subscriptionPanel

                    // Language
                    languagePanel

                    // Notifications
                    notificationPanel

                    // Data
                    dataPanel

                    // Legal & About
                    legalPanel
                }
                .padding(.horizontal, 16)
            }
            .background(Color(.systemBackground))
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showProfileEdit) {
                ProfileEditView()
                    .environmentObject(coordinator)
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacyPolicyView()
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
            }
            .alert("确认注销", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("永久删除", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("注销账号将永久删除您的所有数据，此操作不可撤销。")
            }
            .alert("数据导出", isPresented: $showExportAlert) {
                Button("确定") {}
            } message: {
                Text("导出请求已发送，数据将在 24 小时内通过邮件发送给您。")
            }
            .onChange(of: notifSOS) { coordinator.syncNotificationPrefs() }
            .onChange(of: notifCheckinOverdue) { coordinator.syncNotificationPrefs() }
            .onChange(of: notifFamilyFeed) { coordinator.syncNotificationPrefs() }
        }
    }

    // MARK: - Profile Panel

    private var profilePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("个人资料")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button { showProfileEdit = true } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 36, height: 36)
                        Text(coordinator.currentUser?.avatarInitial ?? "?")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ink)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(coordinator.currentUser?.displayName ?? "未设置")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ink)
                        Text(coordinator.currentUser?.cityName ?? "")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Subscription Panel

    private var subscriptionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("订阅与账单")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if let status = coordinator.storeKitManager.subscriptionStatus, status.isActive {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(safe)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(coordinator.storeKitManager.planDisplayName(for: status.planId))
                            .font(.system(size: 13, weight: .medium))
                        if let expires = status.expiresDate {
                            Text("有效期至 \(expires.formatted(.dateTime.year().month().day()))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "gift")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("免费版")
                            .font(.system(size: 13, weight: .medium))
                        Text("升级解锁更强守护功能")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }

            NavigationLink {
                GuardianPlanBillingView()
                    .environmentObject(coordinator)
            } label: {
                HStack {
                    Text(coordinator.storeKitManager.subscriptionStatus?.isActive == true
                         ? "管理方案与账单" : "查看方案")
                        .font(.system(size: 13))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
        .task {
            await coordinator.storeKitManager.refreshSubscriptionStatus()
        }
    }

    // MARK: - Language Panel

    private var languagePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("语言")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Text("界面语言").font(.system(size: 13))
                Spacer()
                Picker("", selection: $langManager.current) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.fullName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .tint(safe)
            }
            .padding(.vertical, 2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Notification Panel

    private var notificationPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("通知偏好")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            toggleRow("紧急求助 (SOS)", isOn: $notifSOS)
            toggleRow("报平安超时提醒", isOn: $notifCheckinOverdue)
            toggleRow("家庭圈新动态", isOn: $notifFamilyFeed)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Data Panel

    private var dataPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("数据")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button { showExportAlert = true } label: {
                fixedRow("导出我的全部数据", value: "请求导出 →", isWarning: false)
            }
            .buttonStyle(.plain)
            Button { showDeleteConfirm = true } label: {
                fixedRow("注销账号", value: "永久删除", isWarning: true)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Legal Panel

    private var legalPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("法律与关于")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button { showPrivacy = true } label: {
                fixedRow("隐私政策与服务条款", value: "查看 →", isWarning: false)
            }
            .buttonStyle(.plain)
            Button { showAbout = true } label: {
                fixedRow("关于守灯", value: "v1.0.0", isWarning: false)
            }
            .buttonStyle(.plain)
            Button { coordinator.authManager.logout() } label: {
                fixedRow("退出登录", value: "", isWarning: true)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func deleteAccount() async {
        do {
            let _: EmptyResponse = try await coordinator.apiClient.post(
                "/v1/user/delete",
                body: EmptyBody()
            )
            coordinator.authManager.logout()
        } catch {
            #if DEBUG
            print("[GuardianSettings] Delete account failed: \(error)")
            #endif
        }
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

    private func fixedRow(_ label: String, value: String, isWarning: Bool) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(isWarning ? alert : .secondary)
        }
        .padding(.vertical, 2)
    }
}
