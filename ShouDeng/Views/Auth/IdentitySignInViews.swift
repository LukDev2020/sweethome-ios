import SwiftUI
import AuthenticationServices

// MARK: - Sign in with Apple / Alipay (login screen) and Settings → Sign-in methods

private let navy = Color(red: 1/255, green: 69/255, blue: 129/255)
private let ink = Color(red: 14/255, green: 43/255, blue: 74/255)
private let ink3 = Color(red: 14/255, green: 43/255, blue: 74/255).opacity(0.4)
private let line = Color(red: 1/255, green: 69/255, blue: 129/255).opacity(0.13)
private let red = Color(red: 246/255, green: 78/255, blue: 77/255)
private let alipayBlue = Color(red: 22/255, green: 119/255, blue: 255/255)

/// "Sign in with Apple" and (once the server has Alipay's keys) "Sign in with Alipay".
/// Both need the Terms agreed, like the phone code.
struct IdentitySignInButtons: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    let termsAccepted: Bool
    /// Mainland-China network likely (+86 chosen, or the app is on the relay):
    /// phone codes need Google's servers there, so point to Apple / Alipay.
    var recommendForChina = false

    @State private var alipayAvailable = false
    @State private var showTermsHint = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Rectangle().fill(line).frame(height: 1)
                Text(lang.localized("auth.identity.or")).font(.scaled(size: 12)).foregroundStyle(ink3)
                Rectangle().fill(line).frame(height: 1)
            }

            if recommendForChina {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.scaled(size: 13))
                        .foregroundStyle(navy.opacity(0.7))
                    Text(lang.localized(alipayAvailable ? "auth.china.hint.appleAlipay" : "auth.china.hint.apple"))
                        .font(.scaled(size: 12.5))
                        .foregroundStyle(navy.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(navy.opacity(0.06)))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("login.chinaHint")
            }

            AppleIDButton { result, nonce in
                Task { await coordinator.handleAppleSignIn(result, rawNonce: nonce) }
            }
            // Always full colour: a greyed-out Apple button read as "Apple sign-in is broken".
            // Until the Terms are ticked, a tap shows why instead of opening Apple's sheet.
            .allowsHitTesting(termsAccepted)
            .disabled(!termsAccepted)   // VoiceOver can't bypass the Terms either
            .accessibilityIdentifier("login.apple")
            .overlay {
                if !termsAccepted {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { showTermsHint = true }
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: termsAccepted) { _, accepted in if accepted { showTermsHint = false } }

            if showTermsHint && !termsAccepted {
                Text(lang.localized("terms.update.required"))
                    .font(.scaled(size: 12))
                    .foregroundStyle(red)
                    .multilineTextAlignment(.center)
            }

            if alipayAvailable {
                if coordinator.alipayWaiting && !coordinator.alipayConnecting {
                    AlipayWaitingCard()
                } else {
                    AlipaySignInButton(title: lang.localized("auth.alipay.signIn")) {
                        Task { await coordinator.startAlipaySignIn() }
                    }
                    .disabled(!termsAccepted)
                    .opacity(termsAccepted ? 1 : 0.4)
                }
            }

            if let error = coordinator.identitySignInError {
                Text(error)
                    .font(.scaled(size: 12))
                    .foregroundStyle(red)
                    .multilineTextAlignment(.center)
            }
        }
        .task {
            alipayAvailable = await coordinator.authManager.providers()?.alipay ?? false
        }
    }
}

struct AlipaySignInButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("支")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(alipayBlue)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.white))
                Text(title)
                    .font(.scaled(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(alipayBlue))
        }
        .accessibilityIdentifier("login.alipay")
    }
}

/// Sent to Alipay: "Check again" (Alipay answered but nobody came back) or cancel
struct AlipayWaitingCard: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                Text(lang.localized("auth.alipay.waiting"))
                    .font(.scaled(size: 13))
                    .foregroundStyle(ink)
            }
            HStack(spacing: 16) {
                Button(lang.localized("auth.alipay.checkAgain")) {
                    Task { await coordinator.finishAlipaySignIn(quiet: false) }
                }
                .font(.scaled(size: 13, weight: .medium))
                Button(lang.localized("auth.alipay.cancel")) { coordinator.cancelAlipaySignIn() }
                    .font(.scaled(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(alipayBlue.opacity(0.4), lineWidth: 1))
    }
}

