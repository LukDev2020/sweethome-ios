import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case chinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"   // Hong Kong, Macao, Taiwan
    case french = "fr"

    var displayName: String {
        switch self {
        case .english: return "EN"
        case .chinese: return "简"
        case .traditionalChinese: return "繁"
        case .french:  return "FR"
        }
    }

    var fullName: String {
        switch self {
        case .english: return "英语 (English)"
        case .chinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .french:  return "法语 (Français)"
        }
    }

    var isChinese: Bool { self == .chinese || self == .traditionalChinese }

    /// The app's name as shown in this language.
    var brandName: String {
        switch self {
        case .chinese: return "守灯"
        case .traditionalChinese: return "守燈"
        case .english, .french: return "Lantern Care"
        }
    }

    var isFullySupported: Bool {
        true // All 3 languages now supported across main UI
    }
}

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    private let key = "app_language"
    static let languageDidChangeNotification = Notification.Name("ShouDengLanguageDidChange")

    @Published var current: AppLanguage {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: key)
            UserDefaults.standard.set([current.rawValue], forKey: "AppleLanguages")
            bundle = Self.loadBundle(for: current)
            WidgetDataStore.writeLanguage(current.rawValue)
            NotificationCenter.default.post(name: Self.languageDidChangeNotification, object: nil)
        }
    }

    private(set) var bundle: Bundle

    private static let userChoseKey = "app_language_user_chosen"

    /// True once the person picked a language themselves; automatic switching
    /// (e.g. from the phone number's country) must not override that.
    var userChoseLanguage: Bool { UserDefaults.standard.bool(forKey: Self.userChoseKey) }

    /// Explicit choice from a language button or picker.
    func choose(_ language: AppLanguage) {
        UserDefaults.standard.set(true, forKey: Self.userChoseKey)
        if current != language { current = language }
    }

    /// Automatic suggestion (phone country) — ignored after an explicit choice.
    func suggest(_ language: AppLanguage) {
        guard !userChoseLanguage, current != language else { return }
        current = language
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: key)
        let lang = saved.flatMap(AppLanguage.init(rawValue:)) ?? Self.detectLanguage()
        self.current = lang
        self.bundle = Self.loadBundle(for: lang)
        WidgetDataStore.writeLanguage(lang.rawValue)
    }

    func localized(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    func localized(_ key: String, fallback: String) -> String {
        let result = bundle.localizedString(forKey: key, value: fallback, table: nil)
        return result == key ? fallback : result
    }

    /// Simplified Chinese copy that isn't in the strings files yet, shown in
    /// Traditional characters when the app is in Traditional Chinese.
    func zh(_ simplified: String) -> String {
        guard current == .traditionalChinese else { return simplified }
        return Self.toTraditional(simplified)
    }

    static func toTraditional(_ simplified: String) -> String {
        simplified.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? simplified
    }

    static func detectLanguage(preferred: String? = Locale.preferredLanguages.first) -> AppLanguage {
        guard let preferred else { return .english }
        if preferred.hasPrefix("zh") {
            let traditional = preferred.contains("Hant") || ["zh-TW", "zh-HK", "zh-MO"].contains { preferred.hasPrefix($0) }
            return traditional ? .traditionalChinese : .chinese
        }
        if preferred.hasPrefix("fr") { return .french }
        return .english
    }

    private static func loadBundle(for language: AppLanguage) -> Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
