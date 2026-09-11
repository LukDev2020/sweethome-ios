import SwiftUI

// MARK: - Screen A6: Settings
//
// Design from shoudeng-full-design.html:
//   - SOS trigger methods (long press, watch, BT button, silent mode)
//   - Check-in schedule (reminder times, overdue threshold)
//   - Data (retention, export, account deletion)

struct ProtectedSettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var longPressEnabled = true
    @State private var watchEnabled = true
    @State private var silentMode = false
    @State private var showPrivacy = false
    @State private var showAbout = false
    @State private var showDeleteConfirm = false
    @State private var showExportAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                VStack(spacing: 2) {
                    Text("设置")
                        .font(.system(size: 20, weight: .bold))
                    Text("求助方式与隐私")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // SOS trigger methods
                sosTriggerPanel

                // Check-in schedule
                checkInPanel

                // Data
                dataPanel

                // Legal & About
                legalPanel

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

    // MARK: - Account Deletion

    private func deleteAccount() async {
        do {
            let _: EmptyResponse = try await coordinator.apiClient.post(
                "/v1/user/delete",
                body: EmptyBody()
            )
            coordinator.authManager.logout()
        } catch {
            #if DEBUG
            print("[Settings] Delete account failed: \(error)")
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
