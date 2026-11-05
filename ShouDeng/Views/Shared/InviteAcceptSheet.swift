import SwiftUI

// MARK: - Invite Accept Sheet
//
// One screen for every way into an invite: an invite link, "Enter invite code"
// in the family circle, Settings → "Join family", the setup wizard and the
// "I have an invite code" sign-up path (presented by RootView).
//
//   enter / prefilled code → preview (who, and what accepting means) → accept
//
// The invite decides who guards whom, so there is no "role mismatch" any more.
// Each failure gets its own message (docs/roles/mockups.html ③).

// MARK: - Failures

enum InviteFailure: Equatable {
    case notFound
    case expired
    case used
    case selfAccept
    /// - max: how many people the guardian's plan covers, when the server says
    /// - yourPlan: the full plan is mine (I would be the guardian)
    case planLimit(max: Int?, yourPlan: Bool)
    /// The family's plan has no guardian seat left (households: Essential 2, Family 4)
    case guardianLimit(max: Int?, yourPlan: Bool)
    case network
    case tooManyAttempts
    case other

    init(error: Error) {
        if let coded = error as? APIServerError {
            switch coded.code {
            case "NOT_FOUND": self = .notFound
            case "INVITE_EXPIRED": self = .expired
            case "INVITE_USED": self = .used
            case "SELF_ACCEPT": self = .selfAccept
            case "PLAN_LIMIT" where coded.details["limit"] == "guardians":
                self = .guardianLimit(max: coded.details["max"].flatMap { Int($0) },
                                      yourPlan: coded.details["guardianIsYou"] == "true")
            case "PLAN_LIMIT":
                self = .planLimit(max: coded.details["maxProtected"].flatMap { Int($0) },
                                  yourPlan: coded.details["guardianIsYou"] == "true")
            default:
                self = InviteFailure(status: coded.status)
            }
            return
        }
        if let api = error as? APIError {
            switch api {
            case .notFound: self = .notFound
            case .conflict: self = .used
            case .forbidden: self = .planLimit(max: nil, yourPlan: false)
            case .serverError(410): self = .expired
            case .rateLimited: self = .tooManyAttempts
            case .networkError, .serverError, .unknown: self = .network
            default: self = .other
            }
            return
        }
        if error is URLError {
            self = .network
            return
        }
        self = .other
    }

    /// Servers that answer without a `code` (or with one this app doesn't know).
    private init(status: Int) {
        switch status {
        case 404: self = .notFound
        case 409: self = .used
        case 410: self = .expired
        case 403: self = .planLimit(max: nil, yourPlan: false)
        case 429: self = .tooManyAttempts
        default: self = .other
        }
    }

    /// A preview of an invite that can't be accepted.
    init?(preview: InvitePreviewResponse) {
        switch preview.status {
        case "expired": self = .expired
        case "accepted": self = .used
        default:
            guard preview.isOwnInvite != true else { self = .selfAccept; return }
            return nil
        }
    }

    var message: String {
        let lang = LanguageManager.shared
        switch self {
        case .notFound: return lang.localized("invite.error.notFound")
        case .expired: return lang.localized("invite.error.expired")
        case .used: return lang.localized("invite.error.used")
        case .selfAccept: return lang.localized("invite.error.self")
        case .planLimit(let max?, true): return String(format: lang.localized("invite.error.planLimit.yours"), max)
        case .planLimit(nil, true): return lang.localized("invite.error.planLimit.yoursFull")
        case .planLimit(let max?, false): return String(format: lang.localized("invite.error.planLimit.theirs"), max)
        case .planLimit(nil, false): return lang.localized("invite.error.planLimit.theirsFull")
        case .guardianLimit(let max?, true): return String(format: lang.localized("invite.error.guardianLimit.yours"), max)
        case .guardianLimit(let max?, false): return String(format: lang.localized("invite.error.guardianLimit.theirs"), max)
        case .guardianLimit(nil, _): return lang.localized("invite.error.guardianLimit.full")
        case .network: return lang.localized("invite.error.network")
        case .tooManyAttempts: return lang.localized("invite.error.tooMany")
        case .other: return lang.localized("invite.error.other")
        }
    }

    /// "Tell them to upgrade" is offered when the other person's plan is full.
    var suggestsAskingToUpgrade: Bool {
        if case .planLimit(_, false) = self { return true }
        if case .guardianLimit(_, false) = self { return true }
        return false
    }
}

// MARK: - Presentation gate

