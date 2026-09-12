import SwiftUI

// MARK: - Invite Guardian View
//
// Protected person generates an invite code, then shares it with
// a guardian via system share sheet. Guardian enters the code in
// their app to establish the link.

struct InviteGuardianView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    @State private var inviteCode: String?
    @State private var expiresAt: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 4) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(safe)
                        Text("邀请守护者")
                            .font(.system(size: 20, weight: .bold))
                        Text("生成邀请码，发送给你的家人或朋友")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    if let code = inviteCode {
                        // Show invite code
                        codeCard(code)

                        // Share button
                        ShareLink(item: shareText(code: code)) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("分享邀请码")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(safe)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Expiry note
                        if let expires = expiresAt {
                            Text("邀请码 24 小时内有效（截止 \(formatExpiry(expires))）")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        // Instructions
                        instructionsPanel
                    } else {
                        // Generate button
                        Button {
                            Task { await generateCode() }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "key.fill")
                                }
                                Text("生成邀请码")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(safe)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isLoading)

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }

                        // How it works
                        instructionsPanel
                    }
                }
                .padding(.horizontal, 16)
            }
            .background(Color(.systemBackground))
            .navigationTitle("邀请守护者")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - Code Card

    private func codeCard(_ code: String) -> some View {
        VStack(spacing: 8) {
            Text("邀请码")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(code.enumerated()), id: \.offset) { _, char in
                    Text(String(char))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(ink)
                        .frame(width: 40, height: 48)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Button {
                UIPasteboard.general.string = code
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("复制")
                }
                .font(.system(size: 12))
                .foregroundStyle(safe)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(safe.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Instructions

    private var instructionsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("如何使用")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            instructionRow("1", text: "将邀请码发送给你信任的家人或朋友")
            instructionRow("2", text: "对方在「守灯」App 中输入邀请码")
            instructionRow("3", text: "关系建立后，你可以随时调整权限或移除")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 1)
        )
    }

    private func instructionRow(_ number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(safe.opacity(0.15))
                    .frame(width: 22, height: 22)
                Text(number)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(safe)
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(ink.opacity(0.8))
        }
    }

    // MARK: - Actions

    private func generateCode() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await coordinator.createInviteCode()
            await MainActor.run {
                inviteCode = response.code
                expiresAt = response.expiresAt
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func shareText(code: String) -> String {
        let name = coordinator.currentUser?.displayName ?? "我"
        return "\(name)邀请你成为守灯守护者。请在「守灯」App 中输入邀请码：\(code)（24小时内有效）"
    }

    private func formatExpiry(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }
        let display = DateFormatter()
        display.dateFormat = "MM/dd HH:mm"
        return display.string(from: date)
    }
}
