import SwiftUI

// MARK: - Signup View
//
// Phone + verification code + name + role selection.
// Role determines which portal (Protected/Guardian) the user enters.

struct SignupView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    @State private var phone = ""
    @State private var code = ""
    @State private var displayName = ""
    @State private var selectedRole: UserRole = .protected_
    @State private var step: Step = .phone
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var countdown = 0
    @State private var countdownTimer: Timer?

    enum Step {
        case phone
        case code
        case profile
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                stepContent

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.top, 8)
                }

                // Action button
                Button {
                    Task { await handleAction() }
                } label: {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text(buttonTitle)
                        }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(buttonDisabled ? ink.opacity(0.3) : ink)
                    )
                }
                .disabled(buttonDisabled)
                .padding(.horizontal, 32)
                .padding(.top, 20)

                Spacer()
                Spacer()
            }
            .background(Color(.systemBackground))
            .navigationTitle("注册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("返回") { dismiss() }
                }
            }
            .onDisappear {
                countdownTimer?.invalidate()
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .phone:
            VStack(spacing: 16) {
                Text("输入手机号码")
                    .font(.system(size: 20, weight: .bold))
                HStack {
                    Text("+86")
                        .font(.system(size: 15))
                        .foregroundStyle(ink)
                        .frame(width: 44)
                    TextField("手机号码", text: $phone)
                        .font(.system(size: 15))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                )
            }
            .padding(.horizontal, 32)

        case .code:
            VStack(spacing: 16) {
                Text("输入验证码")
                    .font(.system(size: 20, weight: .bold))
                Text("已发送至 \(phone)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("验证码", text: $code)
                    .font(.system(size: 15))
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 32)

        case .profile:
            VStack(spacing: 16) {
                Text("完善资料")
                    .font(.system(size: 20, weight: .bold))
                TextField("你的称呼", text: $displayName)
                    .font(.system(size: 15))
                    .textContentType(.name)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text("你的角色")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    roleOption(.protected_, icon: "shield.fill", title: "被守护者", desc: "家人会收到你的安全信号")
                    roleOption(.guardian, icon: "eye.fill", title: "守护者", desc: "你将关注家人的安全状态")
                }
            }
            .padding(.horizontal, 32)
        }
    }

    private func roleOption(_ role: UserRole, icon: String, title: String, desc: String) -> some View {
        Button {
            selectedRole = role
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(selectedRole == role ? lamp : ink.opacity(0.4))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ink)
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selectedRole == role ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedRole == role ? safe : Color(.separator))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedRole == role ? safe.opacity(0.5) : Color(.separator).opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var buttonTitle: String {
        switch step {
        case .phone: return countdown > 0 ? "\(countdown) 秒后重发" : "获取验证码"
        case .code:  return "下一步"
        case .profile: return "完成注册"
        }
    }

    private var buttonDisabled: Bool {
        if isLoading { return true }
        switch step {
        case .phone: return phone.count < 8 || countdown > 0
        case .code: return code.count < 4
        case .profile: return displayName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func handleAction() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            switch step {
            case .phone:
                try await coordinator.authManager.requestCode(phone: phone)
                step = .code
                startCountdown()
            case .code:
                step = .profile
            case .profile:
                try await coordinator.authManager.signup(
                    phone: phone,
                    code: code,
                    displayName: displayName,
                    role: selectedRole.rawValue
                )
                coordinator.userRole = selectedRole
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startCountdown() {
        countdown = 60
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if countdown > 0 { countdown -= 1 }
            else { countdownTimer?.invalidate() }
        }
    }
}
