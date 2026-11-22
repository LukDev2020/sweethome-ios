import SwiftUI

// MARK: - Onboarding: what Beaconify is + 3 disclosure screens
//
//   - First page: the two ways to use it — family safety and Rider (delivery /
//     ride-hailing). Tapping Rider makes the sign-up start as a rider.
//   - Then one concept per screen, not a single large popup; "我明白了" not "确定"
//   - Each tap logs consent with copy version (sent to the server after sign-in)
//   - Skip on every page: the skipped screens are logged as "skipped". The Terms
//     at sign-in and the SOS disclosure before the first SOS still apply.

struct OnboardingView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showDemoPicker = false
    @Binding var isComplete: Bool
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage("hasCompletedOnboardingOnce") private var hasCompletedOnce = false
    @AppStorage("onboarding_copy_version") private var acceptedVersion = ""
    /// The two-way intro (family / Rider) comes before the disclosure screens
    @State private var showingIntro = UserDefaults.standard.object(forKey: "debug_onboarding_page") == nil
    @State private var currentPage = UserDefaults.standard.integer(forKey: "debug_onboarding_page")
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Design system
    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let ink = Color.appInk
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private let paper = Color(red: 236/255, green: 238/255, blue: 240/255)

    private var screens: [DisclaimerCopy.Onboarding.Screen] {
        DisclaimerCopy.Onboarding.screens(for: lang.current)
    }

    var body: some View {
        ZStack {
            inkDeep.ignoresSafeArea(.all, edges: .all)

            if sizeClass == .regular {
                duoOnboardingLayout
            } else {
                compactOnboardingLayout
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Compact Layout

    @ViewBuilder private var compactOnboardingLayout: some View {
        if showingIntro {
            VStack(spacing: 0) {
                onboardingTopBar
                progressDots
                    .padding(.top, 16)
                OnboardingIntroPage(riderChosen: riderChosen, choose: chooseIntro)
                    .padding(.top, 14)
                introContinueButton
                    .padding(.top, 14)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
        } else {
            disclosureCompactLayout
        }
    }

    private var disclosureCompactLayout: some View {
        VStack(spacing: 0) {
            onboardingTopBar
            progressDots
                .padding(.top, 16)
            Spacer()
                .frame(maxHeight: 48)
            screenContent(screens[currentPage])
            Spacer()
            actionButton(screens[currentPage])
                .padding(.bottom, 48)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Duo Layout (Inner Screen)

    @ViewBuilder private var duoOnboardingLayout: some View {
        if showingIntro {
            // Unfolded: family on the left, Rider on the right
            FoldSplitView(dividerColor: .white.opacity(0.08)) {
                VStack(spacing: 0) {
                    onboardingTopBar.padding(.horizontal, 12)
                    progressDots.padding(.top, 16)
                    OnboardingIntroPage.FamilyHalf(selected: riderChosen == false) { chooseIntro(rider: false) }
                        .padding(24)
                }
            } trailing: {
                VStack(spacing: 0) {
                    OnboardingIntroPage.RiderHalf(selected: riderChosen == true) { chooseIntro(rider: true) }
                        .padding(24)
                    introContinueButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }
        } else {
            disclosureDuoLayout
        }
    }

    private var disclosureDuoLayout: some View {
        FoldSplitView(dividerColor: .white.opacity(0.08)) {
            // LEFT: Icon + Title
            VStack(spacing: 0) {
                onboardingTopBar
                    .padding(.horizontal, 28)
                progressDots
                    .padding(.top, 16)
                Spacer()
                Image(systemName: screens[currentPage].icon)
                    .font(.scaled(size: 56, weight: .light))
                    .foregroundStyle(lamp)
                    .frame(height: 70)
                Text(screens[currentPage].title)
                    .font(.scaled(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                    .padding(.horizontal, 32)
                Spacer()
                Spacer()
            }
        } trailing: {
            // RIGHT: Body + Button
            VStack(spacing: 0) {
                Spacer()
                Text(screens[currentPage].body)
                    .font(.scaled(size: 16))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(6)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 36)
                Spacer()
                actionButton(screens[currentPage])
                    .padding(.horizontal, 36)
                    .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Shared Top Bar

    private var onboardingTopBar: some View {
        HStack {
            Button {
                skipToHome()
            } label: {
                Text(lang.localized("onboarding.skip"))
                    .font(.scaled(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .accessibilityIdentifier("onboarding.skip")

            Spacer()

            // D-07: Language switcher top-right, matching login screen
            HStack(spacing: 2) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .accessibilityLabel(lang.localized("settings.language"))
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Button {
                        lang.choose(language)
                    } label: {
                        Text(language.displayName)
                            .font(.scaled(size: 12))
                            .foregroundStyle(lang.current == language ? .white : .white.opacity(0.35))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                lang.current == language
                                    ? Capsule().fill(.white.opacity(0.15))
                                    : nil
                            )
                    }
                }
            }
            .padding(.trailing, 16)
        }
        .padding(.top, 8)
        .padding(.leading, 4)
    }

    /// Skip from any page. The screens not shown are logged as skipped (not as
    /// agreed); this version isn't shown again.
    private func skipToHome() {
        let firstUnseen = showingIntro ? 0 : currentPage
        for screen in screens.dropFirst(firstUnseen) {
            ConsentLogger.shared.logOnboardingScreenSkipped(screen.id)
        }
        hasCompletedOnce = true
        acceptedVersion = DisclaimerCopy.Onboarding.version
        withAnimation {
            isComplete = true
        }
    }

    // MARK: - Intro (family / Rider)

    /// nil: nothing tapped yet; true: Rider; false: family
    private var riderChosen: Bool? {
        guard introTapped else { return nil }
        return coordinator.pendingSignupIntent?.rider == true
    }
    @State private var introTapped = false

    private func chooseIntro(rider: Bool) {
        introTapped = true
        if rider {
            // The sign-up starts as a rider (same as a partner link without a partner)
            coordinator.pendingSignupIntent = SignupIntent(rider: true,
                                                           partnerCode: coordinator.pendingSignupIntent?.partnerCode)
        } else if coordinator.pendingSignupIntent?.partnerCode == nil, coordinator.pendingCrewCode == nil {
            // A crew / partner link already chose Rider: keep it
            coordinator.pendingSignupIntent = nil
        }
    }

    private var introContinueButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { showingIntro = false }
        } label: {
            Text(lang.localized("intro.continue"))
                .font(.scaled(size: 15, weight: .medium))
                .foregroundStyle(inkDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(lamp)
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
        .accessibilityIdentifier("onboarding.intro.continue")
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        // The intro is the first dot
        let current = showingIntro ? 0 : currentPage + 1
        return HStack(spacing: 8) {
            ForEach(0..<(screens.count + 1), id: \.self) { i in
                Circle()
                    .fill(i <= current ? lamp : lamp.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
    }

    // MARK: - Screen Content

    private func screenContent(_ screen: DisclaimerCopy.Onboarding.Screen) -> some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: screen.icon)
                .font(.scaled(size: 44, weight: .light))
                .foregroundStyle(lamp)
                .frame(height: 60)

            // Title
            Text(screen.title)
                .font(.scaled(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            // Body
            Text(screen.body)
                .font(.scaled(size: 16))
                .foregroundStyle(.white.opacity(0.75))
                .lineSpacing(6)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Action Button

    private func actionButton(_ screen: DisclaimerCopy.Onboarding.Screen) -> some View {
        VStack(spacing: 10) {
            primaryButton(screen)
            // Last page: Explore Mode without an account (disclaimers still apply
            // before any real sign-up — the demo sends nothing)
            if currentPage == screens.count - 1 {
                Button {
                    showDemoPicker = true
                } label: {
                    Label(LanguageManager.shared.localized("explore.entry.button"), systemImage: "sparkles")
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(lamp)
                }
                .sheet(isPresented: $showDemoPicker) {
                    DemoRolePickerView()
                }
            }
        }
    }

    private func primaryButton(_ screen: DisclaimerCopy.Onboarding.Screen) -> some View {
        Button {
            // Log consent
            ConsentLogger.shared.logOnboardingScreen(screen.id)

            if currentPage < screens.count - 1 {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPage += 1
                }
            } else {
                // Mark disclaimers accepted (this version); services start after login
                hasCompletedOnce = true
                acceptedVersion = DisclaimerCopy.Onboarding.version
                withAnimation {
                    isComplete = true
                }
            }
        } label: {
            Text(screen.buttonTitle)
                .font(.scaled(size: 15, weight: .medium))
                .foregroundStyle(inkDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(lamp)
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
    }
}

// MARK: - Intro page: half family safety, half Rider

struct OnboardingIntroPage: View {
    /// nil: nothing chosen yet
    let riderChosen: Bool?
    let choose: (Bool) -> Void
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        VStack(spacing: 10) {
            Text(lang.localized("intro.title"))
                .font(.scaled(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(lang.localized("intro.hint"))
                .font(.scaled(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)
            FamilyHalf(selected: riderChosen == false) { choose(false) }
            RiderHalf(selected: riderChosen == true) { choose(true) }
        }
    }

    static let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    static let riderGreen = Color(red: 63/255, green: 168/255, blue: 120/255)

    struct FamilyHalf: View {
        let selected: Bool
        let action: () -> Void
        var body: some View {
            Half(icon: "house.and.flag.fill", color: OnboardingIntroPage.lamp,
                 titleKey: "intro.family.title", taglineKey: "intro.family.tagline",
                 bulletKeys: ["intro.family.b1", "intro.family.b2", "intro.family.b3"],
                 forKey: "intro.family.for", selected: selected, action: action)
                .accessibilityIdentifier("onboarding.intro.family")
        }
    }

    struct RiderHalf: View {
        let selected: Bool
        let action: () -> Void
        var body: some View {
            Half(icon: "bicycle", color: OnboardingIntroPage.riderGreen,
                 titleKey: "intro.rider.title", taglineKey: "intro.rider.tagline",
                 bulletKeys: ["intro.rider.b1", "intro.rider.b2", "intro.rider.b3"],
                 forKey: "intro.rider.for", selected: selected, action: action)
                .accessibilityIdentifier("onboarding.intro.rider")
        }
    }

    /// One half: a tappable card that fills its share of the page
    private struct Half: View {
        let icon: String
        let color: Color
        let titleKey: String
        let taglineKey: String
        let bulletKeys: [String]
        /// "Good for: …" at the bottom of the card
        let forKey: String
        let selected: Bool
        let action: () -> Void
        @ObservedObject private var lang = LanguageManager.shared

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.scaled(size: 22, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill(color.opacity(0.16)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.localized(titleKey))
                                .font(.scaled(size: 19, weight: .bold))
                                .foregroundStyle(.white)
                            Text(lang.localized(taglineKey))
                                .font(.scaled(size: 13, weight: .medium))
                                .foregroundStyle(color)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.scaled(size: 22))
                            .foregroundStyle(selected ? color : .white.opacity(0.25))
                    }
                    ForEach(bulletKeys, id: \.self) { key in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(color).frame(width: 5, height: 5).offset(y: -2)
                            Text(lang.localized(key))
                                .font(.scaled(size: 14))
                                .foregroundStyle(.white.opacity(0.82))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Label(lang.localized(forKey), systemImage: "person.2.fill")
                        .font(.scaled(size: 13, weight: .medium))
                        .foregroundStyle(color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(color.opacity(0.14)))
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [color.opacity(selected ? 0.26 : 0.14), color.opacity(0.04)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(selected ? color : .white.opacity(0.1), lineWidth: selected ? 2 : 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}
