import SwiftUI

/// Row under the protected person's status: Home Safe + text size.
///
/// The language button that used to sit here was removed after user testing: it was
/// tapped by accident (the app suddenly turned French), its label was unclear, and
/// it crashed on languages without a label. Language is chosen in Settings, on the
/// login screen and during onboarding.
struct QuickPillRow: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @ObservedObject private var fontScale = FontScaleManager.shared
    @State private var showFontSizes = false

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let offWhiteBg = Color(red: 251/255, green: 248/255, blue: 241/255)

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            // Home Safe
            HomeSafePill()
                .coachMark(CoachAnchor.homeSafe)

            // Text size — written out ("字体大小：标准"), not "Aa S"
            Button {
                showFontSizes = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "textformat.size")
                        // The symbol is localized ("大小" in Chinese) and repeated the label; keep "AA"
                        .environment(\.locale, Locale(identifier: "en"))
                        .font(.system(size: 12))
                    Text(FontSizeSheet.buttonTitle(lang: lang, level: fontScale.level))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(offWhiteBg)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(ink.opacity(0.1), lineWidth: 1)
                )
            }
            .accessibilityLabel(FontSizeSheet.buttonTitle(lang: lang, level: fontScale.level))

            Spacer()
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showFontSizes) {
            FontSizeSheet()
                .presentationDetents([.medium, .large])
        }
    }
}

/// Pick a text size from four large, labelled rows, each previewed at its own size.
struct FontSizeSheet: View {
    @ObservedObject private var lang = LanguageManager.shared
    @AppStorage(HomeStyle.storageKey) private var homeStyle = HomeStyle.standard.rawValue
    @ObservedObject private var fontScale = FontScaleManager.shared
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)

    /// "字体大小：标准" / "Text size: Standard"
    static func buttonTitle(lang: LanguageManager, level: FontScaleLevel) -> String {
        String(format: lang.localized("fontScale.button.current"), level.label)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(FontScaleLevel.allCases, id: \.self) { level in
                        Button {
                            fontScale.level = level
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(level.label)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(ink)
                                    Text(lang.localized("fontScale.sample"))
                                        .font(.system(size: 15 * level.scale))
                                        .foregroundStyle(ink.opacity(0.75))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                }
                                Spacer()
                                if fontScale.level == level {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(safe)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(fontScale.level == level ? safe.opacity(0.08) : Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(fontScale.level == level ? safe : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(fontScale.level == level ? .isSelected : [])
                    }
                }
                .padding(16)

                // Large text reads best on the simple home
                if (fontScale.level == .extraLarge || fontScale.level == .huge),
                   homeStyle == HomeStyle.standard.rawValue {
                    Button {
                        homeStyle = HomeStyle.simple.rawValue
                        dismiss()
                    } label: {
                        Label(lang.localized("homeStyle.suggest"), systemImage: "textformat.size.larger")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(safe)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 14).stroke(safe, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
            }
            .navigationTitle(lang.localized("fontScale.button"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lang.localized("settings.action.ok")) { dismiss() }
                }
            }
        }
    }
}