/// Login screen after "I already have an account": sign in with the phone to connect
struct PendingIdentityLinkBanner: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    let pending: PendingIdentity

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: pending.provider == .apple ? "applelogo" : "link")
                .font(.scaled(size: 14))
                .foregroundStyle(navy)
            Text(lang.localized(pending.provider == .apple ? "auth.link.byPhone.apple" : "auth.link.byPhone.alipay"))
                .font(.scaled(size: 12.5))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { coordinator.authManager.cancelPendingIdentity() } label: {
                Image(systemName: "xmark").font(.scaled(size: 11, weight: .semibold)).foregroundStyle(ink3)
            }
            .accessibilityLabel(lang.localized("auth.alipay.cancel"))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(navy.opacity(0.06)))
    }
}

// MARK: - Settings → Sign-in methods

struct SignInMethodsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @State private var methods: SignInMethodsResponse?
    @State private var alipayAvailable = false
    @State private var loadFailed = false
    @State private var showAddPhone = false

    var body: some View {
        List {
            Section {
                row(icon: "phone.fill", title: lang.localized("auth.methods.phone"),
                    detail: methods?.phone ?? lang.localized("auth.methods.notAdded")) {
                    if methods != nil && methods?.phone == nil {
                        Button(lang.localized("auth.methods.addPhone")) { showAddPhone = true }
                            .accessibilityIdentifier("methods.addPhone")
                    }
                }
                row(icon: "applelogo", title: "Apple",
                    detail: methods?.apple == true ? lang.localized("auth.methods.connected") : nil) {
                    if methods?.apple == false {
                        AppleIDButton(kind: .continue, scopes: [], height: 34, cornerRadius: 8) { result, nonce in
                            Task {
                                await coordinator.handleAppleSignIn(result, rawNonce: nonce, connecting: true)
                                await load()
                            }
                        }
                        .frame(width: 170)
                    }
                }
                if alipayAvailable || methods?.alipay == true {
                    row(icon: "link", title: lang.localized("auth.methods.alipay"),
                        detail: methods?.alipay == true ? lang.localized("auth.methods.connected") : nil) {
                        if methods?.alipay == false {
                            if coordinator.alipayWaiting && coordinator.alipayConnecting {
                                ProgressView()
                            } else {
                                Button(lang.localized("auth.methods.connect")) {
                                    Task { await coordinator.startAlipaySignIn(connecting: true) }
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text(lang.localized(methods?.phone == nil ? "auth.methods.phoneWhy" : "auth.methods.footer"))
            }

            if let error = coordinator.identitySignInError {
                Text(error).font(.scaled(size: 12)).foregroundStyle(red)
            } else if loadFailed {
                Text(lang.localized("auth.methods.loadFailed")).font(.scaled(size: 12)).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(lang.localized("auth.methods.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            coordinator.identitySignInError = nil
            await load()
            alipayAvailable = await coordinator.authManager.providers()?.alipay ?? false
        }
        .onChange(of: coordinator.alipayJustConnected) { _, connected in
            if connected {
                coordinator.alipayJustConnected = false
                Task { await load() }
            }
        }
        .sheet(isPresented: $showAddPhone) {
            AddPhoneNumberView { phone in
                coordinator.currentUser?.phone = phone
                Task { await load() }
            }
            .environmentObject(coordinator)
        }
    }

    private func load() async {
        do {
            methods = try await coordinator.authManager.signInMethods()
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    private func row<Trailing: View>(icon: String, title: String, detail: String?,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(navy)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.scaled(size: 15))
                if let detail { Text(detail).font(.scaled(size: 12)).foregroundStyle(.secondary) }
            }
            Spacer()
            trailing()
        }
    }
}

/// Add a phone number to an Apple / Alipay account (Firebase sends the code)
struct AddPhoneNumberView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss
    let onAdded: (String?) -> Void

    @State private var country = CountryCode.deviceDefault
    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCountryPicker = false

    private var fullPhone: String {
        country.dialCode + phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Button("\(country.flag) \(country.dialCode)") { showCountryPicker = true }
                            .buttonStyle(.bordered)
                        TextField(lang.localized("login.phone.placeholder"), text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .disabled(codeSent)
                    }
                    if codeSent {
                        TextField(lang.localized("login.code.placeholder"), text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    }
                } footer: {
                    Text(lang.localized("auth.methods.phoneWhy"))
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(red).font(.scaled(size: 13))
                }
                Button {
                    Task { await next() }
                } label: {
                    if isLoading { ProgressView() } else {
                        Text(lang.localized(codeSent ? "auth.methods.addPhone" : "login.get.code"))
                    }
                }
                .disabled(isLoading || (codeSent ? code.count < 4 : phone.count < 4))
            }
            .navigationTitle(lang.localized("auth.methods.addPhone"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.localized("auth.alipay.cancel")) { dismiss() }
                }
            }
            .sheet(isPresented: $showCountryPicker) { CountryCodePicker(selected: $country) }
        }
    }

    @MainActor
    private func next() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            if codeSent {
                let added = try await coordinator.authManager.linkPhone(code: code)
                onAdded(added ?? fullPhone)
                dismiss()
            } else {
                try await coordinator.authManager.requestCode(phone: fullPhone)
                codeSent = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Settings: an account without a phone number (signed up with Apple / Alipay)
struct PhoneMissingBanner: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        if !coordinator.isDemo, let user = coordinator.currentUser, (user.phone ?? "").isEmpty {
            NavigationLink {
                SignInMethodsView().environmentObject(coordinator)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "phone.badge.plus")
                        .font(.scaled(size: 14))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lang.localized("auth.methods.addPhone"))
                            .font(.scaled(size: 13, weight: .medium))
                            .foregroundStyle(ink)
                        Text(lang.localized("auth.methods.phoneWhy"))
                            .font(.scaled(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.15), lineWidth: 1))
                )
            }
            .buttonStyle(.settingsRow)
        }
    }
}

