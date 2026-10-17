import SwiftUI

// MARK: - Onboarding: 3-Screen Disclosure Flow
//
// From revised plan, section 5.3:
//   - One concept per screen, not a single large popup
//   - Button text "我明白了" not "确定"
//   - Cannot be skipped
//   - Each tap logs consent with copy version

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage("hasCompletedOnboardingOnce") private var hasCompletedOnce = false
    @State private var currentPage = UserDefaults.standard.integer(forKey: "debug_onboarding_page")
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Design system
    private let inkDeep = Color(red: 8/255, green: 15/255, blue: 27/255)
    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
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

    private var compactOnboardingLayout: some View {
        VStack(spacing: 0) {
            onboardingTopBar
            PageIndicator(
                count: screens.count,
                current: currentPage,
                activeColor: lamp,
                inactiveColor: lamp.opacity(0.25)
            )
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

    private var duoOnboardingLayout: some View {
        HStack(spacing: 0) {
            // LEFT: Icon + Title
            VStack(spacing: 0) {
                onboardingTopBar
                    .padding(.horizontal, 28)
                PageIndicator(
                    count: screens.count,
                    current: currentPage,
                    activeColor: lamp,
                    inactiveColor: lamp.opacity(0.25)
                )
                .padding(.top, 16)
                Spacer()
                Image(systemName: screens[currentPage].icon)
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(lamp)
                    .frame(height: 70)
                Text(screens[currentPage].title)
                    .font(.system(size: 26, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 20)
                    .padding(.horizontal, 32)
                Spacer()
                Spacer()
            }
            .frame(width: 445)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)

            // RIGHT: Body + Button
            VStack(spacing: 0) {
                Spacer()
                disclaimerBody(screens[currentPage].body)
                    .padding(.horizontal, 36)
                Spacer()
                actionButton(screens[currentPage])
                    .padding(.horizontal, 36)
                    .padding(.bottom, 48)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Shared Top Bar

    private var onboardingTopBar: some View {
        HStack {
            if hasCompletedOnce {
                Button {
                    skipToHome()
                } label: {
                    Text(lang.current == .chinese ? "跳过" : "Skip")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }

            Spacer()

            LanguageSwitcher(style: .dark)
        }
        .padding(.top, 8)
        .padding(.leading, 4)
    }

    private func skipToHome() {
        withAnimation {
            isComplete = true
        }
    }

    // MARK: - Screen Content

    private func screenContent(_ screen: DisclaimerCopy.Onboarding.Screen) -> some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: screen.icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(lamp)
                .frame(height: 60)

            // Title — no truncation
            Text(screen.title)
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.8)

            // Body with inline SF Symbols
            disclaimerBody(screen.body)
        }
    }

    // MARK: - Disclaimer Body (SF Symbol lines)

    /// Parses body text where each paragraph may start with an SF Symbol name
    /// (e.g. "phone.fill In an emergency..."). Renders icon + text pairs.
    private func disclaimerBody(_ body: String) -> some View {
        let paragraphs = body.components(separatedBy: "\n\n")
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                let parts = Self.parseSymbolLine(paragraph)
                HStack(alignment: .top, spacing: 12) {
                    if let symbol = parts.symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(lamp)
                            .frame(width: 24, alignment: .center)
                            .padding(.top, 2)
                    }
                    Text(parts.text)
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Splits "phone.fill Some text" into (symbol: "phone.fill", text: "Some text").
    /// If no known symbol prefix, returns nil symbol and the full text.
    private static let knownSymbols: Set<String> = [
        "phone.fill", "person.2.fill", "wifi.exclamationmark",
        "eye.slash", "hand.raised", "exclamationmark.triangle"
    ]

    private static func parseSymbolLine(_ line: String) -> (symbol: String?, text: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Check if line starts with a known SF Symbol name
        for sym in knownSymbols {
            if trimmed.hasPrefix(sym + " ") {
                let text = String(trimmed.dropFirst(sym.count + 1))
                return (sym, text)
            }
        }
        return (nil, trimmed)
    }

    // MARK: - Action Button

    private func actionButton(_ screen: DisclaimerCopy.Onboarding.Screen) -> some View {
        Button {
            // Log consent
            ConsentLogger.shared.logOnboardingScreen(screen.id)
            AuditLog.record(event: .disclaimerAccepted, version: DisclaimerCopy.Onboarding.version)

            if currentPage < screens.count - 1 {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPage += 1
                }
            } else {
                // Mark disclaimers accepted; services start after login
                hasCompletedOnce = true
                withAnimation {
                    isComplete = true
                }
            }
        } label: {
            Text(screen.buttonTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(inkDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(lamp)
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
    }
}
