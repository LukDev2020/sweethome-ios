import SwiftUI

struct DuoTabItem: Identifiable {
    let id: Int
    let title: String
    let icon: String
    let view: AnyView
    /// The tab draws the bottom accessory (SOS) itself, inside its own NavigationStack,
    /// because it has a bottom bar of its own (the family-circle composer). An inset
    /// attached outside the NavigationStack is not passed in, so it covered the composer.
    var placesOwnAccessory: Bool = false
}

private struct TabBottomAccessoryKey: EnvironmentKey {
    static let defaultValue: AnyView? = nil
}

extension EnvironmentValues {
    /// Set for tabs with `placesOwnAccessory`: the SOS button to show above their bottom bar.
    var tabBottomAccessory: AnyView? {
        get { self[TabBottomAccessoryKey.self] }
        set { self[TabBottomAccessoryKey.self] = newValue }
    }
}
