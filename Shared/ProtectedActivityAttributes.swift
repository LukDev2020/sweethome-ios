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

        /// Emergency medical info (for lock screen first-responder display)
        var bloodType: String?
        var allergies: [String]
        var conditions: [String]
        var emergencyNote: String?
        var emergencyMedications: [MedInfo]

        /// Latest family-circle post ("Sarah：Home yet?"), shown as "Latest"
        var latestUpdate: String? = nil
        var latestUpdateAt: Date? = nil
        /// Last time "Location" on the card sent a fresh location to the family
        var lastLocationShare: Date? = nil
        /// Settings → Lock screen card (nil: the stored style); a change here redraws the card
        var cardStyle: LockScreenCardStyle? = nil
        /// Rider mode: the card shows the shift, crew and (during SOS) bystander help
        var rider: RiderCardInfo? = nil
    }

    struct MedInfo: Codable, Hashable {
        var name: String
        var location: String
        var dosage: String
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

/// Rider-mode content of the protected person's lock-screen card.
struct RiderCardInfo: Codable, Hashable {
    var shiftStartedAt: Date?
    /// Planned shift end (the check-in is due 30 min after it)
    var checkDueAt: Date?
    var crewOnShiftNearby: Int
    /// Street to read out during an SOS (looked up when the SOS starts)
    var sosAddress: String?
    /// First crew mate who answered "I'm going"
    var helperName: String?
    var helperDistanceM: Int?
}