/// Settings → Security: the row into Sign-in methods
struct SignInMethodsRow: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    let tint: Color

    var body: some View {
        if !coordinator.isDemo {
            NavigationLink {
                SignInMethodsView().environmentObject(coordinator)
            } label: {
                SettingsRow(icon: "person.badge.key.fill", tint: tint, title: lang.localized("auth.methods.title"))
            }
            .buttonStyle(.settingsRow)
        }
    }
}

// MARK: - Apple button in the app's own language

/// "Sign in with Apple" drawn to Apple's guidelines (black, Apple logo, Apple's
/// wording) so the title follows the in-app language right away. Apple's
/// SignInWithAppleButton only uses the language the app was launched in.
struct AppleIDButton: View {
    enum Kind { case signIn, `continue` }

    @ObservedObject private var lang = LanguageManager.shared
    var kind: Kind = .signIn
    var scopes: [ASAuthorization.Scope] = [.fullName, .email]
    var height: CGFloat = 50
    var cornerRadius: CGFloat = 13
    /// Gets the raw nonce (for the server) with Apple's answer
    let onCompletion: (Result<ASAuthorization, Error>, String) -> Void

    @State private var runner = AppleSignInRunner()

    var body: some View {
        Button {
            let nonce = AppleSignInNonce.make()
            Task {
                let result = await runner.run(scopes: scopes, nonceHash: AppleSignInNonce.sha256(nonce))
                onCompletion(result, nonce)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "applelogo")
                    .font(.system(size: height * 0.36, weight: .medium))
                    .offset(y: -1)
                Text(lang.localized(kind == .signIn ? "auth.apple.button.signIn" : "auth.apple.button.continue"))
                    .font(.system(size: height * 0.38, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.black, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        // Stays black while the Terms aren't ticked: a grey Apple button read as "broken"
        .buttonStyle(AppleIDButtonStyle())
    }
}

private struct AppleIDButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}
