import ActivityKit
import Foundation

/// Shared between main app and widget extension.
/// Defines the data model for the "Guardian Active" Live Activity.
struct GuardianActivityAttributes: ActivityAttributes {

    /// Dynamic state — updated during the Live Activity's lifetime.
    public struct ContentState: Codable, Hashable {
        var status: GuardianStatus
        var statusText: String

        // Location
        var locationAccuracy: Int?
        var lastLocationUpdate: Date

        // Guardian
        var guardianName: String
        var guardianOnline: Bool
        var protectionLayers: Int

        // Emergency call
        var emergencyPhone: String
        var emergencyLabel: String
    }

    enum GuardianStatus: String, Codable, Hashable {
        case normal
        case pendingCheckIn
        case sos
        case locationLost
    }

    // Static attributes — set once when creating the Live Activity
    var userName: String
    var serviceTier: String
}
