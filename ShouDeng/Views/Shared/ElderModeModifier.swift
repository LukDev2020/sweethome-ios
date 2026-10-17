import SwiftUI

// MARK: - Elder Mode Modifier
//
// Applied to Care Receiver (Protected) views to enforce accessibility defaults:
// - Minimum dynamic type size of .xLarge
// - Bold text for better legibility
// Controlled by the "elder_mode" AppStorage flag (default: true for Care Receivers).

struct ElderModeModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .dynamicTypeSize(.xLarge ... .accessibility3)
                .environment(\.legibilityWeight, .bold)
        } else {
            content
        }
    }
}
