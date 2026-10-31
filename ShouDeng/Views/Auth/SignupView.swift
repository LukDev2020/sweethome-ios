import SwiftUI

// MARK: - Signup View
//
// Phone + verification code + name + "how do you want to start?".
// Supports international phone numbers with country code picker.
// Nothing is preselected: protected, guardian, or "I have an invite code"
// (then the invite decides the side, after the account exists).
// A login that verified an unregistered number opens straight at the profile.
//
// Security: 5 failed code attempts -> lock + contact Vela support.

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
    @State private var selectedRole: UserRole?
    @State private var usesInviteCode = false
    @State private var inviteCode = ""
    /// Opened from a login that already verified this number (no second SMS)
    @State private var phoneVerifiedByLogin = false
    @State private var agreedToDataTransfer = false
    @State private var step: Step = .phone
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var countdown = 0
    @State private var countdownTimer: Timer?
    @State private var showCountryPicker = false
    @State private var failedAttempts = 0
    @State private var isLocked = false
    @State private var birthdate = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var showAgeRestricted = false

    private enum Field { case phone, code, name, invite }
    @FocusState private var focusedField: Field?

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
                            .font(.scaled(size: 13))
                            .foregroundStyle(red)

                        if step == .code && failedAttempts > 0 {
                            let remaining = maxAttempts - failedAttempts
                            Text(String(format: lang.localized("login.attempts.warning"), remaining))
                                .font(.scaled(size: 12, weight: .medium))
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
                        .font(.scaled(size: 15, weight: .medium))
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
            .contentShape(Rectangle())
            .onTapGesture { focusedField = nil }
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
                // Login already verified this number: go straight to the profile
                if coordinator.signupPhoneVerified, coordinator.authManager.hasVerifiedPhone {
                    phoneVerifiedByLogin = true
                    step = .profile
                }
                coordinator.signupPhoneVerified = false
                // Opened from an invite link: that path is chosen and the code filled in
                if case .invite(let linkCode) = coordinator.pendingDeepLink {
                    chooseInvite()
                    inviteCode = linkCode
                }
                checkLockout()
                applyLanguageForCountry(selectedCountry)
            }
            .onChange(of: selectedCountry) { _, newCountry in
                applyLanguageForCountry(newCountry)
            }
            .onDisappear {
                countdownTimer?.invalidate()
            }
            .alert(lang.localized("signup.age.restricted.title"), isPresented: $showAgeRestricted) {
                Button(lang.localized("signup.age.restricted.ok")) { }
            } message: {
                Text(lang.localized("signup.age.restricted.message"))
            }
        }
    }

    private var userAge: Int {
        Calendar.current.dateComponents([.year], from: birthdate, to: Date()).year ?? 0
    }

    // MARK: - Locked View

    private var lockedView: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock.shield.fill")
                .font(.scaled(size: 48))
                .foregroundStyle(navy.opacity(0.6))
                .padding(.bottom, 20)

            Text(lang.localized("login.locked.title"))
                .font(.scaled(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(navy)

            Text(lang.localized("login.locked.message"))
                .font(.scaled(size: 14))
                .foregroundStyle(ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 12)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Language Auto-Switch

    private func applyLanguageForCountry(_ country: CountryCode) {
        let chineseRegions: Set<String> = ["CN", "HK", "MO", "TW"]
        let target: AppLanguage
        if chineseRegions.contains(country.isoCode) {
            target = country.isoCode == "CN" ? .chinese : .traditionalChinese
        } else if country.isoCode == "FR" {
            target = .french
        } else if country.isoCode == "JP" {
            target = .japanese
        } else {
            target = .english
        }
        if lang.current != target {
            lang.suggest(target)
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
                    .font(.scaled(size: 20, weight: .bold))
                HStack(spacing: 0) {
                    // Country code button
                    Button {
                        showCountryPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedCountry.flag)
                                .font(.scaled(size: 18))
                            Text(selectedCountry.dialCode)
                                .font(.scaled(size: 15))
                                .foregroundStyle(ink)
                            Image(systemName: "chevron.down")
                                .font(.scaled(size: 9, weight: .semibold))
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
                        .font(.scaled(size: 15))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($focusedField, equals: .phone)
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
                    .font(.scaled(size: 20, weight: .bold))
                Text(String(format: lang.localized("signup.code.sent"), selectedCountry.dialCode, phone))
                    .font(.scaled(size: 13))
                    .foregroundStyle(.secondary)
                TextField(lang.localized("login.code.placeholder"), text: $code)
                    .font(.scaled(size: 15))
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($focusedField, equals: .code)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 32)

        case .profile:
            ScrollView {
                VStack(spacing: 16) {
                    if phoneVerifiedByLogin {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(safe)
                            Text(String(format: lang.localized("signup.verified.banner"), "\(selectedCountry.dialCode) \(phone)"))
                                .font(.scaled(size: 13))
                                .foregroundStyle(ink2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(safe.opacity(0.08)))
                    }

                    Text(lang.localized("signup.profile.title"))
                        .font(.scaled(size: 20, weight: .bold))
                    TextField(lang.localized("signup.name.placeholder"), text: $displayName)
                        .font(.scaled(size: 15))
                        .textContentType(.name)
                        .focused($focusedField, equals: .name)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(lang.localized("signup.birthdate"))
                            .font(.scaled(size: 13))
                            .foregroundStyle(.secondary)
                        DatePicker("", selection: $birthdate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                    }

                    if userAge >= 13 && userAge < 18 {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(lamp)
                                .font(.scaled(size: 14))
                            Text(lang.localized("signup.minor.parental.notice"))
                                .font(.scaled(size: 12))
                                .foregroundStyle(ink2)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(lamp.opacity(0.08))
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(lang.localized("signup.start.title"))
                            .font(.scaled(size: 15, weight: .semibold))
                            .foregroundStyle(ink)
                        Text(lang.localized("signup.start.subtitle"))
                            .font(.scaled(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        startOption(isSelected: selectedRole == .protected_, icon: "shield.fill",
                                    title: lang.localized("signup.start.protected"),
                                    desc: lang.localized("signup.start.protected.desc")) {
                            chooseRole(.protected_)
                        }
                        .accessibilityIdentifier("signup.start.protected")
                        startOption(isSelected: selectedRole == .guardian, icon: "eye.fill",
                                    title: lang.localized("signup.start.guardian"),
                                    desc: lang.localized("signup.start.guardian.desc")) {
                            chooseRole(.guardian)
                        }
                        .accessibilityIdentifier("signup.start.guardian")
                        startOption(isSelected: usesInviteCode, icon: "key.fill",
                                    title: lang.localized("signup.start.invite"),
                                    desc: lang.localized("signup.start.invite.desc")) {
                            chooseInvite()
                            focusedField = .invite
                        }
                        .accessibilityIdentifier("signup.start.invite")

                        if usesInviteCode {
                            TextField(lang.localized("wizard.invite.codePlaceholder"), text: $inviteCode)
                                .font(.scaled(size: 18, weight: .semibold, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .textInputAutocapitalization(.characters)
                                .keyboardType(.asciiCapable) // pinyin/kana keyboards hold letters as marked text
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .invite)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                                )
                                .onChange(of: inviteCode) { _, newValue in
                                    let cleaned = String(newValue.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(12))
                                    if cleaned != newValue { inviteCode = cleaned }
                                }
                                .accessibilityIdentifier("signup.inviteCode")
                        }
                    }

                    DataTransferConsentToggle(isOn: $agreedToDataTransfer)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func chooseRole(_ role: UserRole) {
        selectedRole = role
        usesInviteCode = false
    }

    private func chooseInvite() {
        selectedRole = nil
        usesInviteCode = true
    }

    private func startOption(isSelected: Bool, icon: String, title: String, desc: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.scaled(size: 18))
                    .foregroundStyle(isSelected ? lamp : ink.opacity(0.4))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.scaled(size: 16, weight: .medium))
                        .foregroundStyle(ink)
                    Text(desc)
                        .font(.scaled(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? safe : Color(.separator))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? safe.opacity(0.5) : Color(.separator).opacity(0.3), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        case .profile:
            return !SignupProfileGate.canFinish(name: displayName, selectedRole: selectedRole,
                                                usesInviteCode: usesInviteCode, inviteCode: inviteCode,
                                                agreedToDataTransfer: agreedToDataTransfer)
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
                if userAge < 13 {
                    showAgeRestricted = true
                    return
                }
                ConsentLogger.shared.log(
                    userId: "pre-signup",
                    item: "coppa.age_verification",
                    copyVersion: "v1.0",
                    action: userAge < 18 ? "minor_acknowledged" : "adult_verified"
                )
                guard let role = SignupProfileGate.accountRole(selectedRole: selectedRole,
                                                               usesInviteCode: usesInviteCode) else { return }
                try await coordinator.authManager.signup(
                    displayName: displayName,
                    role: role.rawValue,
                    countryCode: selectedCountry.isoCode,
                    dataTransferConsent: DataTransferConsent.version
                )
                coordinator.userRole = role
                coordinator.showSetupWizard = true
                if usesInviteCode {
                    // The account exists now: confirm and accept the invite right
                    // away. Accepting sets the side the invite gives this account.
                    if case .invite = coordinator.pendingDeepLink { coordinator.pendingDeepLink = nil }
                    coordinator.presentInviteAccept(code: inviteCode)
                }
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

// MARK: - Profile step rules

/// "How do you want to start?" has no default: Finish stays disabled until one
/// of the three options is chosen (and, for an invite, a code is entered).
enum SignupProfileGate {
    static func canFinish(name: String, selectedRole: UserRole?, usesInviteCode: Bool,
                          inviteCode: String, agreedToDataTransfer: Bool) -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, agreedToDataTransfer else { return false }
        if usesInviteCode {
            return DeepLinkRouter.normalizedInviteCode(inviteCode) != nil
        }
        return selectedRole != nil
    }

    /// Role the account is created with. On the invite path the invite decides
    /// the side when it is accepted; until then the account starts as protected
    /// (the server moves it to the guardian side if the invite says so).
    static func accountRole(selectedRole: UserRole?, usesInviteCode: Bool) -> UserRole? {
        usesInviteCode ? .protected_ : selectedRole
    }
}
