import SwiftUI

// MARK: - Before you look after someone (guardian, once per version)
//
// The three first-launch screens are shown before sign-in, when the role isn't known
// yet. A guardian confirms this once after signing in: alerts can fail, they are not a
// professional responder, and the person must have agreed. Logged like the others.

struct GuardianDutyView: View {
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage("guardian_duty_version") private var acceptedVersion = ""

    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    var body: some View {
        ZStack {
            inkDeep.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "person.2.wave.2")
                        .font(.scaled(size: 44, weight: .light))
                        .foregroundStyle(lamp)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    Text(lang.localized("duty.title"))
                        .font(.scaled(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    point("exclamationmark.triangle", "duty.point.alerts")
                    point("person.crop.circle.badge.questionmark", "duty.point.notResponder")
                    point("hand.raised", "duty.point.consent")
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    ConsentLogger.shared.logGuardianDuty()
                    acceptedVersion = DisclaimerCopy.GuardianDuty.version
                } label: {
                    Text(lang.localized("duty.button"))
                        .font(.scaled(size: 15, weight: .medium))
                        .foregroundStyle(inkDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(lamp)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
                .background(inkDeep)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    private func point(_ icon: String, _ key: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.scaled(size: 18))
                .foregroundStyle(lamp)
                .frame(width: 26)
            Text(lang.localized(key))
                .font(.scaled(size: 16))
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - After sign-in: Terms (if not agreed to this version), then guardian duties

struct ComplianceGateView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @AppStorage("terms_accepted_version") private var termsVersion = ""

    static func isNeeded(role: UserRole, isDemo: Bool) -> Bool {
        guard !isDemo else { return false }
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "terms_accepted_version") != DisclaimerCopy.Terms.version { return true }
        return role == .guardian && defaults.string(forKey: "guardian_duty_version") != DisclaimerCopy.GuardianDuty.version
    }

    var body: some View {
        if termsVersion != DisclaimerCopy.Terms.version {
            TermsUpdateView()
        } else {
            GuardianDutyView()
        }
    }
}

/// Accounts created before the Terms checkbox (or after a Terms update) agree here.
struct TermsUpdateView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage("terms_accepted_version") private var termsVersion = ""

    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    var body: some View {
        ZStack {
            inkDeep.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "doc.text")
                    .font(.scaled(size: 44, weight: .light))
                    .foregroundStyle(lamp)
                Text(lang.localized("terms.update.title"))
                    .font(.scaled(size: 24, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(lang.localized("terms.update.body"))
                    .font(.scaled(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                TermsAgreementRow(tint: .white)
                    .environmentObject(coordinator)
                    .padding(.top, 8)
                Spacer()
                // Agreeing is the checkbox; this only shows the next step once it is ticked
                Text(lang.localized(termsVersion == DisclaimerCopy.Terms.version ? "terms.update.thanks" : "terms.update.required"))
                    .font(.scaled(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }
}
