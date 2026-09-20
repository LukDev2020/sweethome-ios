import SwiftUI

// MARK: - Signup View
//
// Phone + verification code + name + role selection.
// Supports international phone numbers with country code picker.
// Role determines which portal (Protected/Guardian) the user enters.
//
// Security: 5 failed code attempts -> lock + contact Velar Care.

struct SignupView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var lang = LanguageManager.shared

    // Lighthouse palette (matching LoginView)
    private let navy = Color(red: 1/255, green: 69/255, blue: 129/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let ink2 = Color(red: 14/255, green: 43/255, blue: 74/255).opacity(0.62)
    private let ink3 = Color(red: 14/255, green: 43/255, blue: 74/255).opacity(0.4)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let red = Color(red: 246/255, green: 78/255, blue: 77/255)

    private let maxAttempts = 5
    private let lockoutKey = "signup_lockout_until"
    private let failedAttemptsKey = "signup_failed_attempts"

    @State private var selectedCountry = CountryCode.deviceDefault
    @State private var phone = ""
    @State private var code = ""
    @State private var displayName = ""
    @State private var selectedRole: UserRole = .protected_
    @State private var step: Step = .phone
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var countdown = 0
    @State private var countdownTimer: Timer?
    @State private var showCountryPicker = false
    @State private var failedAttempts = 0
    @State private var isLocked = false

    enum Step {
        case phone
        case code
        case profile
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                if isLocked {
                    lockedView
                } else {
                    stepContent
                }

                // Error + attempts warning
                if let errorMessage, !isLocked {
                    VStack(spacing: 4) {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(red)

                        if step == .code && failedAttempts > 0 {
                            let remaining = maxAttempts - failedAttempts
                            Text(String(format: lang.localized("login.attempts.warning"), remaining))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(remaining <= 2 ? red : ink3)
                        }
                    }
                    .padding(.top, 8)
                }

                // Action button
                if !isLocked {
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
                }

                Spacer()
                Spacer()
            }
            .background(Color(.systemBackground))
            .navigationTitle(lang.localized("signup.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang.localized("signup.back")) { dismiss() }
                }
            }
            .sheet(isPresented: $showCountryPicker) {
                CountryCodePicker(selected: $selectedCountry)
            }
            .onAppear {
                // Pre-fill phone if redirected from login (unregistered user)
                if let prefillPhone = coordinator.signupPhone {
                    phone = prefillPhone
                    coordinator.signupPhone = nil
                }
                if let prefillCountry = coordinator.signupCountry {
                    selectedCountry = prefillCountry
                    coordinator.signupCountry = nil
                }
                checkLockout()
            }
            .onDisappear {
                countdownTimer?.invalidate()
            }
        }
    }

    // MARK: - Locked View

    private var lockedView: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(navy.opacity(0.6))
                .padding(.bottom, 20)

            Text(lang.localized("login.locked.title"))
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(navy)

            Text(lang.localized("login.locked.message"))
                .font(.system(size: 14))
                .foregroundStyle(ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 12)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Step Content

    /// Full E.164 phone number
    private var fullPhoneNumber: String {
        let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        return "\(selectedCountry.dialCode)\(cleaned)"
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .phone:
            VStack(spacing: 16) {
                Text(lang.localized("signup.enter.phone"))
                    .font(.system(size: 20, weight: .bold))
                HStack(spacing: 0) {
                    // Country code button
                    Button {
                        showCountryPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedCountry.flag)
                                .font(.system(size: 18))
                            Text(selectedCountry.dialCode)
                                .font(.system(size: 15))
                                .foregroundStyle(ink)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }

                    TextField(lang.localized("login.phone.placeholder"), text: $phone)
                        .font(.system(size: 15))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .padding(12)
                }
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                )
            }
            .padding(.horizontal, 32)

        case .code:
            VStack(spacing: 16) {
                Text(lang.localized("signup.enter.code"))
                    .font(.system(size: 20, weight: .bold))
                Text(String(format: lang.localized("signup.code.sent"), selectedCountry.dialCode, phone))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField(lang.localized("login.code.placeholder"), text: $code)
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
                Text(lang.localized("signup.profile.title"))
                    .font(.system(size: 20, weight: .bold))
                TextField(lang.localized("signup.name.placeholder"), text: $displayName)
                    .font(.system(size: 15))
                    .textContentType(.name)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text(lang.localized("signup.role.title"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    roleOption(.protected_, icon: "shield.fill",
                               title: lang.localized("signup.role.protected"),
                               desc: lang.localized("signup.role.protected.desc"))
                    roleOption(.guardian, icon: "eye.fill",
                               title: lang.localized("signup.role.guardian"),
                               desc: lang.localized("signup.role.guardian.desc"))
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
        case .phone: return countdown > 0
            ? String(format: lang.localized("login.countdown"), countdown)
            : lang.localized("login.get.code")
        case .code:  return lang.localized("signup.next")
        case .profile: return lang.localized("signup.finish")
        }
    }

    private var buttonDisabled: Bool {
        if isLoading { return true }
        switch step {
        case .phone: return phone.count < 4 || countdown > 0
        case .code: return code.count < 4
        case .profile: return displayName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    // MARK: - Actions

    @MainActor
    private func handleAction() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            switch step {
            case .phone:
                try await coordinator.authManager.requestCode(phone: fullPhoneNumber)
                step = .code
                startCountdown()
            case .code:
                // Verify OTP now so invalid codes fail before profile entry
                try await coordinator.authManager.verifyCode(code: code)
                failedAttempts = 0
                UserDefaults.standard.set(0, forKey: failedAttemptsKey)
                step = .profile
            case .profile:
                try await coordinator.authManager.signup(
                    displayName: displayName,
                    role: selectedRole.rawValue,
                    countryCode: selectedCountry.isoCode
                )
                coordinator.userRole = selectedRole
                coordinator.showSignup = false
            }
        } catch {
            if step == .code {
                failedAttempts += 1
                UserDefaults.standard.set(failedAttempts, forKey: failedAttemptsKey)
                if failedAttempts >= maxAttempts {
                    lockAccount()
                    return
                }
            }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Lockout

    private func lockAccount() {
        let lockUntil = Date().addingTimeInterval(30 * 60) // 30 min lock
        UserDefaults.standard.set(lockUntil.timeIntervalSince1970, forKey: lockoutKey)
        isLocked = true
    }

    private func checkLockout() {
        let lockUntil = UserDefaults.standard.double(forKey: lockoutKey)
        if lockUntil > 0 {
            if Date().timeIntervalSince1970 < lockUntil {
                isLocked = true
            } else {
                // Lockout expired — reset
                UserDefaults.standard.removeObject(forKey: lockoutKey)
                UserDefaults.standard.set(0, forKey: failedAttemptsKey)
            }
        }
        failedAttempts = UserDefaults.standard.integer(forKey: failedAttemptsKey)
    }

    @MainActor
    private func startCountdown() {
        countdown = 60
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in
            Task { @MainActor in
                if countdown > 0 { countdown -= 1 }
                else { countdownTimer?.invalidate() }
            }
        }
    }
}
