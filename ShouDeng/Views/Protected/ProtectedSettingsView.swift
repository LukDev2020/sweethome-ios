import SwiftUI
import ActivityKit

// MARK: - Settings (person looked after)
//
// Profile and plan, display and language, featured (lock screen card, disguise mode,
// fake call), home style; then SOS, automatic protection, check-in, tools, family and
// role, account and security, data and privacy, about; log out and delete last.
// Building blocks: Views/Shared/SettingsKit.swift.

struct ProtectedSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let ink = Color.appInk
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @AppStorage("distress_detection_enabled") private var distressDetectionEnabled = false
    @AppStorage("voice_command_enabled") private var voiceCommandEnabled = false
    /// Read so the fall-profile switch redraws (the value itself is the coordinator's)
    @AppStorage(AppCoordinator.sensitiveFallKey) private var sensitiveFallStored = false
    @AppStorage(HomeStyle.storageKey) private var homeStyleStored = HomeStyle.defaultStyle.rawValue

    private let pro = Color(red: 107/255, green: 92/255, blue: 165/255)
    private let paneBorder = Color(red: 1/255, green: 69/255, blue: 129/255).opacity(0.13)

    @State private var showProfileEdit = false
    @State private var showPrivacy = false
    @State private var showAbout = false
    @State private var showDeleteConfirm = false
    @State private var showExportAlert = false
    @State private var showRoleSwitchInfo = false
    @State private var showDeleteError = false
    @State private var showExportSent = false
    @State private var exportFile: ExportFile?
    @State private var showMedicalCard = false
    @State private var showEmergencyText = false
    @State private var showConsulate = false
    @State private var showClaimMaterials = false
    @State private var showDuressCode = false
    @State private var showSilentAlarm = false
    @State private var showBLETracker = false
    @State private var showFakeCall = false
    @State private var showDeadManSwitch = false
    @State private var showTrackerDetection = false
    @State private var showDisguiseMode = false
    @State private var showLogoutConfirm = false

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
                PrivacyPolicyView().environmentObject(coordinator)
            }
            .sheet(isPresented: $showAbout) {
                AboutView().environmentObject(coordinator)
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
            .sheet(item: $exportFile) { file in
                ShareSheet(items: [file.url])
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
                Button(langManager.localized("settings.action.confirm"), role: .destructive) {
                    Task {
                        do {
                            try await coordinator.switchRole(to: .guardian)
                        } catch {
                            // Offline or a server error: say so instead of doing nothing
                            showDeleteError = true
                        }
                    }
                }
                Button(langManager.localized("settings.action.cancel"), role: .cancel) {}
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
            .sheet(isPresented: $showFakeCall) {
                FakeCallSettingsView().environmentObject(coordinator)
            }
            .sheet(isPresented: $showDeadManSwitch) {
                DeadManSwitchView().environmentObject(coordinator)
            }
            .sheet(isPresented: $showTrackerDetection) {
                TrackerDetectionView().environmentObject(coordinator)
            }
            .sheet(isPresented: $showDisguiseMode) {
                DisguiseModeSettingsView().environmentObject(coordinator)
            }
            .logoutConfirmation(isPresented: $showLogoutConfirm, isProtected: true) {
                coordinator.authManager.logout()
            }
        }
    }

    // MARK: - Layout
    //
    // Top to bottom: who I am and my plan, display and language, what ShouDeng is known
    // for (lock screen card, home style), then one group per job. On iPhone Duo the
    // first part is the left pane and the groups the right.

    private var settingsCompact: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identityAndLook
                groups
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 96) // clear of the floating SOS button
        }
        .background(Color(.systemGroupedBackground))
    }

    private var settingsDuoPane: some View {
        FoldSplitView(dividerColor: paneBorder) {
            ScrollView {
                identityAndLook
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
        } trailing: {
            ScrollView {
                groups
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 96)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    /// Profile, plan, display and language, featured
    private var identityAndLook: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 10) {
                SettingsProfileHeader { showProfileEdit = true }
                emailMissingBanner
                PhoneMissingBanner()
                SettingsPlanCard()
            }
            SettingsDisplaySection(tint: safe)
            featuredSection
            SettingsSection(langManager.localized("homeStyle.section")) {
                HomeStylePanel()
            }
        }
    }

    /// One group per job
    private var groups: some View {
        VStack(alignment: .leading, spacing: 20) {
            sosSection
            autoProtectSection
            SettingsSection(langManager.localized("protected.settings.section.checkIn"),
                            footer: langManager.localized("protected.settings.checkIn.overdueHint")) {
                CheckInSettingsPanel()
            }
            toolsSection
            familySection
            WatchBackPanel(framed: false)
            accountSection
            dataSection
            aboutSection
            leaveSection
            #if DEBUG
            devPanel
            #endif
            #if BETA
            BetaDeveloperPanel()
            #endif
            Text(langManager.localized("protected.settings.sos.redundancyHint"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
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
            .buttonStyle(.settingsRow)
        }
    }

    // MARK: - Featured

    private var featuredSection: some View {
        SettingsSection(langManager.localized("settings.section.featured")) {
            LockScreenCardFeature()
            SettingsDivider()
            Button { showDisguiseMode = true } label: {
                SettingsRow(icon: "theatermasks.fill", tint: SettingsTint.pro,
                            title: langManager.localized("settings.safetyTools.disguiseMode"),
                            subtitle: langManager.localized("settings.featured.disguise.desc"))
            }
            .buttonStyle(.settingsRow)
            SettingsDivider()
            Button { showFakeCall = true } label: {
                SettingsRow(icon: "phone.arrow.down.left.fill", tint: SettingsTint.pro,
                            title: langManager.localized("settings.safetyTools.fakeCall"),
                            subtitle: langManager.localized("settings.featured.fakeCall.desc"))
            }
            .buttonStyle(.settingsRow)
        }
    }

    // MARK: - SOS

    private var sosSection: some View {
        SettingsSection(langManager.localized("protected.settings.section.sosTrigger")) {
            // Always on (no switch): turning SOS off is never what someone means to do
            SettingsRow(icon: "hand.tap.fill", tint: SettingsTint.sos,
                        title: langManager.localized("protected.settings.sos.longPress"),
                        value: langManager.localized("settings.notification.sos.alwaysOn"), chevron: false)
            SettingsDivider()
            SettingsRow(icon: "square.grid.2x2.fill", tint: SettingsTint.sos,
                        title: langManager.localized("protected.settings.sos.widget"),
                        value: langManager.localized("settings.notification.sos.alwaysOn"), chevron: false)
            SettingsDivider()
            Button { showBLETracker = true } label: {
                let paired = BLETrackerService.shared.pairedTags.count
                SettingsRow(icon: "antenna.radiowaves.left.and.right", tint: SettingsTint.sos,
                            title: langManager.localized("protected.settings.sos.bluetooth"),
                            subtitle: langManager.localized("settings.security.bleTrackerDesc"),
                            value: paired > 0
                                ? String(format: langManager.localized("settings.security.deviceCount"), paired)
                                : langManager.localized("protected.settings.sos.pairButton"),
                            valueColor: paired > 0 ? safe : .secondary)
            }
            .buttonStyle(.settingsRow)
            SettingsDivider()
            Button { showDuressCode = true } label: {
                let set = KeychainHelper.shared.read(.duressCode) != nil
                SettingsRow(icon: "exclamationmark.shield.fill", tint: SettingsTint.sos,
                            title: langManager.localized("settings.security.duressCode"),
                            subtitle: langManager.localized("settings.security.duressCodeDesc"),
                            value: langManager.localized(set ? "settings.status.configured" : "settings.status.notConfigured"),
                            valueColor: set ? safe : .secondary)
            }
            .buttonStyle(.settingsRow)
            SettingsDivider()
            Button { showSilentAlarm = true } label: {
                let on = SilentAlarmService.shared.isEnabled
                SettingsRow(icon: "bell.slash.fill", tint: SettingsTint.sos,
                            title: langManager.localized("protected.settings.security.silentAlarm"),
                            subtitle: langManager.localized("protected.settings.security.silentAlarmDesc"),
                            value: langManager.localized(on ? "settings.status.enabled" : "settings.status.disabled"),
                            valueColor: on ? safe : .secondary)
            }
            .buttonStyle(.settingsRow)
            SettingsDivider()
            // The daily check-in reminder lives in the check-in group
            SOSNotificationRows()
                .padding(.vertical, 8)
        }
    }

    // MARK: - Automatic protection

    private var autoProtectSection: some View {
        SettingsSection(langManager.localized("protected.settings.section.smartDetection")) {
            // Fall detection: always on while the app is open (no switch), and testable
            VStack(alignment: .leading, spacing: 6) {
                SettingsRow(icon: "figure.fall", tint: SettingsTint.amber,
                            title: langManager.localized("protected.settings.detection.fall"),
                            subtitle: langManager.localized("protected.settings.detection.fallDesc"),
                            chevron: false)
                Label(langManager.localized("protected.settings.detection.fallOn"), systemImage: "checkmark.circle.fill")
                    .font(.scaled(size: 13, weight: .medium))
                    .foregroundStyle(safe)
                    .padding(.leading, 40)
                Button {
                    coordinator.testFallDetection()
                } label: {
                    Label(langManager.localized(coordinator.isDemo ? "fallTest.tryButton" : "fallTest.button"), systemImage: "play.circle")
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(SettingsTint.amber)
                }
                .padding(.leading, 40)
                .padding(.bottom, 8)
                .accessibilityIdentifier("settings.testFallDetection")
            }
            SettingsDivider()
            SettingsToggleRow(icon: "figure.walk.motion", tint: SettingsTint.amber,
                              title: langManager.localized("protected.settings.detection.fallSensitive"),
                              subtitle: langManager.localized("protected.settings.detection.fallSensitiveDesc"),
                              isOn: sensitiveFallBinding)
                .accessibilityIdentifier("settings.sensitiveFallDetection")
            SettingsDivider()
            SettingsToggleRow(icon: "waveform", tint: SettingsTint.amber,
                              title: langManager.localized("protected.settings.detection.distress"),
                              subtitle: langManager.localized("protected.settings.detection.distressDesc"),
                              isOn: $distressDetectionEnabled)
                .onChange(of: distressDetectionEnabled) { _, enabled in
                    coordinator.audioCoordinator.distressDetectionEnabled = enabled
                }
            SettingsDivider()
            SettingsToggleRow(icon: "mic.fill", tint: SettingsTint.amber,
                              title: langManager.localized("protected.settings.detection.voiceCommand"),
                              subtitle: langManager.localized("protected.settings.detection.voiceCommandDesc"),
                              isOn: $voiceCommandEnabled)
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
            SettingsDivider()
            Button { showDeadManSwitch = true } label: {
                SettingsRow(icon: "timer", tint: SettingsTint.amber,
                            title: langManager.localized("settings.safetyTools.deadManSwitch"),
                            value: langManager.localized("settings.action.start"))
            }
            .buttonStyle(.settingsRow)
        }
    }

    // MARK: - Tools

    private var toolsSection: some View {
        SettingsSection(langManager.localized("settings.section.safetyTools")) {
            Button { showMedicalCard = true } label: {
                SettingsRow(icon: "cross.case.fill", tint: SettingsTint.blue,
                            title: langManager.localized("settings.safetyTools.medicalCard"),
                            subtitle: langManager.localized("protected.settings.safetyTools.lockscreenHint"),
                            value: langManager.localized("settings.action.edit"))
            }
            .buttonStyle(.settingsRow)
            SettingsDivider()
            Button { showEmergencyText = true } label: {
                SettingsRow(icon: "text.bubble.fill", tint: SettingsTint.blue,
                            title: langManager.localized("settings.safetyTools.emergencyCard"))
            }
            .buttonStyle(.settingsRow)
            SettingsDivider()
            Button { showConsulate = true } label: {
                SettingsRow(icon: "building.columns.fill", tint: SettingsTint.blue,
                            title: langManager.localized("settings.safetyTools.consulate"))
            }
            .buttonStyle(.settingsRow)
            SettingsDivider()
            Button { showTrackerDetection = true } label: {
                SettingsRow(icon: "sensor.tag.radiowaves.forward.fill", tint: SettingsTint.blue,
                            title: langManager.localized("settings.safetyTools.trackerDetection"))
            }
            .buttonStyle(.settingsRow)
            SettingsDivider()
            Button { showClaimMaterials = true } label: {
                SettingsRow(icon: "doc.text.fill", tint: SettingsTint.blue,
                            title: langManager.localized("settings.safetyTools.claimMaterials"))
            }
            .buttonStyle(.settingsRow)
        }
    }

    // MARK: - Family and role

    private var familySection: some View {
        SettingsSection(langManager.localized("settings.section.familyRole")) {
            SettingsRow(icon: "shield.fill", tint: SettingsTint.safe,
                        title: langManager.localized("protected.settings.role.protected"),
                        subtitle: langManager.localized("protected.settings.role.protectedDesc"),
                        chevron: false)
            SettingsDivider()
            // Join family: enter an invite code (any role; the invite decides the direction)
            Button { coordinator.presentInviteAccept() } label: {
                SettingsRow(icon: "key.fill", tint: SettingsTint.safe,
                            title: langManager.localized("settings.joinFamily"),
                            subtitle: langManager.localized("settings.joinFamily.desc"))
            }
            .buttonStyle(.settingsRow)
            .accessibilityIdentifier("settings.joinFamily")
            SettingsDivider()
            // Looked after and looking after family: the home's side switch
            BothRolesSettingsRow()
            WorkRoleSettingsRow()

            // Switching roles silently turns off protection for this person, so it is
            // DEBUG-only until roles phase B (docs/roles/ROLES.md: dual roles + view switcher).
            #if DEBUG
            SettingsDivider()
            Button { showRoleSwitchInfo = true } label: {
                SettingsRow(icon: "arrow.triangle.2.circlepath", tint: SettingsTint.gray,
                            title: langManager.localized("protected.settings.role.switchToGuardian"),
                            value: langManager.localized("protected.settings.role.needsApproval"))
            }
            .buttonStyle(.settingsRow)
            #endif
        }
    }

    // MARK: - Account and security

    private var accountSection: some View {
        SettingsSection(langManager.localized("settings.section.accountSecurity")) {
            // Phone, Apple, Alipay: the ways into this account
            SignInMethodsRow(tint: SettingsTint.gray)
            if BiometricAuthManager.shared.isAvailable {
                SettingsDivider()
                SettingsToggleRow(icon: BiometricAuthManager.shared.biometricIconName, tint: SettingsTint.gray,
                                  title: String(format: langManager.localized("settings.security.biometricLogin"),
                                                BiometricAuthManager.shared.biometricName),
                                  isOn: biometricBinding)
            } else {
                SettingsDivider()
                SettingsRow(icon: "lock.fill", tint: SettingsTint.gray,
                            title: langManager.localized("settings.security.biometricUnavailable"),
                            chevron: false, titleColor: .secondary)
            }
        }
    }

    // MARK: - Data and privacy

    private var dataSection: some View {
        SettingsSection(langManager.localized("settings.section.dataPrivacy")) {
            SettingsRow(icon: "clock.arrow.circlepath", tint: SettingsTint.gray,
                        title: langManager.localized("settings.data.locationRetention"),
                        value: langManager.localized("settings.data.locationRetentionValue"), chevron: false)
            SettingsDivider()
            NavigationLink {
                DataLocationView().environmentObject(coordinator)
            } label: {
                SettingsRow(icon: "externaldrive.fill", tint: SettingsTint.gray,
                            title: langManager.localized("settings.data.storageLocation"),
                            value: langManager.localized(coordinator.needsDataTransferConsent
                                                         ? "settings.data.storageLocation.pending"
                                                         : "settings.data.storageLocation.value"),
                            valueColor: coordinator.needsDataTransferConsent ? alert : .secondary)
            }
            .buttonStyle(.settingsRow)
            SettingsDivider()
            Button { showExportAlert = true } label: {
                SettingsRow(icon: "square.and.arrow.up.fill", tint: SettingsTint.gray,
                            title: langManager.localized("settings.data.exportAll"),
                            value: langManager.localized("settings.action.requestExport"))
            }
            .buttonStyle(.settingsRow)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        SettingsSection(langManager.localized("settings.section.about")) {
            TipsSettingsPanel()
            SettingsDivider()
            Button { showPrivacy = true } label: {
                SettingsRow(icon: "hand.raised.fill", tint: SettingsTint.gray,
                            title: langManager.localized("settings.legal.privacyAndTerms"))
            }
            .buttonStyle(.settingsRow)
            SettingsDivider()
            Button { showAbout = true } label: {
                SettingsRow(icon: "info.circle.fill", tint: SettingsTint.gray,
                            title: langManager.localized("settings.legal.about"),
                            value: AppVersion.display)
            }
            .buttonStyle(.settingsRow)
        }
    }

    /// Log out, and delete the account, apart from everything else
    private var leaveSection: some View {
        VStack(spacing: 10) {
            SettingsDestructiveButton(title: langManager.localized("settings.logout")) { showLogoutConfirm = true }
                .settingsCard()
            SettingsDestructiveButton(title: langManager.localized("settings.delete.account")) { showDeleteConfirm = true }
                .settingsCard()
        }
    }

    private var biometricBinding: Binding<Bool> {
        Binding(
            get: { BiometricAuthManager.shared.isEnabled },
            set: { newValue in
                if newValue {
                    try? BiometricAuthManager.shared.enable()
                } else {
                    BiometricAuthManager.shared.disable()
                }
            }
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
            coordinator.accountWasDeleted()
        } catch {
            showDeleteError = true
        }
    }

    private func requestDataExport() async {
        do {
            exportFile = ExportFile(url: try await coordinator.exportMyData())
        } catch {
            showDeleteError = true
        }
    }

    private var sensitiveFallBinding: Binding<Bool> {
        Binding(
            get: { _ = sensitiveFallStored; _ = homeStyleStored; return coordinator.sensitiveFallDetection },
            set: { coordinator.setSensitiveFallDetection($0) }
        )
    }
}
