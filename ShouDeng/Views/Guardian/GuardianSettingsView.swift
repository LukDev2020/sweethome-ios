import SwiftUI

// MARK: - Guardian Settings View
//
// Settings for the guardian portal: profile, language, notifications,
// data, legal, logout, and account deletion.

struct GuardianSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @ObservedObject private var fontScaleManager = FontScaleManager.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

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
    @State private var showOrgDashboard = false
    @State private var showInsuranceReport = false
    @State private var showDuressCode = false
    @State private var showBLETracker = false

    @AppStorage("app_dark_mode") private var darkModeEnabled = false
    @AppStorage("notif_sos_alerts") private var notifSOS = true
    @AppStorage("notif_checkin_overdue") private var notifCheckinOverdue = true
    @AppStorage("notif_family_feed") private var notifFamilyFeed = true
    @AppStorage("lockscreen_card_enabled") private var lockscreenCardEnabled = true

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
                    await coordinator.fetchProtectedPersons()
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
                Button(langManager.localized("settings.action.confirm"), role: .destructive) {
                    Task {
                        do {
                            try await coordinator.switchRole(to: .protected_)
                        } catch {
                            #if DEBUG
                            print("[Settings] Role switch failed: \(error)")
                            #endif
                        }
                    }
                }
                Button(langManager.localized("settings.action.cancel"), role: .cancel) {}
            } message: {
                Text(langManager.localized("guardian.settings.alert.roleSwitch.message"))
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
            .sheet(isPresented: $showOrgDashboard) {
                OrgDashboardView().environmentObject(coordinator)
            }
            .sheet(isPresented: $showInsuranceReport) {
                ClaimMaterialsView().environmentObject(coordinator)
            }
            .sheet(isPresented: $showDuressCode) {
                DuressCodeSettingsView().environmentObject(coordinator)
            }
            .sheet(isPresented: $showBLETracker) {
                BLETrackerSettingsView().environmentObject(coordinator)
            }
            .onChange(of: notifSOS) { coordinator.syncNotificationPrefs() }
            .onChange(of: notifCheckinOverdue) { coordinator.syncNotificationPrefs() }
            .onChange(of: notifFamilyFeed) { coordinator.syncNotificationPrefs() }
        }
    }

    // MARK: - Layout Variants

    private var settingsCompact: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(langManager.localized("guardian.settings.section.preferences"))
                    .font(.scaled(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                profilePanel
                emailMissingBanner
                rolePanel
                subscriptionPanel
                safetyToolsPanel
                organizationPanel
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
                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
    }

    private var settingsDuoPane: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    Text(langManager.localized("settings.section.account"))
                        .font(.scaled(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    profilePanel
                    emailMissingBanner
                    rolePanel
                    subscriptionPanel
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
                    organizationPanel
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

    // MARK: - Subscription Panel

    private var subscriptionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("guardian.settings.section.subscription"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            if let status = coordinator.storeKitManager.subscriptionStatus, status.isActive {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(safe)
                        .font(.scaled(size: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(coordinator.storeKitManager.planDisplayName(for: status.planId))
                            .font(.scaled(size: 13, weight: .medium))
                        if let expires = status.expiresDate {
                            Text(String(format: langManager.localized("guardian.settings.subscription.expiresAt"), expires.formatted(.dateTime.year().month().day())))
                                .font(.scaled(size: 12))
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
                        .font(.scaled(size: 14))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(langManager.localized("guardian.settings.subscription.free"))
                            .font(.scaled(size: 13, weight: .medium))
                        Text(langManager.localized("guardian.settings.subscription.upgradeHint"))
                            .font(.scaled(size: 12))
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
                         ? langManager.localized("guardian.settings.subscription.manage") : langManager.localized("guardian.settings.subscription.viewPlans"))
                        .font(.scaled(size: 13))
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
        .task {
            await coordinator.storeKitManager.refreshSubscriptionStatus()
        }
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

            HStack(spacing: 6) {
                Image(systemName: "lock.display")
                    .font(.scaled(size: 11))
                    .foregroundStyle(.orange)
                Text(langManager.localized("guardian.settings.safetyTools.lockscreenHint"))
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
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Organization Panel

    private var organizationPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("guardian.settings.section.organization"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)

            Button { showOrgDashboard = true } label: {
                fixedRow(langManager.localized("guardian.settings.org.complianceDashboard"), value: langManager.localized("settings.action.view"), isWarning: false)
            }
            .buttonStyle(.plain)

            Button { showInsuranceReport = true } label: {
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
            toggleRow(langManager.localized("guardian.settings.notification.checkInOverdue"), isOn: $notifCheckinOverdue)
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
                Image(systemName: "eye.fill")
                    .font(.scaled(size: 14))
                    .foregroundStyle(pro)
                VStack(alignment: .leading, spacing: 1) {
                    Text(langManager.localized("guardian.settings.role.guardian"))
                        .font(.scaled(size: 13, weight: .medium))
                    Text(langManager.localized("guardian.settings.role.guardianDesc"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)

            Button { showRoleSwitchInfo = true } label: {
                HStack {
                    Text(langManager.localized("guardian.settings.role.switchToProtected"))
                        .font(.scaled(size: 13))
                    Spacer()
                    Text(langManager.localized("guardian.settings.role.needsConfirm"))
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

    // MARK: - Helpers

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
                .font(.scaled(size: 12))
                .foregroundStyle(isWarning ? alert : .secondary)
        }
        .padding(.vertical, 2)
    }
}
