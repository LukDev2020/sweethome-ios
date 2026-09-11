import Foundation

// MARK: - API Endpoints
//
// Request/response types for all server API calls.
// Organized by domain: heartbeat, location, SOS, relationships, user.

// MARK: - Heartbeat

struct HeartbeatRequest: Codable {
    let userId: String
    let timestamp: Date
    let source: HeartbeatSource
    let batteryLevel: Double?
    let batteryState: BatteryState?
    let latitude: Double?
    let longitude: Double?
    let accuracy: Double?
}

// MARK: - Location Report

struct LocationReportRequest: Codable {
    let userId: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let altitude: Double?
    let speed: Double?
    let timestamp: Date
    let isInSafeZone: Bool?
    let safeZoneName: String?
}

// MARK: - SOS

struct SOSTriggerRequest: Codable {
    let protectedPersonId: String
    let triggerMethod: SOSTriggerMethod
    let latitude: Double?
    let longitude: Double?
    let batteryLevel: Double?
}

struct SOSTriggerResponse: Codable {
    let sosEventId: String
    let escalationState: EscalationState
}

struct SOSResolveRequest: Codable {
    let sosEventId: String
    let resolvedBy: String
    let resolution: SOSResolution
}

// MARK: - Voice Call

struct VoiceCallRequest: Codable {
    let guardianId: String
    let sosEventId: String
    let protectedPersonName: String
    let locationDescription: String?
}

// MARK: - Check-In

struct CheckInRequest: Codable {
    let userId: String
    let latitude: Double?
    let longitude: Double?
    let note: String?
}

struct CheckInResponse: Codable {
    let checkInId: String
    let timestamp: Date
}

// MARK: - Relationships

struct InviteGuardianRequest: Codable {
    let protectedPersonId: String
    let guardianPhone: String
    let permissions: GuardianPermissions
    let message: String
}

struct InviteResponse: Codable {
    let inviteId: String
    let status: String
}

struct AcceptInviteRequest: Codable {
    let inviteId: String
}

// MARK: - User Profile

struct UpdateProfileRequest: Codable {
    let displayName: String?
    let timeZone: String?
    let cityName: String?
    let countryCode: String?
}

struct UserProfileResponse: Codable {
    let id: String
    let displayName: String
    let role: String
    let avatarInitial: String
    let timeZone: String
    let countryCode: String
    let cityName: String
    let createdAt: Date
}

// MARK: - Protected Person Status (guardian polls this)

struct ProtectedPersonStatusResponse: Codable {
    let personId: String
    let displayName: String
    let status: SafetyStatus
    let latitude: Double?
    let longitude: Double?
    let locationTimestamp: Date?
    let locationAddress: String?
    let batteryLevel: Double?
    let batteryState: BatteryState
    let lastCheckIn: Date?
    let lastPhoneActivity: Date?
    let protectionLayers: Int
}

// MARK: - Device Token Registration

struct DeviceTokenRequest: Codable {
    let token: String
    let platform: String
    let environment: String
}

// MARK: - Safe Zone

struct SaveSafeZoneRequest: Codable {
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double
}

struct SafeZoneResponse: Codable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let isAutoSuggested: Bool
}

// MARK: - Duty Schedule

struct UpdateDutyScheduleRequest: Codable {
    let guardianId: String
    let slots: [DutySlot]
}

// MARK: - Timeline

struct TimelineResponse: Codable {
    let entries: [TimelineEntry]
    let hasMore: Bool
}

// MARK: - Subscription

struct SubscriptionResponse: Codable {
    let planId: String
    let status: String
    let expiresAt: String?
    let features: [String]
}

// MARK: - Data Export

struct DataExportRequest: Codable {
    let userId: String
    let format: String
}

// MARK: - Empty Body (for POST with no payload)

struct EmptyBody: Codable {}
