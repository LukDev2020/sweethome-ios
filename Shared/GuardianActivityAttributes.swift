import ActivityKit
import Foundation

/// Live Activity data model for the **关怀者 (Guardian)** role.
/// Shows the status of each protected person at a glance.
struct GuardianActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        var overallStatus: OverallStatus
        var overallStatusText: String

        /// Protected persons being watched (max 3 shown)
        var persons: [PersonInfo]

        /// The person needing most attention (for the CTA button)
        var priorityPersonName: String
        var priorityPersonPhone: String

        /// Updated timestamp
        var updatedAt: Date

        /// Settings → Lock screen card (nil: the stored style); a change here redraws the card
        var cardStyle: LockScreenCardStyle? = nil
        /// Someone I look after raised an SOS: the card is about them
        var sos: SOSCardInfo? = nil
    }

    /// The SOS on the guardian's card: where, how far, battery, who is handling it.
    struct SOSCardInfo: Codable, Hashable {
        var sosEventId: String
        var personName: String
        var initial: String
        var startedAt: Date
        var batteryLevel: Double? = nil
        var address: String? = nil
        var distanceMeters: Int? = nil
        var locationAt: Date? = nil
        var latitude: Double? = nil
        var longitude: Double? = nil
        var phone: String? = nil
        /// A guardian said "I've got it" (me: `acknowledgedByMe`)
        var acknowledgedByName: String? = nil
        var acknowledgedByMe: Bool = false
    }

    struct PersonInfo: Codable, Hashable, Identifiable {
        var id: String
        var displayName: String
        var initial: String
        var status: PersonStatus
        var cityName: String
        var lastCheckIn: Date?
        var batteryLevel: Double?
    }

    enum PersonStatus: String, Codable, Hashable {
        case normal
        case overdue
        case alert
        case unreachable
    }

    enum OverallStatus: String, Codable, Hashable {
        case allSafe
        case needsAttention
        case sosAlert
    }

    // Static — set once
    var guardianName: String
}
