import SwiftUI

// MARK: - Post-Signup Setup Wizard
//
// Shown once after first signup. Collects:
//   Step 1: Email (account recovery)
//   Step 2: City (pre-filled from country)
//   Step 3: Biometric (Face ID / Touch ID)
//   Step 4: [Guardian only] Subscription plan
//   Step 5: Invite guidance (role-specific)

struct PostSignupWizardView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var email = ""
    @State private var cityName = ""
    @State private var isLoading = false

    private let navy = Color(red: 1/255, green: 69/255, blue: 129/255)
    private let cream = Color(red: 252/255, green: 242/255, blue: 218/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    private var totalSteps: Int {
        coordinator.userRole == .guardian ? 5 : 4
    }

    private var stepTitles: [String] {
        var titles = ["邮箱", "城市", "安全登录", "邀请"]
        if coordinator.userRole == .guardian {
            titles.insert("方案", at: 3)
        }
        return titles
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            progressBar
                .padding(.top, 16)
                .padding(.bottom, 24)

            // Step content
            Group {
                switch currentStep {
                case 0: emailStep
                case 1: cityStep
                case 2: biometricStep
                case 3 where coordinator.userRole == .guardian: paymentStep
                case 3: inviteStep
                case 4: inviteStep
                default: EmptyView()
                }
            }
            .frame(maxHeight: .infinity)

            // Bottom buttons
            bottomButtons
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .background(Color(.systemBackground))
        .onAppear {
            // Pre-fill city from country code
            if let country = coordinator.signupCountry {
                cityName = defaultCity(for: country.isoCode)
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                VStack(spacing: 4) {
                    Circle()
                        .fill(index <= currentStep ? navy : Color(.systemGray4))
                        .frame(width: 8, height: 8)
                    Text(stepTitles[index])
                        .font(.system(size: 10))
                        .foregroundStyle(index <= currentStep ? ink : .secondary)
                }
            }
        }
    }

    // MARK: - Step 1: Email

    private var emailStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 48))
                .foregroundStyle(navy.opacity(0.7))

            Text("添加邮箱")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ink)

            Text("用于账号找回和重要安全通知。\n我们不会向您发送营销邮件。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            TextField("your@email.com", text: $email)
                .font(.system(size: 16))
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)

            Spacer()
        }
    }

    // MARK: - Step 2: City

    private var cityStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "building.2")
                .font(.system(size: 48))
                .foregroundStyle(navy.opacity(0.7))

            Text("确认您的城市")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ink)

            Text("用于显示本地时间和紧急服务信息。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("例：上海、Toronto", text: $cityName)
                .font(.system(size: 16))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)

            Spacer()
        }
    }

    // MARK: - Step 3: Biometric

    private var biometricStep: some View {
        let biometric = BiometricAuthManager.shared

        return VStack(spacing: 16) {
            Spacer()

            Image(systemName: biometric.biometricIconName)
                .font(.system(size: 56))
                .foregroundStyle(navy.opacity(0.7))

            Text("启用\(biometric.biometricName)登录？")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ink)

            Text("下次打开守灯时，无需输入验证码即可快速登录。\n您可以随时在设置中关闭此功能。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            VStack(spacing: 12) {
                Button {
                    try? biometric.enable()
                    biometric.hasShownPrompt = true
                    advanceStep()
                } label: {
                    Text("启用\(biometric.biometricName)")
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(navy)
                        )
                }

                Button {
                    biometric.hasShownPrompt = true
                    advanceStep()
                } label: {
                    Text("暂不开启")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
    }

    // MARK: - Step 4: Payment (Guardian only)

    private var paymentStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(safe.opacity(0.8))

            Text("选择守护方案")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ink)

            Text("守灯提供7天免费试用，试用期间享受完整功能。\n试用结束后可继续使用基础版。")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            VStack(spacing: 10) {
                planCard(title: "单人关注版", price: "¥10/月", description: "守护1位家人", highlight: true)
                planCard(title: "家庭版", price: "¥30/月", description: "守护多位家人", highlight: false)
            }
            .padding(.horizontal, 8)

            Text("免费试用7天，随时取消")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)

            Spacer()
        }
    }

    private func planCard(title: String, price: String, description: String, highlight: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ink)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(price)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(highlight ? safe : .secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(highlight ? safe.opacity(0.08) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(highlight ? safe.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: - Step 5: Invite Guidance

    private var inviteStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: coordinator.userRole == .guardian ? "person.badge.plus" : "person.2.wave.2")
                .font(.system(size: 48))
                .foregroundStyle(navy.opacity(0.7))

            if coordinator.userRole == .guardian {
                Text("添加守护对象")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ink)

                Text("请被守护者在守灯APP中生成邀请码，\n然后在这里输入邀请码来建立守护关系。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                inviteCodeInput
            } else {
                Text("邀请守护者")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(ink)

                Text("生成邀请码并分享给您的家人，\n他们可以用守灯APP扫码加入守护。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                generateInviteButton
            }

            Spacer()
        }
    }

    @State private var inviteCode = ""
    @State private var inviteError = ""
    @State private var inviteSuccess = false

    private var inviteCodeInput: some View {
        VStack(spacing: 12) {
            TextField("输入邀请码", text: $inviteCode)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)

            if inviteSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(safe)
                    Text("守护关系已建立")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(safe)
                }
            }

            if !inviteError.isEmpty {
                Text(inviteError)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            Button {
                Task { await acceptInvite() }
            } label: {
                Text("确认邀请码")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(cream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(inviteCode.count >= 6 ? navy : Color(.systemGray4))
                    )
            }
            .disabled(inviteCode.count < 6 || isLoading)
            .padding(.horizontal, 8)
        }
    }

    @State private var generatedCode: String?

    private var generateInviteButton: some View {
        VStack(spacing: 12) {
            if let code = generatedCode {
                Text(code)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(navy)
                    .padding(.vertical, 8)

                Text("24小时内有效")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)

                Button {
                    let av = UIActivityViewController(activityItems: [
                        "我在用守灯(ShouDeng)守护家人安全，请输入邀请码加入：\(code)"
                    ], applicationActivities: nil)
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = scene.windows.first?.rootViewController {
                        root.present(av, animated: true)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("分享邀请码")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(cream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(navy)
                    )
                }
                .padding(.horizontal, 8)
            } else {
                Button {
                    Task { await generateCode() }
                } label: {
                    Text("生成邀请码")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(navy)
                        )
                }
                .disabled(isLoading)
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        HStack {
            // Skip / Back
            if currentStep > 0 && currentStep != 2 {
                Button("上一步") {
                    withAnimation { currentStep -= 1 }
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Next / Skip / Done
            if currentStep == 2 {
                // Biometric step has its own buttons
                EmptyView()
            } else if currentStep == totalSteps - 1 {
                Button {
                    Task { await finishWizard() }
                } label: {
                    HStack(spacing: 4) {
                        Text("开始使用")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(cream)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(navy)
                    )
                }
                .disabled(isLoading)
            } else {
                HStack(spacing: 16) {
                    if currentStep == 0 && email.isEmpty {
                        Button("稍后") {
                            advanceStep()
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    }

                    Button {
                        advanceStep()
                    } label: {
                        HStack(spacing: 4) {
                            Text("下一步")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(cream)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(navy)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func advanceStep() {
        withAnimation { currentStep += 1 }
    }

    private func acceptInvite() async {
        isLoading = true
        inviteError = ""
        do {
            let _: AcceptInviteResponse = try await coordinator.apiClient.post(
                "/v1/invite/accept",
                body: AcceptInviteRequest(code: inviteCode.trimmingCharacters(in: .whitespaces))
            )
            inviteSuccess = true
            await coordinator.fetchProtectedPersons()
        } catch {
            inviteError = "邀请码无效或已过期"
        }
        isLoading = false
    }

    private func generateCode() async {
        isLoading = true
        do {
            let response: CreateInviteResponse = try await coordinator.apiClient.post(
                "/v1/invite/create",
                body: CreateInviteRequest(role: "protected")
            )
            generatedCode = response.code
        } catch {
            #if DEBUG
            print("[Wizard] Failed to generate invite: \(error)")
            #endif
        }
        isLoading = false
    }

    private func finishWizard() async {
        isLoading = true

        // Save email and city to server
        var updates: [String: String] = [:]
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty && trimmedEmail.contains("@") {
            updates["email"] = trimmedEmail
        }
        let trimmedCity = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCity.isEmpty {
            updates["cityName"] = trimmedCity
        }

        if !updates.isEmpty {
            do {
                let _: SuccessResponse = try await coordinator.apiClient.put(
                    "/v1/user/me",
                    body: updates
                )
            } catch {
                #if DEBUG
                print("[Wizard] Failed to save profile: \(error)")
                #endif
            }
        }

        isLoading = false
        onComplete()
    }

    // MARK: - Helpers

    private func defaultCity(for countryCode: String) -> String {
        let map: [String: String] = [
            "CN": "上海", "HK": "香港", "TW": "台北", "JP": "东京",
            "KR": "首尔", "SG": "新加坡", "US": "New York", "CA": "Toronto",
            "GB": "London", "AU": "Sydney", "DE": "Berlin", "FR": "Paris",
        ]
        return map[countryCode] ?? ""
    }
}
