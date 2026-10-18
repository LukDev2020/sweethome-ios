import SwiftUI

enum FontScaleLevel: String, CaseIterable {
    case standard = "standard"
    case large = "large"
    case extraLarge = "extraLarge"
    case huge = "huge"

    var scale: CGFloat {
        switch self {
        case .standard:  return 1.0
        case .large:     return 1.25
        case .extraLarge: return 1.5
        case .huge:      return 1.75
        }
    }

    var label: String {
        switch self {
        case .standard:  return "标准"
        case .large:     return "大字"
        case .extraLarge: return "特大"
        case .huge:      return "超大"
        }
    }

    var icon: String {
        switch self {
        case .standard:  return "textformat.size.smaller"
        case .large:     return "textformat.size"
        case .extraLarge: return "textformat.size.larger"
        case .huge:      return "textformat.size.larger"
        }
    }
}

final class FontScaleManager: ObservableObject {
    static let shared = FontScaleManager()

    @Published var level: FontScaleLevel {
        didSet {
            UserDefaults.standard.set(level.rawValue, forKey: "fontScaleLevel")
        }
    }

    var scale: CGFloat { level.scale }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "fontScaleLevel")
        self.level = saved.flatMap(FontScaleLevel.init(rawValue:)) ?? .standard
    }
}

// MARK: - Scaled Font

extension Font {
    /// Drop-in replacement for `.system(size:weight:design:)` that applies the user's font scale.
    /// Body text (<=24pt) gets full scaling; larger sizes get dampened scaling to avoid blowup.
    static func scaled(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let factor = FontScaleManager.shared.scale
        let scaledSize: CGFloat
        if size <= 24 {
            scaledSize = size * factor
        } else {
            // Dampen scaling for large sizes: half the extra scale
            scaledSize = size * (1 + (factor - 1) * 0.5)
        }
        return .system(size: scaledSize, weight: weight, design: design)
    }
}