/// When RootView shows the sheet: signed in, past the Face ID gate, and asked for.
enum InviteSheetGate {
    static func isPresented(requested: Bool, authState: AuthManager.AuthState, biometricLocked: Bool) -> Bool {
        guard requested, case .loggedIn = authState else { return false }
        return !biometricLocked
    }
}

// MARK: - Sheet

struct InviteAcceptSheet: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var lang = LanguageManager.shared

    /// Prefilled from an invite link or the sign-up invite path; previewed straight away.
    let initialCode: String?

    private let navy = Color(red: 1/255, green: 69/255, blue: 129/255)
    private let ink = Color(red: 14/255, green: 43/255, blue: 74/255)
    private let ink2 = Color(red: 14/255, green: 43/255, blue: 74/255).opacity(0.62)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let cream = Color(red: 252/255, green: 242/255, blue: 218/255)
    private let bg = Color(red: 250/255, green: 247/255, blue: 240/255)

    @State private var code = ""
    @State private var preview: InvitePreviewResponse?
    @State private var accepted: AcceptInviteResponse?
    @State private var failure: InviteFailure?
    @State private var isLoading = false
    /// Guardian's explicit choice to receive SOS alerts as Critical Alerts.
    @State private var criticalAlertConsent = true
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let preview, let accepted {
                        acceptedView(preview: preview, response: accepted)
                    } else if let preview {
                        confirmView(preview)
                    } else {
                        codeEntryView
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle(lang.localized(preview == nil ? "invite.accept.title" : "invite.accept.confirmTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if accepted == nil {
                        Button(lang.localized("common.cancel")) { dismiss() }
                    }
                }
            }
            .task {
                guard code.isEmpty, let initial = initialCode, !initial.isEmpty else { return }
                code = initial
                await loadPreview()
            }
        }
        .interactiveDismissDisabled(isLoading)
    }

    // MARK: Code entry

    private var codeEntryView: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.fill")
                .font(.scaled(size: 32))
                .foregroundStyle(navy.opacity(0.75))
                .padding(.top, 12)

            Text(lang.localized("invite.accept.hint"))
                .font(.scaled(size: 14))
                .foregroundStyle(ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            TextField(lang.localized("wizard.invite.codePlaceholder"), text: $code)
                .font(.scaled(size: 22, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .keyboardType(.asciiCapable) // pinyin/kana keyboards hold letters as marked text
                .autocorrectionDisabled()
                .focused($codeFocused)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                .onChange(of: code) { _, newValue in
                    let cleaned = String(newValue.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(12))
                    if cleaned != newValue { code = cleaned }
                    failure = nil
                }
                .onSubmit { Task { await loadPreview() } }
                .accessibilityIdentifier("invite.code.field")

            if let failure {
                failureView(failure)
            }

            primaryButton(lang.localized("invite.accept.view"), enabled: code.count >= 4) {
                Task { await loadPreview() }
            }
            .accessibilityIdentifier("invite.view")
        }
        .onAppear {
            if (initialCode ?? "").isEmpty { codeFocused = true }
        }
    }

    // MARK: Confirmation (mockup ②)

    private func confirmView(_ preview: InvitePreviewResponse) -> some View {
        let name = Self.inviterName(preview)
        let becomesGuardian = preview.acceptorRole == .guardian
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(AvatarInitial.make(for: name))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .font(.scaled(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(becomesGuardian ? lamp : safe))
                Text(String(format: lang.localized(becomesGuardian ? "invite.accept.headline.beGuardian" : "invite.accept.headline.beProtected"), name))
                    .font(.scaled(size: 18, weight: .semibold))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("invite.headline")
            }

            VStack(alignment: .leading, spacing: 8) {
                if becomesGuardian {
                    permissionRow("invite.accept.youWillSee", "invite.accept.guardian.seeValue", ok: true)
                    permissionRow("invite.accept.whenTheyNeedHelp", "invite.accept.guardian.helpValue", ok: true)
                    permissionRow("invite.accept.youWontSee", "invite.accept.guardian.privateValue", ok: false)
                } else {
                    permissionRow("invite.accept.theyWillSee", "invite.accept.protected.seeValue", ok: true)
                    permissionRow("invite.accept.whenYouNeedHelp", "invite.accept.protected.helpValue", ok: true)
                    permissionRow("invite.accept.theyWontSee", "invite.accept.protected.privateValue", ok: false)
                    Text(lang.localized("invite.accept.removeAnytime"))
                        .font(.scaled(size: 12))
                        .foregroundStyle(ink2)
                        .padding(.top, 2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(bg))

            // Only someone who will receive SOS alerts is asked about Critical Alerts
            if becomesGuardian {
                criticalAlertConsentCard
            }

            if let failure {
                failureView(failure)
            }

            primaryButton(lang.localized("invite.accept.accept"), enabled: true) {
                Task { await accept(preview) }
            }
            .accessibilityIdentifier("invite.accept")

            Button {
                dismiss()
            } label: {
                Text(lang.localized("invite.accept.decline"))
                    .font(.scaled(size: 14))
                    .foregroundStyle(ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .disabled(isLoading)
        }
    }

    private func permissionRow(_ labelKey: String, _ valueKey: String, ok: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.scaled(size: 13))
                .foregroundStyle(ok ? safe : alert)
                .padding(.top, 1)
            Text(permissionText(lang.localized(labelKey), lang.localized(valueKey)))
                .font(.scaled(size: 13))
                .foregroundStyle(ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "**You'll see**: their location…" with the label in bold.
    private func permissionText(_ label: String, _ value: String) -> AttributedString {
        var bold = AttributedString(label)
        bold.inlinePresentationIntent = .stronglyEmphasized
        bold.foregroundColor = ink
        return bold + AttributedString(lang.localized("invite.accept.labelSeparator") + value)
    }

    /// Explains Critical Alerts before the guardian joins; their choice is
    /// stored with the guardian link and can be changed later in Settings.
    private var criticalAlertConsentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $criticalAlertConsent) {
                Label(lang.localized("consent.criticalAlerts.title"), systemImage: "bell.badge.fill")
                    .font(.scaled(size: 15, weight: .semibold))
                    .foregroundStyle(ink)
            }
            .tint(navy)
            Text(lang.localized("consent.criticalAlerts.body"))
                .font(.scaled(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.4), lineWidth: 1))
    }

    // MARK: Accepted

    private func acceptedView(preview: InvitePreviewResponse, response: AcceptInviteResponse) -> some View {
        let name = Self.inviterName(preview)
        let iAmGuardian = (response.acceptorRole ?? preview.acceptorRole.rawValue) == UserRole.guardian.rawValue
        return VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.scaled(size: 48))
                .foregroundStyle(safe)
                .padding(.top, 20)
            Text(String(format: lang.localized(iAmGuardian ? "invite.accept.success.guardian" : "invite.accept.success.protected"), name))
                .font(.scaled(size: 18, weight: .semibold))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("invite.success")
            primaryButton(lang.localized("invite.accept.done"), enabled: true) { dismiss() }
                .padding(.top, 8)
        }
    }

    // MARK: Pieces

    private func failureView(_ failure: InviteFailure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(alert).frame(width: 7, height: 7).padding(.top, 5)
                Text(failure.message)
                    .font(.scaled(size: 13))
                    .foregroundStyle(alert)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("invite.error")
            }
            if failure.suggestsAskingToUpgrade {
                ShareLink(item: lang.localized("invite.error.planLimit.shareText")) {
                    Text(lang.localized("invite.error.planLimit.tellThem") + " ›")
                        .font(.scaled(size: 13, weight: .medium))
                        .foregroundStyle(navy)
                }
                .padding(.leading, 13)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(cream)
                } else {
                    Text(title)
                }
            }
            .font(.scaled(size: 15, weight: .semibold))
            .foregroundStyle(enabled ? cream : Color(.systemGray))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(enabled ? navy : Color(.systemGray5)))
        }
        .disabled(!enabled || isLoading)
    }

    static func inviterName(_ preview: InvitePreviewResponse) -> String {
        let name = (preview.inviterName ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? LanguageManager.shared.localized("invite.accept.someone") : name
    }

    // MARK: Actions

    @MainActor
    private func loadPreview() async {
        guard code.count >= 4, !isLoading else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            let result = try await coordinator.previewInvite(code: code)
            if let problem = InviteFailure(preview: result) {
                failure = problem
            } else {
                preview = result
            }
        } catch {
            failure = InviteFailure(error: error)
        }
    }

    @MainActor
    private func accept(_ preview: InvitePreviewResponse) async {
        isLoading = true
        failure = nil
        defer { isLoading = false }
        do {
            let consent: Bool? = preview.acceptorRole == .guardian ? criticalAlertConsent : nil
            accepted = try await coordinator.acceptInvite(code: preview.code, criticalAlertConsent: consent)
        } catch {
            failure = InviteFailure(error: error)
        }
    }
}
