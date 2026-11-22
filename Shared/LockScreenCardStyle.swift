import SwiftUI

// MARK: - Lock-screen card style
//
// Chosen in Settings → Lock screen card. Saved in the App Group (so the widget can read
// it) and also carried in each Live Activity update, which is what makes the card
// redraw when the style changes.
//
// The system cuts a lock-screen Live Activity off at 160 pt. Bigger text therefore
// means fewer rows: every row has a fixed height per text size, and a style only
// offers the rows that fit (`fits`).

struct LockScreenCardStyle: Codable, Hashable {

    enum TextSize: String, Codable, CaseIterable {
        case standard, large, extraLarge
        var scale: CGFloat {
            switch self {
            case .standard: return 1.0
            case .large: return 1.15
            case .extraLarge: return 1.3
            }
        }
    }

    enum Theme: String, Codable, CaseIterable {
        case graphite, navy, midnight, forest, plum, light
        var background: Color {
            switch self {
            case .graphite: return Color(red: 0.145, green: 0.153, blue: 0.169)
            case .navy: return SharedColors.ink
            case .midnight: return Color(red: 0.05, green: 0.05, blue: 0.07)
            case .forest: return Color(red: 0.08, green: 0.22, blue: 0.17)
            case .plum: return Color(red: 0.24, green: 0.11, blue: 0.24)
            case .light: return Color(red: 0.98, green: 0.97, blue: 0.94)
            }
        }
        /// During an SOS the dark backgrounds turn a shade warmer: noticeable to the
        /// person, not a red flag to someone glancing at the phone
        func background(alert: Bool) -> Color {
            guard alert else { return background }
            switch self {
            case .graphite: return Color(red: 0.165, green: 0.145, blue: 0.141)
            case .navy: return Color(red: 0.13, green: 0.12, blue: 0.2)
            case .midnight: return Color(red: 0.09, green: 0.06, blue: 0.07)
            case .forest, .plum, .light: return background
            }
        }
        var isLight: Bool { self == .light }
        /// Main text
        var primary: Color { isLight ? SharedColors.ink : .white }
        /// Labels and secondary text
        var secondary: Color { isLight ? SharedColors.ink.opacity(0.62) : .white.opacity(0.7) }
    }

    enum Accent: String, Codable, CaseIterable {
        case slate, lantern, gold, teal, green, sky
        var color: Color {
            switch self {
            case .slate: return Color(red: 0.58, green: 0.64, blue: 0.72)
            case .lantern: return SharedColors.lamp
            case .gold: return Color(red: 0.91, green: 0.64, blue: 0.24)
            case .teal: return Color(red: 0.18, green: 0.62, blue: 0.66)
            case .green: return Color(red: 0.25, green: 0.65, blue: 0.43)
            case .sky: return Color(red: 0.35, green: 0.6, blue: 0.95)
            }
        }
    }

    /// Optional rows of the protected person's card (the header is always there)
    enum Section: String, Codable, CaseIterable {
        case checkIn, latest, medical, actions
    }

    var textSize: TextSize = .standard
    var theme: Theme = .graphite
    var accent: Accent = .slate
    var sections: [Section] = [.checkIn, .latest, .actions]

    static let standard = LockScreenCardStyle()

    // MARK: Calm status colours
    //
    // Buttons and status text use dimmed colours on a tinted background instead of
    // solid red / green, so the lock screen stays quiet. Same meaning on every theme.

    enum Tone { case sos, safe, warn, info }

    /// Text and icon colour of a tone on this card's background
    func ink(_ tone: Tone) -> Color {
        let light = theme.isLight
        switch tone {
        case .sos:  return light ? Color(red: 0.56, green: 0.29, blue: 0.25) : Color(red: 0.89, green: 0.70, blue: 0.66)
        case .safe: return light ? Color(red: 0.25, green: 0.38, blue: 0.31) : Color(red: 0.72, green: 0.80, blue: 0.75)
        case .warn: return light ? Color(red: 0.48, green: 0.37, blue: 0.16) : Color(red: 0.84, green: 0.76, blue: 0.61)
        case .info: return light ? Color(red: 0.27, green: 0.34, blue: 0.42) : Color(red: 0.73, green: 0.77, blue: 0.82)
        }
    }

    /// Background of a button / chip in a tone
    func fill(_ tone: Tone) -> Color {
        let base: Color
        switch tone {
        case .sos:  base = Color(red: 0.79, green: 0.54, blue: 0.50)
        case .safe: base = Color(red: 0.58, green: 0.67, blue: 0.61)
        case .warn: base = Color(red: 0.78, green: 0.67, blue: 0.45)
        case .info: base = Color(red: 0.58, green: 0.64, blue: 0.72)
        }
        return base.opacity(theme.isLight ? 0.22 : 0.2)
    }

    func with(textSize: TextSize) -> LockScreenCardStyle {
        var copy = self
        copy.textSize = textSize
        return copy
    }

    // MARK: Fit (160 pt lock-screen limit)

    static let heightLimit: CGFloat = 160
    static let verticalPadding: CGFloat = 10
    static let rowSpacing: CGFloat = 6

    var s: CGFloat { textSize.scale }
    var headerHeight: CGFloat { 26 * s }

    func height(of section: Section) -> CGFloat {
        switch section {
        case .checkIn, .latest: return 20 * s
        case .medical: return 24 * s
        case .actions: return 38 * s
        }
    }

    /// Height of the protected card with these rows
    func protectedHeight(_ rows: [Section]) -> CGFloat {
        headerHeight + rows.map(height(of:)).reduce(0, +)
            + CGFloat(rows.count) * Self.rowSpacing + 2 * Self.verticalPadding
    }

    func fits(_ rows: [Section]) -> Bool { protectedHeight(rows) <= Self.heightLimit }

    /// The rows the card draws: the chosen ones in a fixed order, dropping the least
    /// important if they don't fit (a style saved with a smaller text size).
    var visibleSections: [Section] {
        var rows = Section.allCases.filter(sections.contains)
        for drop in [Section.medical, .latest, .checkIn, .actions] where !fits(rows) {
            rows.removeAll { $0 == drop }
        }
        return rows
    }

    /// Guardian card: header, as many person rows as fit, call button
    var guardianHeaderHeight: CGFloat { 24 * s }
    var guardianRowHeight: CGFloat { 20 * s }
    var guardianButtonHeight: CGFloat { 32 * s }
    /// 3 at standard size, 2 at large, 1 at extra large
    var guardianPersonRows: Int {
        let free = Self.heightLimit - 2 * Self.verticalPadding - guardianHeaderHeight - guardianButtonHeight - 2 * Self.rowSpacing
        return max(1, min(3, Int((free + Self.rowSpacing) / (guardianRowHeight + Self.rowSpacing))))
    }

    // MARK: Storage (App Group)

    private static let key = "lockscreen_card_style"

    static var stored: LockScreenCardStyle {
        guard let data = UserDefaults(suiteName: WidgetDataStore.appGroupId)?.data(forKey: key),
              let style = try? JSONDecoder().decode(LockScreenCardStyle.self, from: data) else { return .standard }
        return style
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: WidgetDataStore.appGroupId)?.set(data, forKey: Self.key)
    }
}
