import ActivityKit
import Foundation

/// Live Activity data model for the **被关怀者 (Protected Person)** role.
/// Shows who is guarding you, your status, and quick-action buttons.
struct ProtectedActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        var status: OverallStatus
        var statusText: String

        /// Guardians currently watching
        var guardians: [GuardianInfo]

        /// Last check-in time
        var lastCheckIn: Date?

        /// Home timer (optional)
        var homeTimerDeadline: Date?
        var homeTimerLabel: String?

        /// Emergency call target
        var emergencyPhone: String
        var emergencyLabel: String
    }

    struct GuardianInfo: Codable, Hashable {
        var name: String
        var initial: String
        var isOnDuty: Bool
        var isOnline: Bool
    }

    enum OverallStatus: String, Codable, Hashable {
        case normal
        case sosActive
        case timerRunning
        case pendingCheckIn
    }

    // Static — set once
    var userName: String
}
