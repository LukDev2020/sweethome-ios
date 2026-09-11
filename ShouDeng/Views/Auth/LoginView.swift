import SwiftUI

// MARK: - Login View
//
// Phone + verification code login flow with international country code picker.
// Design follows the lighthouse design system:
//   navy #014581, blue #3D9AC0, cream #FCF2DA, bg #FBF8F1, ink #0E2B4A
//
// Security: 5 failed code attempts → lock + contact Velar Care.
// Reset: clears all state and returns to phone entry.

struct LoginView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    // Lighthouse palette
    private let navy = Color(red: 1/255, green: 69/255, blue: 129/255)
    private let blue = Color(red: 61/255, green: 154/255, blue: 192/255)
    private let cream = Color(red: 252/255, green: 242/255, blue: 218/255)
    private let bg = Color(red: 251/255, green: 248/255, blue: 241/255)
    private let ink = Color(red: 14/255, green: 43/255, blue: 74/255)
    private let ink2 = Color(red: 14/255, green: 43/255, blue: 74/255).opacity(0.62)
    private let ink3 = Color(red: 14/255, green: 43/255, blue: 74/255).opacity(0.4)
    private let line = Color(red: 1/255, green: 69/255, blue: 129/255).opacity(0.13)
    private let red = Color(red: 246/255, green: 78/255, blue: 77/255)

    private let maxAttempts = 5
    private let lockoutKey = "login_lockout_until"

    @State private var selectedCountry = CountryCode.deviceDefault
    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var countdown = 0
    @State private var countdownTimer: Timer?
    @State private var showCountryPicker = false
    @State private var failedAttempts = 0
    @State private var isLocked = false

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            if isLocked {
                lockedView
            } else {
                loginView
            }
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryCodePicker(selected: $selectedCountry)
        }
        .onAppear {
            checkLockout()
        }
        .onDisappear {
            countdownTimer?.invalidate()
        }
    }

    // MARK: - Locked View

    private var lockedView: some View {
        VStack(spacing: 0) {
            Spacer()

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

            Button {
                openSupport()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 13))
                    Text(lang.localized("login.locked.contact"))
                }
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(navy)
                )
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Login View

    private var loginView: some View {
        VStack(spacing: 0) {
            // Top bar: reset (left) + language (right)
            HStack {
                if codeSent || errorMessage != nil {
                    Button {
                        resetAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text(lang.localized("login.reset"))
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(navy.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(navy.opacity(0.06))
                        )
                    }
                    .padding(.leading, 20)
                }

                Spacer()

                HStack(spacing: 2) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Button {
                            lang.current = language
                        } label: {
                            Text(language.displayName)
                                .font(.system(size: 12))
                                .foregroundStyle(lang.current == language ? navy : ink3)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    lang.current == language
                                        ? Capsule().fill(navy.opacity(0.09))
                                        : nil
                                )
                        }
                    }
                }
                .padding(.trailing, 20)
            }
            .padding(.top, 6)

            Spacer()

            // Brand area
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [blue.opacity(0.16), blue.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                VStack(spacing: 0) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text(lang.localized("app.name"))
                        .font(.system(size: 29, weight: .black, design: .serif))
                        .foregroundStyle(navy)
                        .tracking(1.5)
                        .padding(.top, 10)

                    Text("VELAR CARE")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(blue)
                        .tracking(3.5)
                        .padding(.top, 4)

                    Text(lang.localized("app.tagline"))
                        .font(.system(size: 13.5))
                        .foregroundStyle(ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, 12)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.bottom, 36)

            // Phone input row
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Button {
                        showCountryPicker = true
                    } label: {
                        HStack(spacing: 5) {
                            Text(selectedCountry.flag)
                                .font(.system(size: 18))
                            Text(selectedCountry.dialCode)
                                .font(.system(size: 14))
                                .foregroundStyle(ink)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(ink3)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(line, lineWidth: 1)
                                )
                        )
                    }

                    TextField(lang.localized("login.phone.placeholder"), text: $phone)
                        .font(.system(size: 15))
                        .foregroundStyle(ink)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .padding(15)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(line, lineWidth: 1)
                                )
                        )
                }

                if codeSent {
                    TextField(lang.localized("login.code.placeholder"), text: $code)
                        .font(.system(size: 15))
                        .foregroundStyle(ink)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .padding(15)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(line, lineWidth: 1)
                                )
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 32)
            .animation(.easeInOut(duration: 0.3), value: codeSent)

            // Error + attempts warning
            if let errorMessage {
                VStack(spacing: 4) {
                    Text(errorMessage)
                        .font(.system(size: 11.5))
                        .foregroundStyle(red)

                    if codeSent && failedAttempts > 0 {
                        let remaining = maxAttempts - failedAttempts
                        Text(String(format: lang.localized("login.attempts.warning"), remaining))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(remaining <= 2 ? red : ink3)
                    }
                }
                .padding(.top, 10)
                .padding(.horizontal, 32)
            }

            // Action button
            Button {
                Task { await handleAction() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(cream)
                    } else {
                        Text(codeSent
                            ? lang.localized("login.button")
                            : (countdown > 0
                                ? String(format: lang.localized("login.countdown"), countdown)
                                : lang.localized("login.get.code")))
                    }
                }
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(buttonDisabled ? navy.opacity(0.42) : cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(buttonDisabled ? navy.opacity(0.11) : navy)
                )
            }
            .disabled(buttonDisabled)
            .padding(.horizontal, 32)
            .padding(.top, 16)

            // Switch to signup
            Button {
                coordinator.showSignup = true
            } label: {
                HStack(spacing: 0) {
                    Text(lang.localized("login.no.account"))
                        .foregroundStyle(ink3)
                    Text(lang.localized("login.signup"))
                        .foregroundStyle(ink2)
                        .underline(true, color: ink2)
                }
                .font(.system(size: 11.5))
            }
            .padding(.top, 13)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Helpers

    private var fullPhoneNumber: String {
        let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        return "\(selectedCountry.dialCode)\(cleaned)"
    }

    private var buttonDisabled: Bool {
        if isLoading { return true }
        if codeSent { return code.count < 4 }
        return phone.count < 4 || countdown > 0
    }

    // MARK: - Actions

    @MainActor
    private func handleAction() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            if codeSent {
                try await coordinator.authManager.login(phone: fullPhoneNumber, code: code)
                failedAttempts = 0
            } else {
                try await coordinator.authManager.requestCode(phone: fullPhoneNumber)
                codeSent = true
                startCountdown()
            }
        } catch {
            let errorType = String(describing: type(of: error))
            let errorCase = String(describing: error)
            #if DEBUG
            print("[LoginView] error type: \(errorType), case: \(errorCase)")
            print("[LoginView] localized: \(error.localizedDescription)")
            #endif

            // Detect "user not found" — check multiple ways for robustness
            let isUserNotFound =
                errorCase == "userNotFound" ||
                errorCase == "notFound" ||
                error.localizedDescription.contains("资源不存在") ||
                error.localizedDescription.contains("not found")

            if codeSent && isUserNotFound {
                coordinator.signupPhone = phone
                coordinator.signupCountry = selectedCountry
                coordinator.showSignup = true
                return
            }

            if codeSent {
                failedAttempts += 1
                if failedAttempts >= maxAttempts {
                    lockAccount()
                    return
                }
            }
            errorMessage = error.localizedDescription
        }
    }

    private func resetAll() {
        countdownTimer?.invalidate()
        phone = ""
        code = ""
        codeSent = false
        isLoading = false
        errorMessage = nil
        countdown = 0
        countdownTimer = nil
        // Don't reset failedAttempts — persists across resets
    }

    private func lockAccount() {
        let lockUntil = Date().addingTimeInterval(30 * 60) // 30 min lock
        UserDefaults.standard.set(lockUntil.timeIntervalSince1970, forKey: lockoutKey)
        isLocked = true
    }

    private func checkLockout() {
        let lockUntil = UserDefaults.standard.double(forKey: lockoutKey)
        if lockUntil > 0 && Date().timeIntervalSince1970 < lockUntil {
            isLocked = true
        }
    }

    private func openSupport() {
        if let url = URL(string: "mailto:support@velarcare.com?subject=Account%20Locked") {
            UIApplication.shared.open(url)
        }
    }

    @MainActor
    private func startCountdown() {
        countdown = 60
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] _ in
            Task { @MainActor in
                if countdown > 0 {
                    countdown -= 1
                } else {
                    countdownTimer?.invalidate()
                }
            }
        }
    }
}
