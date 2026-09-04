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

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var shareLocation = true
    @State private var shareBattery = true
    @State private var shareHealth = true
    @State private var sharePhoneActivity = false
    @State private var shareEmergencyAudio = true
    @State private var locationDisclosureTrigger = false
    @State private var audioDisclosureTrigger = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Guardian card
                guardianHeader

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
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle("守护者详情")
        .navigationBarTitleDisplayMode(.inline)
        .featureDisclosure(.location, trigger: $locationDisclosureTrigger)
        .featureDisclosure(.emergencyAudio, trigger: $audioDisclosureTrigger)
        .onAppear {
            // Trigger location disclosure on first visit
            locationDisclosureTrigger = true
        }
        .onChange(of: shareEmergencyAudio) { _, newValue in
            if newValue {
                audioDisclosureTrigger = true
            }
        }
    }

    // MARK: - Guardian Header

    private var guardianHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 40)
                Text("妈")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ink)
                Circle()
                    .stroke(safe, lineWidth: 2)
                    .frame(width: 46, height: 46)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("妈妈")
                        .font(.system(size: 15, weight: .medium))
                    Text("值班中")
                        .font(.system(size: 9.5))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(safe.opacity(0.14))
                        .foregroundStyle(safe)
                        .clipShape(Capsule())
                }
                Text("多伦多 · 自 2024 年 3 月起")
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

    // MARK: - Daily Visible Panel

    private var dailyVisiblePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日常可见")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
            Toggle("", isOn: isOn)
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
                Toggle("", isOn: $shareEmergencyAudio)
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
            fixedRow("移除这位守护者", value: "需二次确认", isWarning: true)
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
