import SwiftUI

// MARK: - Language Switcher
//
// Shared EN/中/FR control used on onboarding and login screens.
// Anchored top-right with 16pt trailing inset.

struct LanguageSwitcher: View {
    enum Style {
        case dark   // White text on dark background (onboarding)
        case light  // Navy text on light background (login)
    }

    var style: Style = .light
    @ObservedObject private var lang = LanguageManager.shared

    private var activeColor: Color {
        style == .dark ? .white : Color(red: 1/255, green: 69/255, blue: 129/255)
    }

    private var inactiveColor: Color {
        style == .dark ? .white.opacity(0.35) : Color(red: 14/255, green: 43/255, blue: 74/255).opacity(0.4)
    }

    private var pillColor: Color {
        style == .dark ? .white.opacity(0.15) : Color(red: 1/255, green: 69/255, blue: 129/255).opacity(0.09)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppLanguage.allCases, id: \.self) { language in
                Button {
                    lang.current = language
                } label: {
                    Text(language.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(lang.current == language ? activeColor : inactiveColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            lang.current == language
                                ? Capsule().fill(pillColor)
                                : nil
                        )
                }
            }
        }
        .padding(.trailing, 16)
    }
}
