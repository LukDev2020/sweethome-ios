import SwiftUI

// MARK: - Signup View
//
// Phone + verification code + name + role selection.
// Supports international phone numbers with country code picker.
// Role determines which portal (Protected/Guardian) the user enters.

struct SignupView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) var dismiss

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

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
            .navigationTitle(NSLocalizedString("signup.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("signup.back", comment: "")) { dismiss() }
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
            }
            .onDisappear {
                countdownTimer?.invalidate()
            }
        }
    }

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
                Text(NSLocalizedString("signup.enter.phone", comment: ""))
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

                    TextField(NSLocalizedString("login.phone.placeholder", comment: ""), text: $phone)
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
                Text(NSLocalizedString("signup.enter.code", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                Text(String(format: NSLocalizedString("signup.code.sent", comment: ""), selectedCountry.dialCode, phone))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField(NSLocalizedString("login.code.placeholder", comment: ""), text: $code)
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
                Text(NSLocalizedString("signup.profile.title", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                TextField(NSLocalizedString("signup.name.placeholder", comment: ""), text: $displayName)
                    .font(.system(size: 15))
                    .textContentType(.name)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("signup.role.title", comment: ""))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    roleOption(.protected_, icon: "shield.fill",
                               title: NSLocalizedString("signup.role.protected", comment: ""),
                               desc: NSLocalizedString("signup.role.protected.desc", comment: ""))
                    roleOption(.guardian, icon: "eye.fill",
                               title: NSLocalizedString("signup.role.guardian", comment: ""),
                               desc: NSLocalizedString("signup.role.guardian.desc", comment: ""))
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
            ? String(format: NSLocalizedString("login.countdown", comment: ""), countdown)
            : NSLocalizedString("login.get.code", comment: "")
        case .code:  return NSLocalizedString("signup.next", comment: "")
        case .profile: return NSLocalizedString("signup.finish", comment: "")
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
                step = .profile
            case .profile:
                try await coordinator.authManager.signup(
                    phone: fullPhoneNumber,
                    code: code,
                    displayName: displayName,
                    role: selectedRole.rawValue
                )
                coordinator.userRole = selectedRole
                coordinator.showSignup = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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
