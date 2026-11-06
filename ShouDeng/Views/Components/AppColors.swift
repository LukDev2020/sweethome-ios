import SwiftUI
import UIKit

// MARK: - Colours that follow dark mode
//
// Most screens hard-coded a navy "ink" for text and cream backgrounds; in dark mode
// that gave navy text on black and white cards with white text. These follow the
// app's colour scheme (Settings → Dark Mode, applied at the app root).

extension Color {
    /// Brand navy text; near-white in dark mode
    static let appInk = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.94, alpha: 1)
            : UIColor(red: 18/255, green: 32/255, blue: 58/255, alpha: 1)
    })

    /// The same navy in both modes — fills and panels with white text on them
    static let inkSolid = Color(red: 18/255, green: 32/255, blue: 58/255)

    /// A light page / card background (cream, off-white) that turns dark in dark mode
    static func paper(_ red: Double, _ green: Double, _ blue: Double, elevated: Bool = false) -> Color {
        Color(UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return elevated ? .secondarySystemBackground : .systemBackground
            }
            return UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
        })
    }
}
