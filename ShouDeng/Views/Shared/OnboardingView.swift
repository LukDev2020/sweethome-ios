import SwiftUI

// MARK: - Onboarding: what Beaconify is + 3 disclosure screens
//
//   - First page: what it can do — family care, work safety (delivery / courier rider,
//     ride-hailing driver), looking after family. Any of them together; the sign-up
//     starts with them ticked and the setup after it asks only what they need.
//     "Family sent me an invite" takes the sign-up straight to the invite code.
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
        // A crew / partner link opened the app: Work safety starts ticked
        .onAppear {
            if coordinator.pendingSignupIntent?.rider == true || coordinator.pendingCrewCode != nil { intro.work = true }
        }
    }

    // MARK: - Compact Layout

    @ViewBuilder private var compactOnboardingLayout: some View {
        if showingIntro {
            VStack(spacing: 0) {
                onboardingTopBar
                progressDots
                    .padding(.top, 16)
                ScrollView {
                    OnboardingIntroPage(choice: $intro)
                        .padding(.top, 14)
                }
                .scrollBounceBehavior(.basedOnSize)
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
            // Unfolded: the choices on the left, Continue on the right
            FoldSplitView(dividerColor: .white.opacity(0.08)) {
                VStack(spacing: 0) {
                    onboardingTopBar.padding(.horizontal, 12)
                    progressDots.padding(.top, 16)
                    ScrollView {
                        OnboardingIntroPage(choice: $intro)
                            .padding(24)
                    }
                }
            } trailing: {
                VStack(spacing: 0) {
                    Spacer()
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

    // MARK: - Intro (family care / work / looking after family)

    @State private var intro = IntroChoice()

    /// What the first page passes on to the sign-up
    private func applyIntro() {
        let link = coordinator.pendingSignupIntent
        // A crew / partner link already chose work: keep it, add the rest
        let linkChoseWork = link?.partnerCode != nil || coordinator.pendingCrewCode != nil
        guard intro.any || linkChoseWork else {
            coordinator.pendingSignupIntent = nil
            return
        }
        coordinator.pendingSignupIntent = SignupIntent(
            rider: intro.work || linkChoseWork, partnerCode: link?.partnerCode,
            family: intro.care, guardian: intro.guardian, invite: intro.invite)
        if intro.work { UserDefaults.standard.set(intro.workKind, forKey: AppCoordinator.workKindKey) }
    }

    private var introContinueButton: some View {
        Button {
            applyIntro()
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

// MARK: - Intro page: family care, work safety, looking after family

/// The first page's choices (any of them together)
struct IntroChoice: Equatable {
    var care = false
    var work = false
    var guardian = false
    /// "rider" (delivery, courier) or "driver" (ride-hailing)
    var workKind = "rider"
    /// "Family sent me an invite"
    var invite = false
    var any: Bool { care || work || guardian || invite }
}

struct OnboardingIntroPage: View {
    @Binding var choice: IntroChoice
    @ObservedObject private var lang = LanguageManager.shared

    static let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    static let riderGreen = Color(red: 63/255, green: 168/255, blue: 120/255)
    static let guardianBlue = Color(red: 110/255, green: 150/255, blue: 205/255)

    var body: some View {
        VStack(spacing: 10) {
            // Invited by family: the fastest way in
            Button {
                choice.invite.toggle()
                if choice.invite { choice.care = false; choice.work = false; choice.guardian = false }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.open.fill")
                        .font(.scaled(size: 16, weight: .semibold))
                    Text(lang.localized("intro.invite"))
                        .font(.scaled(size: 15, weight: .semibold))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: choice.invite ? "checkmark.circle.fill" : "chevron.right")
                        .font(.scaled(size: 15, weight: .semibold))
                }
                .foregroundStyle(Self.lamp)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Self.lamp.opacity(choice.invite ? 0.22 : 0.1)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(choice.invite ? Self.lamp : .clear, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.intro.invite")
            .accessibilityAddTraits(choice.invite ? .isSelected : [])

            Text(lang.localized("intro.title"))
                .font(.scaled(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Text(lang.localized("intro.hint"))
                .font(.scaled(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)

            Card(icon: "house.and.flag.fill", color: Self.lamp,
                 titleKey: "intro.care.title", taglineKey: "intro.care.tagline", forKey: "intro.family.for",
                 selected: choice.care) { toggle(\.care) }
                .accessibilityIdentifier("onboarding.intro.family")
            Card(icon: choice.workKind == "driver" ? "car.fill" : "bicycle", color: Self.riderGreen,
                 titleKey: "intro.work.title", taglineKey: "intro.work.tagline", forKey: "intro.rider.for",
                 selected: choice.work) { toggle(\.work) } extra: {
                if choice.work { workKinds }
            }
            .accessibilityIdentifier("onboarding.intro.rider")
            Card(icon: "person.2.fill", color: Self.guardianBlue,
                 titleKey: "intro.guardian.title", taglineKey: "intro.guardian.tagline", forKey: "intro.guardian.for",
                 selected: choice.guardian) { toggle(\.guardian) }
                .accessibilityIdentifier("onboarding.intro.guardian")
        }
    }

    private func toggle(_ key: WritableKeyPath<IntroChoice, Bool>) {
        withAnimation(.easeInOut(duration: 0.15)) {
            choice[keyPath: key].toggle()
            if choice[keyPath: key] { choice.invite = false }
        }
    }

    /// Delivery / courier rider or ride-hailing driver
    private var workKinds: some View {
        HStack(spacing: 8) {
            ForEach(["rider", "driver"], id: \.self) { kind in
                let on = choice.workKind == kind
                Button { choice.workKind = kind } label: {
                    Text(lang.localized("intro.work.kind.\(kind)"))
                        .font(.scaled(size: 13, weight: .semibold))
                        .foregroundStyle(on ? Color.black.opacity(0.85) : .white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(on ? Self.riderGreen : .white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("onboarding.intro.work.\(kind)")
            }
            Spacer(minLength: 0)
        }
    }

    /// One choice: a tappable card, ticked when chosen
    fileprivate struct Card<Extra: View>: View {
        let icon: String
        let color: Color
        let titleKey: String
        let taglineKey: String
        /// "Good for: …"
        let forKey: String
        let selected: Bool
        let action: () -> Void
        @ViewBuilder var extra: () -> Extra
        @ObservedObject private var lang = LanguageManager.shared

        init(icon: String, color: Color, titleKey: String, taglineKey: String, forKey: String,
             selected: Bool, action: @escaping () -> Void, @ViewBuilder extra: @escaping () -> Extra) {
            self.icon = icon; self.color = color; self.titleKey = titleKey; self.taglineKey = taglineKey
            self.forKey = forKey; self.selected = selected; self.action = action; self.extra = extra
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: action) {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.scaled(size: 20, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(color.opacity(0.16)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.localized(titleKey))
                                .font(.scaled(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                            Text(lang.localized(taglineKey))
                                .font(.scaled(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(lang.localized(forKey))
                                .font(.scaled(size: 12))
                                .foregroundStyle(color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.scaled(size: 22))
                            .foregroundStyle(selected ? color : .white.opacity(0.25))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                extra()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(color.opacity(selected ? 0.2 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? color : .white.opacity(0.1), lineWidth: selected ? 2 : 1)
            )
        }
    }
}

extension OnboardingIntroPage.Card where Extra == EmptyView {
    init(icon: String, color: Color, titleKey: String, taglineKey: String, forKey: String,
         selected: Bool, action: @escaping () -> Void) {
        self.init(icon: icon, color: color, titleKey: titleKey, taglineKey: taglineKey, forKey: forKey,
                  selected: selected, action: action, extra: { EmptyView() })
    }
}
