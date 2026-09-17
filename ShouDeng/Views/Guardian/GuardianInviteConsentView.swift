import SwiftUI

// MARK: - Screen B5: Invite & Consent
//
// Design from shoudeng-full-design.html:
//   - Step 1: Permissions you're requesting (toggles)
//   - Step 2: Preview message the protected person will see
//   - Step 3: Waiting for confirmation with status
//   - "Resend invite" button
//
// This screen is critical for App Store review — proves bilateral consent.

struct GuardianInviteConsentView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)

    @State private var requestLocation = true
    @State private var requestBattery = true
    @State private var requestHealth = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                VStack(spacing: 2) {
                    Text("邀请弟弟加入")
                        .font(.system(size: 20, weight: .bold))
                    Text("他确认后关系才成立")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Step 1: Permissions
                step1Panel

                // Step 2: Preview message
                step2Panel

                // Step 3: Waiting
                step3Panel

                // Resend button
                Button {
                    Task {
                        let _: EmptyResponse = try await coordinator.apiClient.post(
                            "/v1/guardian/resend-invite",
                            body: EmptyBody()
                        )
                    }
                } label: {
                    Text("重新发送邀请")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(ink.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding(.top, 4)

                Text("这一屏是过审的关键证据：应用商店要求证明守护类功能获得了双方明确同意。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .background(Color(.systemBackground))
        .navigationTitle("邀请与授权")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Step 1: Permissions

    private var step1Panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第一步 · 你申请查看的内容")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            permissionToggle("位置", isOn: $requestLocation)
            permissionToggle("电量与在线状态", isOn: $requestBattery)
            permissionToggle("健康数据", isOn: $requestHealth)
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

    // MARK: - Step 2: Preview Message

    private var step2Panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第二步 · 他会看到这段话")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("妈妈想在你遇到危险时能帮到你。她将能看到你的位置和电量，看不到你的聊天、相册或任何应用内容。你随时可以关闭，也可以随时移除她。")
                .font(.system(size: 12.5))
                .foregroundStyle(ink.opacity(0.78))
                .lineSpacing(4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Step 3: Waiting

    private var step3Panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第三步 · 等待他确认")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            waitingRow("邀请状态", value: "等待中 · 已发送 2 分钟", isWarning: false)
            waitingRow("未确认前你能看到", value: "什么都看不到", isWarning: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func waitingRow(_ label: String, value: String, isWarning: Bool) -> some View {
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
