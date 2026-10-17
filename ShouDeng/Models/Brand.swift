import Foundation

// MARK: - Brand Constants
//
// Single source of truth for brand names. Every user-facing
// reference to the app name MUST come from here or from the
// Localizable.strings keys "app.name" / "app.subtitle".
//
// Banned strings: old brand names must not appear in user-facing code.

enum Brand {
    static let nameEN = "Vela"
    static let nameZH = "守灯"
    static let domain = "velar.care"
    static let supportEmail = "support@velarcare.com"

    /// Primary display title based on locale.
    /// EN/FR → "Vela", ZH → "守灯"
    static func displayTitle(locale: AppLanguage) -> String {
        switch locale {
        case .chinese: return nameZH
        case .english, .french: return nameEN
        }
    }

    /// Secondary subtitle (the "other" name).
    /// EN/FR → "守灯", ZH → "VELA"
    static func displaySubtitle(locale: AppLanguage) -> String {
        switch locale {
        case .chinese: return "VELA"
        case .english, .french: return nameZH
        }
    }
}
