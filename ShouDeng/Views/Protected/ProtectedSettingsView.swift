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

    @AppStorage("app_dark_mode") private var darkModeEnabled = false
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
    @State private var showDuressCode = false
    @State private var showSilentAlarm = false
    @State private var showBLETracker = false

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
            .alert(langManager.localized("settings.alert.deleteAccount.title"), isPresented: $showDeleteConfirm) {
                Button(langManager.localized("settings.action.cancel"), role: .cancel) {}
                Button(langManager.localized("settings.action.deletePermanently"), role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text(langManager.localized("settings.alert.deleteAccount.message"))
            }
            .alert(langManager.localized("settings.alert.dataExport.title"), isPresented: $showExportAlert) {
                Button(langManager.localized("settings.action.requestExport")) {
                    Task { await requestDataExport() }
                }
                Button(langManager.localized("settings.action.cancel"), role: .cancel) {}
            } message: {
                Text(langManager.localized("settings.alert.dataExport.message"))
            }
            .alert(langManager.localized("settings.alert.exportSent.title"), isPresented: $showExportSent) {
                Button(langManager.localized("settings.action.ok")) {}
            } message: {
                Text(langManager.localized("settings.alert.exportSent.message"))
            }
            .alert(langManager.localized("settings.alert.error.title"), isPresented: $showDeleteError) {
                Button(langManager.localized("settings.action.ok")) {}
            } message: {
                Text(langManager.localized("settings.alert.error.message"))
            }
            .alert(langManager.localized("settings.alert.roleSwitch.title"), isPresented: $showRoleSwitchInfo) {
                Button(langManager.localized("settings.action.understood")) {}
            } message: {
                Text(langManager.localized("protected.settings.alert.roleSwitch.message"))
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
            .sheet(isPresented: $showDuressCode) {
                DuressCodeSettingsView().environmentObject(coordinator)
            }
            .sheet(isPresented: $showSilentAlarm) {
                SilentAlarmSettingsView().environmentObject(coordinator)
            }
            .sheet(isPresented: $showBLETracker) {
                BLETrackerSettingsView().environmentObject(coordinator)
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
                Text(langManager.localized("protected.settings.section.sosAndPrivacy"))
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
                darkModePanel
                notificationPanel
                dataPanel
                legalPanel
                #if DEBUG
                devPanel
                #endif
                Text(langManager.localized("protected.settings.sos.redundancyHint"))
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
                    Text(langManager.localized("protected.settings.section.accountAndSos"))
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
                    Text(langManager.localized("settings.section.toolsAndSecurity"))
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
            Text(langManager.localized("settings.section.profile"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            Button { showProfileEdit = true } label: {
                HStack(spacing: 10) {
                    AvatarView(user: coordinator.currentUser, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(coordinator.currentUser?.displayName ?? langManager.localized("settings.profile.notSet"))
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
                        Text(langManager.localized("settings.email.addTitle"))
                            .font(.scaled(size: 13, weight: .medium))
                            .foregroundStyle(ink)
                        Text(langManager.localized("settings.email.addDesc"))
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
            Text(langManager.localized("protected.settings.section.sosTrigger"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            toggleRow(langManager.localized("protected.settings.sos.longPress"), isOn: $longPressEnabled)
            toggleRow(langManager.localized("protected.settings.sos.watch"), isOn: $watchEnabled)
            fixedRow(langManager.localized("protected.settings.sos.bluetooth"), value: langManager.localized("protected.settings.sos.notPaired"), isWarning: true)
            toggleRow(langManager.localized("protected.settings.sos.silentMode"), isOn: $silentMode)
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
            Text(langManager.localized("protected.settings.section.smartDetection"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                toggleRow(langManager.localized("protected.settings.detection.distress"), isOn: $distressDetectionEnabled)
                Text(langManager.localized("protected.settings.detection.distressDesc"))
                    .font(.scaled(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
            }
            .onChange(of: distressDetectionEnabled) { _, enabled in
                coordinator.audioCoordinator.distressDetectionEnabled = enabled
            }

            VStack(alignment: .leading, spacing: 2) {
                toggleRow(langManager.localized("protected.settings.detection.voiceCommand"), isOn: $voiceCommandEnabled)
                Text(langManager.localized("protected.settings.detection.voiceCommandDesc"))
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
            Text(langManager.localized("protected.settings.section.checkIn"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            fixedRow(langManager.localized("protected.settings.checkIn.dailyReminder"), value: "09:00、21:00", isWarning: false)
            fixedRow(langManager.localized("protected.settings.checkIn.overdueThreshold"), value: langManager.localized("protected.settings.checkIn.fourHours"), isWarning: false)
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
            Text(langManager.localized("settings.section.safetyTools"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            Button { showMedicalCard = true } label: {
                fixedRow(langManager.localized("settings.safetyTools.medicalCard"), value: langManager.localized("settings.action.edit"), isWarning: false)
            }
            .buttonStyle(.plain)

            // Lock screen hint
            HStack(spacing: 6) {
                Image(systemName: "lock.display")
                    .font(.scaled(size: 11))
                    .foregroundStyle(.orange)
                Text(langManager.localized("protected.settings.safetyTools.lockscreenHint"))
                    .font(.scaled(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button { showEmergencyText = true } label: {
                fixedRow(langManager.localized("settings.safetyTools.emergencyCard"), value: langManager.localized("settings.action.view"), isWarning: false)
            }
            .buttonStyle(.plain)

            Button { showConsulate = true } label: {
                fixedRow(langManager.localized("settings.safetyTools.consulate"), value: langManager.localized("settings.action.view"), isWarning: false)
            }
            .buttonStyle(.plain)

            Button { showClaimMaterials = true } label: {
                fixedRow(langManager.localized("settings.safetyTools.claimMaterials"), value: langManager.localized("settings.action.start"), isWarning: false)
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
                    Text(String(format: langManager.localized("settings.security.biometricLogin"), BiometricAuthManager.shared.biometricName))
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
                    Text(langManager.localized("settings.security.biometricUnavailable"))
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Divider().padding(.vertical, 4)

            // Duress code
            Button { showDuressCode = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.scaled(size: 14))
                        .foregroundStyle(.orange)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(langManager.localized("settings.security.duressCode"))
                            .font(.scaled(size: 13))
                            .foregroundStyle(ink)
                        Text(langManager.localized("settings.security.duressCodeDesc"))
                            .font(.scaled(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(KeychainHelper.shared.read(.duressCode) != nil ? langManager.localized("settings.status.configured") : langManager.localized("settings.status.notConfigured"))
                        .font(.scaled(size: 11))
                        .foregroundStyle(KeychainHelper.shared.read(.duressCode) != nil ? safe : .secondary)
                    Image(systemName: "chevron.right")
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            // Silent alarm
            Button { showSilentAlarm = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bell.slash.fill")
                        .font(.scaled(size: 14))
                        .foregroundStyle(.orange)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(langManager.localized("protected.settings.security.silentAlarm"))
                            .font(.scaled(size: 13))
                            .foregroundStyle(ink)
                        Text(langManager.localized("protected.settings.security.silentAlarmDesc"))
                            .font(.scaled(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(SilentAlarmService.shared.isEnabled ? langManager.localized("settings.status.enabled") : langManager.localized("settings.status.disabled"))
                        .font(.scaled(size: 11))
                        .foregroundStyle(SilentAlarmService.shared.isEnabled ? safe : .secondary)
                    Image(systemName: "chevron.right")
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            // BLE tracker
            Button { showBLETracker = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.scaled(size: 14))
                        .foregroundStyle(safe)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(langManager.localized("settings.security.bleTracker"))
                            .font(.scaled(size: 13))
                            .foregroundStyle(ink)
                        Text(langManager.localized("settings.security.bleTrackerDesc"))
                            .font(.scaled(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: langManager.localized("settings.security.deviceCount"), BLETrackerService.shared.pairedTags.count))
                        .font(.scaled(size: 11))
                        .foregroundStyle(BLETrackerService.shared.pairedTags.isEmpty ? .secondary : safe)
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
                            Text(langManager.localized("settings.fontsize.sample"))
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
            Text(langManager.localized("settings.fontsize.hint"))
                .font(.scaled(size: 11))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Dark Mode Panel

    private var darkModePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("settings.appearance", fallback: "Appearance"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: darkModeEnabled ? "moon.fill" : "sun.max.fill")
                    .font(.scaled(size: 14))
                    .foregroundStyle(darkModeEnabled ? .indigo : .orange)
                    .frame(width: 20)
                Text(langManager.localized("settings.darkMode", fallback: "Dark Mode"))
                    .font(.scaled(size: 13))
                Spacer()
                Toggle("", isOn: $darkModeEnabled)
                    .labelsHidden()
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
            Text(langManager.localized("settings.section.notifications"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            toggleRow(langManager.localized("settings.notification.sos"), isOn: $notifSOS)
            toggleRow(langManager.localized("protected.settings.notification.checkInReminder"), isOn: $notifCheckin)
            toggleRow(langManager.localized("settings.notification.familyFeed"), isOn: $notifFamilyFeed)
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
            Text(langManager.localized("settings.section.data"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            fixedRow(langManager.localized("settings.data.locationRetention"), value: langManager.localized("settings.data.locationRetentionValue"), isWarning: false)
            Button { showExportAlert = true } label: {
                fixedRow(langManager.localized("settings.data.exportAll"), value: langManager.localized("settings.action.requestExport"), isWarning: false)
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
            Text(langManager.localized("settings.section.legal"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            Button { showPrivacy = true } label: {
                fixedRow(langManager.localized("settings.legal.privacyAndTerms"), value: langManager.localized("settings.action.view"), isWarning: false)
            }
            .buttonStyle(.plain)
            Button { showAbout = true } label: {
                fixedRow(langManager.localized("settings.legal.about"), value: "v1.0.0", isWarning: false)
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
            Text(langManager.localized("settings.section.role"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "shield.fill")
                    .font(.scaled(size: 14))
                    .foregroundStyle(safe)
                VStack(alignment: .leading, spacing: 1) {
                    Text(langManager.localized("protected.settings.role.protected"))
                        .font(.scaled(size: 13, weight: .medium))
                    Text(langManager.localized("protected.settings.role.protectedDesc"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)

            Button { showRoleSwitchInfo = true } label: {
                HStack {
                    Text(langManager.localized("protected.settings.role.switchToGuardian"))
                        .font(.scaled(size: 13))
                    Spacer()
                    Text(langManager.localized("protected.settings.role.needsApproval"))
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
            Text(langManager.localized("settings.section.dev"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                Text(langManager.localized("settings.dev.switchRole")).font(.scaled(size: 13))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        coordinator.userRole = coordinator.userRole == .protected_ ? .guardian : .protected_
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: coordinator.userRole == .protected_ ? "shield.fill" : "eye.fill")
                            .font(.scaled(size: 10))
                        Text(coordinator.userRole == .protected_ ? langManager.localized("protected.settings.role.protected") : langManager.localized("guardian.settings.role.guardian"))
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
