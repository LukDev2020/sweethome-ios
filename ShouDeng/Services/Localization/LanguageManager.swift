import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case chinese = "zh-Hans"
    case french = "fr"

    var displayName: String {
        switch self {
        case .english: return "EN"
        case .chinese: return "中"
        case .french:  return "FR"
        }
    }

    var fullName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        case .french:  return "Français"
        }
    }
}

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    private let key = "app_language"
    @Published var current: AppLanguage {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: key)
            UserDefaults.standard.set([current.rawValue], forKey: "AppleLanguages")
            bundle = Self.loadBundle(for: current)
        }
    }

    private(set) var bundle: Bundle

    private init() {
        let saved = UserDefaults.standard.string(forKey: key)
        let lang = saved.flatMap(AppLanguage.init(rawValue:)) ?? Self.detectLanguage()
        self.current = lang
        self.bundle = Self.loadBundle(for: lang)
    }

    func localized(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func detectLanguage() -> AppLanguage {
        guard let preferred = Locale.preferredLanguages.first else { return .english }
        if preferred.hasPrefix("zh") { return .chinese }
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
