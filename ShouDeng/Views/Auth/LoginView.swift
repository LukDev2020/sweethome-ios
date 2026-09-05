import SwiftUI

// MARK: - Login View
//
// Phone + verification code login flow.
// Matches the app's design system (ink, safe, lamp colors).

struct LoginView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var countdown = 0
    @State private var countdownTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo area
            VStack(spacing: 8) {
                Image(systemName: "light.beacon.max")
                    .font(.system(size: 44))
                    .foregroundStyle(lamp)
                Text("守灯")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(ink)
                Text("在紧急时刻更快联系上你的家人")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)

            // Phone input
            VStack(spacing: 12) {
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

                if codeSent {
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
            }
            .padding(.horizontal, 32)

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
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(codeSent ? "登录" : (countdown > 0 ? "\(countdown) 秒后重发" : "获取验证码"))
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

            // Switch to signup
            Button {
                coordinator.showSignup = true
            } label: {
                Text("还没有账号？注册")
                    .font(.system(size: 13))
                    .foregroundStyle(ink.opacity(0.6))
            }
            .padding(.top, 12)

            Spacer()
            Spacer()
        }
        .background(Color(.systemBackground))
        .onDisappear {
            countdownTimer?.invalidate()
        }
    }

    private var buttonDisabled: Bool {
        if isLoading { return true }
        if codeSent { return code.count < 4 }
        return phone.count < 8 || countdown > 0
    }

    private func handleAction() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            if codeSent {
                try await coordinator.authManager.login(phone: phone, code: code)
            } else {
                try await coordinator.authManager.requestCode(phone: phone)
                codeSent = true
                startCountdown()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startCountdown() {
        countdown = 60
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if countdown > 0 {
                countdown -= 1
            } else {
                countdownTimer?.invalidate()
            }
        }
    }
}
