import SwiftUI

// MARK: - Screen A3: Guardian Detail / Permissions
//
// Design from shoudeng-full-design.html:
//   - Guardian avatar + name + since date
//   - "Daily visible" toggles: location, battery, health, phone activity
//   - "Auto-enabled in emergency" section
//   - "Safe revocation" section: 6-hour delay, remove guardian

struct ProtectedGuardianDetailView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var langManager = LanguageManager.shared
    let guardianId: String

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var shareLocation = true
    @State private var shareBattery = true
    @State private var shareHealth = false
    @State private var sharePhoneActivity = false
    @State private var shareEmergencyAudio = true
    @State private var locationDisclosureTrigger = false
    @State private var audioDisclosureTrigger = false
    @State private var showRemoveConfirm = false
    @State private var isRemoving = false
    @State private var isSavingPermissions = false
    @State private var permissionSaveError: String?

    private var guardian: Guardian? {
        coordinator.myGuardians.first { $0.id == guardianId }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let g = guardian {
                    // Guardian card
                    guardianHeader(g)

                    // Daily visible
                    dailyVisiblePanel

                    // Emergency auto-enable
                    emergencyPanel

                    // Safe revocation
                    revocationPanel

                    Text(langManager.localized("guardian.detail.delayExplanation"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                } else {
                    ContentUnavailableView(
                        langManager.localized("guardian.detail.notFound"),
                        systemImage: "person.slash",
                        description: Text(langManager.localized("guardian.detail.notFoundDesc"))
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle(langManager.localized("guardian.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .featureDisclosure(.location, trigger: $locationDisclosureTrigger)
        .featureDisclosure(.emergencyAudio, trigger: $audioDisclosureTrigger)
        .onAppear {
            loadPermissions()
            locationDisclosureTrigger = true
        }
        .onChange(of: shareEmergencyAudio) { _, newValue in
            if newValue {
                audioDisclosureTrigger = true
            }
        }
        .alert(langManager.localized("guardian.detail.removeTitle"), isPresented: $showRemoveConfirm) {
            Button(langManager.localized("guardian.detail.cancel"), role: .cancel) {}
            Button(langManager.localized("guardian.detail.confirmRemove"), role: .destructive) {
                Task { await removeGuardian() }
            }
        } message: {
            if let g = guardian {
                Text(String(format: langManager.localized("guardian.detail.removeMessage"), g.user.displayName))
            }
        }
    }

    // MARK: - Load Permissions from Guardian

    private func loadPermissions() {
        guard let g = guardian else { return }
        shareLocation = g.permissions.canSeeLocation
        shareBattery = g.permissions.canSeeBattery
        shareHealth = g.permissions.canSeeHealth
        sharePhoneActivity = g.permissions.canSeePhoneActivity
        shareEmergencyAudio = g.permissions.canHearEmergencyAudio
    }

    // MARK: - Save Permissions

    private func savePermissions() {
        let permissions = GuardianPermissions(
            canSeeLocation: shareLocation,
            canSeeBattery: shareBattery,
            canSeeHealth: shareHealth,
            canSeePhoneActivity: sharePhoneActivity,
            canHearEmergencyAudio: shareEmergencyAudio
        )
        isSavingPermissions = true
        permissionSaveError = nil
        Task {
            do {
                try await coordinator.updateGuardianPermissions(
                    guardianId: guardianId,
                    permissions: permissions
                )
                // Update local state
                if let idx = coordinator.myGuardians.firstIndex(where: { $0.id == guardianId }) {
                    await MainActor.run {
                        coordinator.myGuardians[idx].permissions = permissions
                        coordinator.localStore.saveGuardians(coordinator.myGuardians)
                    }
                }
            } catch {
                await MainActor.run {
                    permissionSaveError = error.localizedDescription
                }
            }
            await MainActor.run {
                isSavingPermissions = false
            }
        }
    }

    // MARK: - Remove Guardian

    private func removeGuardian() async {
        isRemoving = true
        do {
            try await coordinator.removeGuardian(guardianId: guardianId)
        } catch {
            #if DEBUG
            print("[GuardianDetail] Remove failed: \(error)")
            #endif
        }
        isRemoving = false
    }

    // MARK: - Guardian Header

    private func guardianHeader(_ g: Guardian) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 40)
                Text(g.user.avatarInitial)
                    .font(.scaled(size: 14, weight: .medium))
                    .foregroundStyle(ink)
                if g.isOnDuty {
                    Circle()
                        .stroke(safe, lineWidth: 2)
                        .frame(width: 46, height: 46)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(g.user.displayName)
                        .font(.scaled(size: 15, weight: .medium))
                    if g.isOnDuty {
                        Text(langManager.localized("guardian.detail.onDuty"))
                            .font(.scaled(size: 11))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(safe.opacity(0.14))
                            .foregroundStyle(safe)
                            .clipShape(Capsule())
                    }
                }
                Text(String(format: langManager.localized("guardian.detail.since"), g.user.cityName, linkedSinceText(g.linkedSince)))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func linkedSinceText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = langManager.localized("guardian.detail.dateFormat")
        return formatter.string(from: date)
    }

    // MARK: - Daily Visible Panel

    private var dailyVisiblePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(langManager.localized("guardian.detail.dailyVisible"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if isSavingPermissions {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                if let error = permissionSaveError {
                    Text(error)
                        .font(.scaled(size: 12))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            permissionToggle(langManager.localized("guardian.detail.myLocation"), isOn: $shareLocation)
            permissionToggle(langManager.localized("guardian.detail.batteryStatus"), isOn: $shareBattery)
            permissionToggle(langManager.localized("guardian.detail.healthFall"), isOn: $shareHealth)
            permissionToggle(langManager.localized("guardian.detail.phoneActivity"), isOn: $sharePhoneActivity)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func permissionToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.scaled(size: 13))
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn.wrappedValue },
                set: { newValue in
                    isOn.wrappedValue = newValue
                    savePermissions()
                }
            ))
                .labelsHidden()
                .tint(safe)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Emergency Panel

    private var emergencyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("guardian.detail.emergencyAuto"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            fixedRow(langManager.localized("guardian.detail.highFreqLocation"), value: langManager.localized("guardian.detail.alwaysOn"), isOk: true)
            HStack {
                Text(langManager.localized("guardian.detail.ambientAudio")).font(.scaled(size: 13))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { shareEmergencyAudio },
                    set: { newValue in
                        shareEmergencyAudio = newValue
                        savePermissions()
                    }
                ))
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

    // MARK: - Revocation Panel

    private var revocationPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("guardian.detail.safeRevocation"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
            fixedRow(langManager.localized("guardian.detail.shareDelay"), value: langManager.localized("guardian.detail.sixHoursLater"), isOk: false)

            Button {
                showRemoveConfirm = true
            } label: {
                HStack {
                    Text(langManager.localized("guardian.detail.removeGuardian")).font(.scaled(size: 13))
                    Spacer()
                    if isRemoving {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text(langManager.localized("guardian.detail.requireConfirm"))
                            .font(.scaled(size: 11.5))
                            .foregroundStyle(alert)
                    }
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

    private func fixedRow(_ label: String, value: String, isOk: Bool = false, isWarning: Bool = false) -> some View {
        HStack {
            Text(label).font(.scaled(size: 13))
            Spacer()
            Text(value)
                .font(.scaled(size: 11.5))
                .foregroundStyle(isWarning ? alert : isOk ? safe : .secondary)
        }
        .padding(.vertical, 2)
    }
}
