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

                    Text("延迟生效为胁迫场景准备：被逼当场关闭时，家人仍能在六小时内看到。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                } else {
                    ContentUnavailableView(
                        "找不到守护者",
                        systemImage: "person.slash",
                        description: Text("该守护者可能已被移除")
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle("守护者详情")
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
        .alert("移除守护者", isPresented: $showRemoveConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认移除", role: .destructive) {
                Task { await removeGuardian() }
            }
        } message: {
            if let g = guardian {
                Text("确定要移除「\(g.user.displayName)」吗？移除后对方将无法查看你的状态。")
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
                    .font(.system(size: 14, weight: .medium))
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
                        .font(.system(size: 15, weight: .medium))
                    if g.isOnDuty {
                        Text("值班中")
                            .font(.system(size: 9.5))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(safe.opacity(0.14))
                            .foregroundStyle(safe)
                            .clipShape(Capsule())
                    }
                }
                Text("\(g.user.cityName) · 自 \(linkedSinceText(g.linkedSince)) 起")
                    .font(.system(size: 11))
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
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter.string(from: date)
    }

    // MARK: - Daily Visible Panel

    private var dailyVisiblePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("日常可见")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if isSavingPermissions {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                if let error = permissionSaveError {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            permissionToggle("我的位置", isOn: $shareLocation)
            permissionToggle("电量与在线状态", isOn: $shareBattery)
            permissionToggle("健康与跌倒检测", isOn: $shareHealth)
            permissionToggle("手机活跃信号", isOn: $sharePhoneActivity)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func permissionToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
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
            Text("紧急时自动开启")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            fixedRow("高频位置上报", value: "始终开启", isOk: true)
            HStack {
                Text("环境录音").font(.system(size: 13))
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
            Text("安全撤销")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            fixedRow("关闭共享延迟生效", value: "6 小时后", isOk: false)

            Button {
                showRemoveConfirm = true
            } label: {
                HStack {
                    Text("移除这位守护者").font(.system(size: 13))
                    Spacer()
                    if isRemoving {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("需二次确认")
                            .font(.system(size: 11.5))
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
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(isWarning ? alert : isOk ? safe : .secondary)
        }
        .padding(.vertical, 2)
    }
}
