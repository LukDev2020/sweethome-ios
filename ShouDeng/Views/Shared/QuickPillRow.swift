import SwiftUI

struct QuickPillRow: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @ObservedObject private var fontScale = FontScaleManager.shared

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let offWhiteBg = Color(red: 251/255, green: 248/255, blue: 241/255)

    private let languages: [AppLanguage] = [.english, .chinese, .french]
    private let langLabels = ["EN", "\u{4E2D}\u{6587}", "FR"]
    private let fontLevels: [FontScaleLevel] = [.standard, .large, .extraLarge, .huge]
    private let fontLabels = ["S", "M", "L", "XL"]

    var body: some View {
        HStack(spacing: 8) {
            Spacer()

            // Home Safe
            HomeSafePill()

            // Language pill
            Button {
                let currentIdx = languages.firstIndex(of: lang.current) ?? 0
                let nextIdx = (currentIdx + 1) % languages.count
                lang.current = languages[nextIdx]
            } label: {
                let idx = languages.firstIndex(of: lang.current) ?? 0
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 12))
                    Text(langLabels[idx])
                        .font(.system(size: 12, weight: .semibold))
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

            // Font size pill
            Button {
                let currentIdx = fontLevels.firstIndex(of: fontScale.level) ?? 0
                let nextIdx = (currentIdx + 1) % fontLevels.count
                fontScale.level = fontLevels[nextIdx]
            } label: {
                let idx = fontLevels.firstIndex(of: fontScale.level) ?? 0
                HStack(spacing: 5) {
                    Text("Aa")
                        .font(.system(size: 12, weight: .medium))
                    Text(fontLabels[idx])
                        .font(.system(size: 12, weight: .semibold))
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

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
