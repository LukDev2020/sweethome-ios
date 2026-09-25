import SwiftUI

/// Brand colors shared between the main app and widget extension.
enum SharedColors {
    /// Dark navy background — "ink"
    static let ink = Color(red: 0.086, green: 0.129, blue: 0.235)
    /// Brand accent — "lamp red"
    static let lamp = Color(red: 0.914, green: 0.271, blue: 0.376)
    /// Safe / normal status
    static let safe = Color.green
    /// Alert / SOS status
    static let alert = Color.red
    /// Warning / overdue status
    static let warning = Color.orange
    /// Offline / unreachable status
    static let offline = Color.gray
}
