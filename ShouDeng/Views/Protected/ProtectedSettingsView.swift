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
    @ObservedObject private var fontScaleManager = FontScaleManager.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @AppStorage("sos_longPress") private var longPressEnabled = true
    @AppStorage("sos_watch") private var watchEnabled = true
    @AppStorage("sos_silentMode") private var silentMode = false
    @AppStorage("distress_detection_enabled") private var distressDetectionEnabled = false
    @AppStorage("voice_command_enabled") private var voiceCommandEnabled = false
    @AppStorage("notif_sos_alerts") private var notifSOS = true
    @AppStorage("notif_checkin_reminder") private var notifCheckin = true
    @AppStorage("notif_family_feed") private var notifFamilyFeed = true
    @AppStorage("lockscreen_card_enabled") private var lockscreenCardEnabled = true

    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)
    private let creamBg = Color(red: 254/255, green: 252/255, blue: 247/255)
    private let offWhiteBg = Color(red: 251/255, green: 248/255, blue: 241/255)
    private let paneBorder = Color(red: 1/255, green: 69/255, blue: 129/255).opacity(0.13)

    @State private var showProfileEdit = false
    @State private var showPrivacy = false
    @State private var showAbout = false
    @State private var showDeleteConfirm = false
    @State private var showExportAlert = false
    @State private var showRoleSwitchInfo = false
    @State private var showDeleteError = false
    @State private var showExportSent = false
    @State private var showMedicalCard = false
    @State private var showEmergencyText = false
    @State private var showConsulate = false
    @State private var showClaimMaterials = false

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    settingsDuoPane
                } else {
                    settingsCompact
                }
            }
            .navigationTitle(langManager.localized("settings.title"))
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
            .sheet(isPresented: $showMedicalCard) {
                MedicalCardView().environmentObject(coordinator)
            }
            .sheet(isPresented: $showEmergencyText) {
                EmergencyTextCardView().environmentObject(coordinator)
            }
            .sheet(isPresented: $showConsulate) {
                ConsulateView().environmentObject(coordinator)
            }
            .sheet(isPresented: $showClaimMaterials) {
                ClaimMaterialsView().environmentObject(coordinator)
            }
            .onChange(of: notifSOS) { coordinator.syncNotificationPrefs() }
            .onChange(of: notifCheckin) { coordinator.syncNotificationPrefs() }
            .onChange(of: notifFamilyFeed) { coordinator.syncNotificationPrefs() }
        }
    }

    // MARK: - Layout Variants

    private var settingsCompact: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("求助方式与隐私")
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                profilePanel
                emailMissingBanner
                rolePanel
                sosTriggerPanel
                smartDetectionPanel
                checkInPanel
                safetyToolsPanel
                lockScreenCardPanel
                securityPanel
                languagePanel
                fontSizePanel
                notificationPanel
                dataPanel
                legalPanel
                #if DEBUG
                devPanel
                #endif
                Text("求助方式给三种冗余：手机没在手上时，手表或实体按钮仍能触发。")
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
    }

    private var settingsDuoPane: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    Text("账户与求助")
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    profilePanel
                    emailMissingBanner
                    rolePanel
                    sosTriggerPanel
                    smartDetectionPanel
                    checkInPanel
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
            }
            .frame(width: 445)
            .background(creamBg)

            Rectangle().fill(paneBorder).frame(width: 1)

            ScrollView {
                VStack(spacing: 12) {
                    Text("工具与安全")
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    safetyToolsPanel
                    lockScreenCardPanel
                    securityPanel
                    languagePanel
                    notificationPanel
                    dataPanel
                    legalPanel
                    #if DEBUG
                    devPanel
                    #endif
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity)
            .background(offWhiteBg)
        }
    }

    // MARK: - Profile Panel

    private var profilePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("个人资料")
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            Button { showProfileEdit = true } label: {
                HStack(spacing: 10) {
                    AvatarView(user: coordinator.currentUser, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(coordinator.currentUser?.displayName ?? "未设置")
                            .font(.scaled(size: 13, weight: .medium))
                            .foregroundStyle(ink)
                        Text(coordinator.currentUser?.cityName ?? "")
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.scaled(size: 11))
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

    // MARK: - Email Missing Banner

    @ViewBuilder
    private var emailMissingBanner: some View {
        if let user = coordinator.currentUser, (user.email ?? "").isEmpty {
            Button { showProfileEdit = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.scaled(size: 14))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("添加邮箱以便找回账号")
                            .font(.scaled(size: 13, weight: .medium))
                            .foregroundStyle(ink)
                        Text("遇到换手机或号码失效时可通过邮箱找回")
                            .font(.scaled(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.15), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - SOS Trigger Panel

    private var sosTriggerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("怎样触发求助")
                .font(.scaled(size: 12))
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

    // MARK: - Smart Detection Panel

    private var smartDetectionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("智能检测")
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                toggleRow("异常声音检测", isOn: $distressDetectionEnabled)
                Text("检测到尖叫等异常声音时自动触发 60 秒倒计时。全部在本机处理，不上传录音。")
                    .font(.scaled(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
            }
            .onChange(of: distressDetectionEnabled) { _, enabled in
                coordinator.audioCoordinator.distressDetectionEnabled = enabled
            }

            VStack(alignment: .leading, spacing: 2) {
                toggleRow("语音求助", isOn: $voiceCommandEnabled)
                Text("说出「救命」「help」即可触发求助。需要麦克风和语音识别权限。")
                    .font(.scaled(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
            }
            .onChange(of: voiceCommandEnabled) { _, enabled in
                if enabled {
                    VoiceCommandService.requestAuthorization { authorized in
                        if !authorized {
                            voiceCommandEnabled = false
                        }
                    }
                }
                coordinator.audioCoordinator.voiceCommandEnabled = enabled
            }
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
                .font(.scaled(size: 12))
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

    // MARK: - Safety Tools Panel

    private var safetyToolsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("安全工具")
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            Button { showMedicalCard = true } label: {
                fixedRow("紧急医疗卡", value: "编辑 →", isWarning: false)
            }
            .buttonStyle(.plain)

            // Lock screen hint
            HStack(spacing: 6) {
                Image(systemName: "lock.display")
                    .font(.scaled(size: 11))
                    .foregroundStyle(.orange)
                Text("在医疗卡中标记急救的药品会显示在锁屏小组件和实时活动中")
                    .font(.scaled(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button { showEmergencyText = true } label: {
                fixedRow("多语言急救卡", value: "查看 →", isWarning: false)
            }
            .buttonStyle(.plain)

            Button { showConsulate = true } label: {
                fixedRow("领事与紧急电话", value: "查看 →", isWarning: false)
            }
            .buttonStyle(.plain)

            Button { showClaimMaterials = true } label: {
                fixedRow("理赔材料整理", value: "开始 →", isWarning: false)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Lock Screen Card Panel

    private var lockScreenCardPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("settings.lockscreen"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "rectangle.on.rectangle.badge.person.crop")
                    .font(.scaled(size: 14))
                    .foregroundStyle(safe)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(langManager.localized("settings.lockscreen"))
                        .font(.scaled(size: 13))
                    Text(langManager.localized("settings.lockscreen.desc"))
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $lockscreenCardEnabled)
                    .labelsHidden()
                    .tint(safe)
            }
            .padding(.vertical, 2)
            .onChange(of: lockscreenCardEnabled) { _, enabled in
                if enabled {
                    coordinator.startLiveActivityIfNeeded()
                } else {
                    coordinator.liveActivityManager.endAllActivities()
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Security Panel

    private var securityPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("settings.security"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            if BiometricAuthManager.shared.isAvailable {
                HStack {
                    Image(systemName: BiometricAuthManager.shared.biometricIconName)
                        .font(.scaled(size: 14))
                        .foregroundStyle(safe)
                        .frame(width: 20)
                    Text("\(BiometricAuthManager.shared.biometricName) 登录")
                        .font(.scaled(size: 13))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { BiometricAuthManager.shared.isEnabled },
                        set: { newValue in
                            if newValue {
                                try? BiometricAuthManager.shared.enable()
                            } else {
                                BiometricAuthManager.shared.disable()
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(safe)
                }
                .padding(.vertical, 2)
            } else {
                HStack {
                    Image(systemName: "lock.fill")
                        .font(.scaled(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text("此设备不支持生物识别登录")
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
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
            Text(langManager.localized("settings.language"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            HStack {
                Text(langManager.localized("settings.language")).font(.scaled(size: 13))
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

    // MARK: - Font Size Panel

    private var fontSizePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("settings.fontsize"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(FontScaleLevel.allCases, id: \.self) { level in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            fontScaleManager.level = level
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text("字")
                                .font(.system(size: 11 * level.scale, weight: .medium))
                                .foregroundStyle(fontScaleManager.level == level ? .white : ink)
                            Text(level.label)
                                .font(.system(size: 10))
                                .foregroundStyle(fontScaleManager.level == level ? .white.opacity(0.9) : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(fontScaleManager.level == level ? safe : Color(.secondarySystemBackground))
                        )
                    }
                }
            }
            Text("调整后所有页面文字大小会立即变化")
                .font(.scaled(size: 11))
                .foregroundStyle(.secondary.opacity(0.7))
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
                .font(.scaled(size: 12))
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
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            fixedRow("位置保留时长", value: "90 天后自动删除", isWarning: false)
            Button { showExportAlert = true } label: {
                fixedRow("导出我的全部数据", value: "请求导出 →", isWarning: false)
            }
            .buttonStyle(.plain)
            Button { showDeleteConfirm = true } label: {
                fixedRow(langManager.localized("settings.delete.account"), value: "", isWarning: true)
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
                .font(.scaled(size: 12))
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
                fixedRow(langManager.localized("settings.logout"), value: "", isWarning: true)
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
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .font(.scaled(size: 14))
                    .foregroundStyle(safe)
                VStack(alignment: .leading, spacing: 1) {
                    Text("被守护者")
                        .font(.scaled(size: 13, weight: .medium))
                    Text("家人会收到您的安全信号")
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)

            Button { showRoleSwitchInfo = true } label: {
                HStack {
                    Text("申请切换为守护者")
                        .font(.scaled(size: 13))
                    Spacer()
                    Text("需守护者同意")
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.scaled(size: 11))
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
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                Text("切换角色视图").font(.scaled(size: 13))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        coordinator.userRole = coordinator.userRole == .protected_ ? .guardian : .protected_
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: coordinator.userRole == .protected_ ? "shield.fill" : "eye.fill")
                            .font(.scaled(size: 10))
                        Text(coordinator.userRole == .protected_ ? "被守护者" : "守护者")
                            .font(.scaled(size: 12, weight: .medium))
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.scaled(size: 9))
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
                .font(.scaled(size: 11, weight: .bold, design: .monospaced))
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
            Text(label).font(.scaled(size: 13))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(safe)
        }
        .padding(.vertical, 2)
    }

    private func fixedRow(_ label: String, value: String, isWarning: Bool) -> some View {
        HStack {
            Text(label).font(.scaled(size: 13))
            Spacer()
            Text(value)
                .font(.scaled(size: 11.5))
                .foregroundStyle(isWarning ? alert : .secondary)
        }
        .padding(.vertical, 2)
    }
}
