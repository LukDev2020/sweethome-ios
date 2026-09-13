import SwiftUI

// MARK: - Screen A6: Settings
//
// Design from shoudeng-full-design.html:
//   - Profile section (name, avatar, city)
//   - SOS trigger methods (long press, watch, BT button, silent mode)
//   - Check-in schedule (reminder times, overdue threshold)
//   - Language selection
//   - Notification preferences
//   - Data (retention, export, account deletion)

struct ProtectedSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @AppStorage("sos_longPress") private var longPressEnabled = true
    @AppStorage("sos_watch") private var watchEnabled = true
    @AppStorage("sos_silentMode") private var silentMode = false
    @AppStorage("notif_sos_alerts") private var notifSOS = true
    @AppStorage("notif_checkin_reminder") private var notifCheckin = true
    @AppStorage("notif_family_feed") private var notifFamilyFeed = true

    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)

    @State private var showProfileEdit = false
    @State private var showPrivacy = false
    @State private var showAbout = false
    @State private var showDeleteConfirm = false
    @State private var showExportAlert = false
    @State private var showRoleSwitchInfo = false
    @State private var showDeleteError = false
    @State private var showExportSent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Header
                    Text("求助方式与隐私")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    // Profile
                    profilePanel

                    // Role
                    rolePanel

                    // SOS trigger methods
                    sosTriggerPanel

                    // Check-in schedule
                    checkInPanel

                    // Language
                    languagePanel

                    // Notifications
                    notificationPanel

                    // Data
                    dataPanel

                    // Legal & About
                    legalPanel

                    #if DEBUG
                    devPanel
                    #endif

                    Text("求助方式给三种冗余：手机没在手上时，手表或实体按钮仍能触发。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
            }
            .background(Color(.systemBackground))
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showProfileEdit, onDismiss: {
                Task {
                    await coordinator.fetchUserProfile()
                    await coordinator.fetchGuardians()
                }
            }) {
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
                Button("请求导出") {
                    Task { await requestDataExport() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("确认后，数据将在 24 小时内通过邮件发送给您。")
            }
            .alert("导出已提交", isPresented: $showExportSent) {
                Button("确定") {}
            } message: {
                Text("导出请求已发送，数据将在 24 小时内通过邮件发送给您。")
            }
            .alert("操作失败", isPresented: $showDeleteError) {
                Button("确定") {}
            } message: {
                Text("操作未能完成，请检查网络连接后重试。")
            }
            .alert("切换角色", isPresented: $showRoleSwitchInfo) {
                Button("我知道了") {}
            } message: {
                Text("切换角色需要守护者同意。请联系您的守护者发起角色变更申请。")
            }
            .onChange(of: notifSOS) { coordinator.syncNotificationPrefs() }
            .onChange(of: notifCheckin) { coordinator.syncNotificationPrefs() }
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
                    AvatarView(user: coordinator.currentUser, size: 36)
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

    // MARK: - SOS Trigger Panel

    private var sosTriggerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("怎样触发求助")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            toggleRow("App 内长按 3 秒", isOn: $longPressEnabled)
            toggleRow("手表快捷键", isOn: $watchEnabled)
            fixedRow("蓝牙实体按钮", value: "未配对", isWarning: true)
            toggleRow("静默模式 · 本机无提示", isOn: $silentMode)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Check-in Panel

    private var checkInPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("定时报平安")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            fixedRow("每天提醒", value: "09:00、21:00", isWarning: false)
            fixedRow("超时多久算失联", value: "4 小时", isWarning: false)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
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
            if !langManager.current.isFullySupported {
                Text("当前仅登录页面支持此语言，主界面将逐步适配")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
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
            toggleRow("报平安提醒", isOn: $notifCheckin)
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
            fixedRow("位置保留时长", value: "90 天后自动删除", isWarning: false)
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

    // MARK: - Role Panel

    private var rolePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前角色")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(safe)
                VStack(alignment: .leading, spacing: 1) {
                    Text("被守护者")
                        .font(.system(size: 13, weight: .medium))
                    Text("家人会收到您的安全信号")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)

            Button { showRoleSwitchInfo = true } label: {
                HStack {
                    Text("申请切换为守护者")
                        .font(.system(size: 13))
                    Spacer()
                    Text("需守护者同意")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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

    // MARK: - Dev Panel

    #if DEBUG
    private var devPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("开发者选项")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack {
                Text("切换角色视图").font(.system(size: 13))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        coordinator.userRole = coordinator.userRole == .protected_ ? .guardian : .protected_
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: coordinator.userRole == .protected_ ? "shield.fill" : "eye.fill")
                            .font(.system(size: 10))
                        Text(coordinator.userRole == .protected_ ? "被守护者" : "守护者")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(coordinator.userRole == .protected_ ? safe : pro)
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Text("DEV")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(.orange))
                .offset(x: -8, y: -8)
        }
    }
    #endif

    // MARK: - Account Deletion

    private func deleteAccount() async {
        do {
            let _: EmptyResponse = try await coordinator.apiClient.post(
                "/v1/user/delete",
                body: EmptyBody()
            )
            coordinator.authManager.logout()
        } catch {
            showDeleteError = true
        }
    }

    private func requestDataExport() async {
        do {
            let _: EmptyResponse = try await coordinator.apiClient.post(
                "/v1/user/export",
                body: EmptyBody()
            )
            showExportSent = true
        } catch {
            showDeleteError = true
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
