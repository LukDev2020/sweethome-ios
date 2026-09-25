import Foundation

/// Shared data model for widget state. Stored as JSON in App Group UserDefaults.
/// Read by widget timeline providers; written by AppCoordinator in the main app.
struct WidgetState: Codable {
    var isLoggedIn: Bool
    var userRole: String?
    var userName: String?
    var guardianCount: Int
    var lastCheckInDate: Date?
    var sosActive: Bool
    var sosTriggeredAt: Date?
    var homeTimerActive: Bool
    var homeTimerDeadline: Date?
    var homeTimerLabel: String?
    var protectedPersons: [WidgetProtectedPerson]
    var updatedAt: Date

    static let empty = WidgetState(
        isLoggedIn: false,
        userRole: nil,
        userName: nil,
        guardianCount: 0,
        lastCheckInDate: nil,
        sosActive: false,
        sosTriggeredAt: nil,
        homeTimerActive: false,
        homeTimerDeadline: nil,
        homeTimerLabel: nil,
        protectedPersons: [],
        updatedAt: Date()
    )
}

struct WidgetProtectedPerson: Codable, Identifiable {
    var id: String
    var displayName: String
    var initial: String
    var status: String  // "normal", "overdue", "alert", "unreachable"
    var lastCheckIn: Date?
    var batteryLevel: Double?
    var homeTimerDeadline: Date?
}
