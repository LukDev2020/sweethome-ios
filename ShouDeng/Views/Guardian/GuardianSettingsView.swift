import SwiftUI
import ActivityKit

// MARK: - Guardian Settings View
//
// Profile and plan, display and language, the lock screen card; then notifications,
// family and role, safety tools, organization, account and security, data and
// privacy, about; log out and delete last. Building blocks: Views/Shared/SettingsKit.swift.

struct GuardianSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let ink = Color.appInk
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

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
    @State private var showOrgDashboard = false
    @State private var showInsuranceReport = false
    @State private var showDuressCode = false
    @State private var showBLETracker = false
    @State private var showLogoutConfirm = false

    @AppStorage(AppCoordinator.sosCriticalAlertsKey) private var notifSOSCritical = true
    @AppStorage("notif_checkin_overdue") private var notifCheckinOverdue = true
    /// "Mom is home safe" pushes (the server reads it as checkinReminder)
    @AppStorage("notif_checkin_reminder") private var notifHomeSafe = true

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
                            try await coordinator.switchRole(to: .protected_)
                        } catch {
                            // Offline or a server error: say so instead of doing nothing
                            showDeleteError = true
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
            .onChange(of: notifSOSCritical) { coordinator.setSOSCriticalAlerts(enabled: notifSOSCritical) }
            .onChange(of: notifCheckinOverdue) { coordinator.syncNotificationPrefs() }
            .onChange(of: notifHomeSafe) { coordinator.syncNotificationPrefs() }
            .logoutConfirmation(isPresented: $showLogoutConfirm, isProtected: false) {
                coordinator.authManager.logout()
            }
        }
    }

    // MARK: - Layout
    //
    // Top to bottom: who I am and my plan, display and language, the lock screen card;
    // then notifications, family and role, safety tools, organization, account and
    // security, data and privacy, about. On iPhone Duo the first part is the left pane.

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
                    .padding(.bottom, 96) // clear of the floating SOS button
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
            SettingsDisplaySection(tint: pro)
            SettingsSection(langManager.localized("settings.section.featured")) {
                LockScreenCardFeature()
            }
        }
    }

    /// One group per job
    private var groups: some View {
        VStack(alignment: .leading, spacing: 20) {
            notificationSection
            familySection
            WatchBackPanel(framed: false)
            toolsSection
            organizationSection
            accountSection
            dataSection
            aboutSection
            VStack(spacing: 10) {
                SettingsDestructiveButton(title: langManager.localized("settings.logout")) { showLogoutConfirm = true }
                    .settingsCard()
                SettingsDestructiveButton(title: langManager.localized("settings.delete.account")) { showDeleteConfirm = true }
                    .settingsCard()
            }
            #if DEBUG
            devPanel
            #endif
            #if BETA
            BetaDeveloperPanel()
            #endif
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

    // MARK: - Notifications

    private var notificationSection: some View {
        SettingsSection(langManager.localized("settings.section.notifications")) {
            SOSNotificationRows()
                .padding(.vertical, 8)
            if PushService.criticalAlertsEntitled {
                SettingsDivider()
                SettingsToggleRow(icon: "exclamationmark.triangle.fill", tint: SettingsTint.sos,
                                  title: langManager.localized("settings.notification.sosCritical"),
                                  subtitle: langManager.localized("settings.notification.sosCritical.footnote"),
                                  isOn: $notifSOSCritical)
            }
            SettingsDivider()
            SettingsToggleRow(icon: "clock.badge.exclamationmark.fill", tint: SettingsTint.amber,
                              title: langManager.localized("guardian.settings.notification.checkInOverdue"),
                              isOn: $notifCheckinOverdue)
            SettingsDivider()
            SettingsToggleRow(icon: "house.fill", tint: SettingsTint.safe,
                              title: langManager.localized("guardian.settings.notification.homeSafe"),
                              isOn: $notifHomeSafe)
        }
    }

    // MARK: - Family and role

    private var familySection: some View {
        SettingsSection(langManager.localized("settings.section.familyRole")) {
            SettingsRow(icon: "eye.fill", tint: SettingsTint.pro,
                        title: langManager.localized("guardian.settings.role.guardian"),
                        subtitle: langManager.localized("guardian.settings.role.guardianDesc"),
                        chevron: false)
            SettingsDivider()
            // Join family: enter an invite code (any role; the invite decides the direction)
            Button { coordinator.presentInviteAccept() } label: {
                SettingsRow(icon: "key.fill", tint: SettingsTint.pro,
                            title: langManager.localized("settings.joinFamily"),
                            subtitle: langManager.localized("settings.joinFamily.desc"))
            }
            .buttonStyle(.settingsRow)
            .accessibilityIdentifier("settings.joinFamily")
            SettingsDivider()
            // Looked after and looking after family: the home's side switch
            BothRolesSettingsRow()

            // Switching roles silently turns off protection for this person, so it is
            // DEBUG-only until roles phase B (docs/roles/ROLES.md: dual roles + view switcher).
            #if DEBUG
            SettingsDivider()
            Button { showRoleSwitchInfo = true } label: {
                SettingsRow(icon: "arrow.triangle.2.circlepath", tint: SettingsTint.gray,
                            title: langManager.localized("guardian.settings.role.switchToProtected"),
                            value: langManager.localized("guardian.settings.role.needsConfirm"))
            }
            .buttonStyle(.settingsRow)
            #endif
        }
    }

    // MARK: - Safety tools

    private var toolsSection: some View {
        SettingsSection(langManager.localized("settings.section.safetyTools")) {
            Button { showMedicalCard = true } label: {
                SettingsRow(icon: "cross.case.fill", tint: SettingsTint.blue,
                            title: langManager.localized("settings.safetyTools.medicalCard"),
                            subtitle: langManager.localized("guardian.settings.safetyTools.lockscreenHint"),
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
            Button { showBLETracker = true } label: {
                let count = BLETrackerService.shared.pairedTags.count
                SettingsRow(icon: "antenna.radiowaves.left.and.right", tint: SettingsTint.blue,
                            title: langManager.localized("settings.security.bleTracker"),
                            subtitle: langManager.localized("settings.security.bleTrackerDesc"),
                            value: String(format: langManager.localized("settings.security.deviceCount"), count),
                            valueColor: count == 0 ? .secondary : safe)
            }
            .buttonStyle(.settingsRow)
        }
    }

    // MARK: - Organization

    private var organizationSection: some View {
        SettingsSection(langManager.localized("guardian.settings.section.organization")) {
            Button { showOrgDashboard = true } label: {
                SettingsRow(icon: "building.2.fill", tint: SettingsTint.gray,
                            title: langManager.localized("guardian.settings.org.complianceDashboard"))
            }
            .buttonStyle(.settingsRow)
            SettingsDivider()
            Button { showInsuranceReport = true } label: {
                SettingsRow(icon: "doc.text.fill", tint: SettingsTint.gray,
                            title: langManager.localized("settings.safetyTools.claimMaterials"))
            }
            .buttonStyle(.settingsRow)
        }
    }

    // MARK: - Account and security

    private var accountSection: some View {
        SettingsSection(langManager.localized("settings.section.accountSecurity")) {
            // Phone, Apple, Alipay: the ways into this account
            SignInMethodsRow(tint: SettingsTint.gray)
            SettingsDivider()
            if BiometricAuthManager.shared.isAvailable {
                SettingsToggleRow(icon: BiometricAuthManager.shared.biometricIconName, tint: SettingsTint.gray,
                                  title: String(format: langManager.localized("settings.security.biometricLogin"),
                                                BiometricAuthManager.shared.biometricName),
                                  isOn: Binding(
                                      get: { BiometricAuthManager.shared.isEnabled },
                                      set: { newValue in
                                          if newValue {
                                              try? BiometricAuthManager.shared.enable()
                                          } else {
                                              BiometricAuthManager.shared.disable()
                                          }
                                      }
                                  ))
            } else {
                SettingsRow(icon: "lock.fill", tint: SettingsTint.gray,
                            title: langManager.localized("settings.security.biometricUnavailable"),
                            chevron: false, titleColor: .secondary)
            }
        }
    }

    // MARK: - Data and privacy

    private var dataSection: some View {
        SettingsSection(langManager.localized("settings.section.dataPrivacy")) {
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
            TutorialHelpButton(role: .guardian, style: .row)
            SettingsDivider()
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

}

// MARK: - Row button style

/// Plain look, but the whole row is tappable — including the Spacer between the
/// title and the chevron. A contentShape on the Button/NavigationLink itself does
/// not reach a NavigationLink's label; here it is applied to the label.
struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == SettingsRowButtonStyle {
    static var settingsRow: SettingsRowButtonStyle { SettingsRowButtonStyle() }
}
