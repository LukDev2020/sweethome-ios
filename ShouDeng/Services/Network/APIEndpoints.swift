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

struct CreateInviteRequest: Codable {
    let role: String
}

struct CreateInviteResponse: Codable {
    let inviteId: String
    let code: String
    let expiresAt: String
    let status: String
}

struct AcceptInviteRequest: Codable {
    let code: String
}

struct AcceptInviteResponse: Codable {
    let success: Bool
    let guardianId: String
    let protectedPersonId: String
    let linkId: String
}

struct UpdatePermissionsRequest: Codable {
    let canSeeLocation: Bool
    let canSeeBattery: Bool
    let canSeeHealth: Bool
    let canSeePhoneActivity: Bool
    let canHearEmergencyAudio: Bool
}

struct SuccessResponse: Codable {
    let success: Bool
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
    let locationAccuracy: Double?
    let batteryLevel: Double?
    let batteryState: BatteryState
    let lastCheckIn: Date?
    let lastPhoneActivity: Date?
    let protectionLayers: Int
    // Profile fields for cross-timezone display
    var timeZoneId: String?
    var countryCode: String?
    var cityName: String?
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

// MARK: - Family Feed

struct CreatePostRequest: Codable {
    let text: String
    let mediaURLs: [String]
}

struct CreatePostResponse: Codable {
    let postId: String
}

struct AddCommentRequest: Codable {
    let text: String
}

struct AddCommentResponse: Codable {
    let commentId: String
}

struct MediaUploadResponse: Codable {
    let url: String
}

// MARK: - Notification Preferences

struct NotificationPrefsRequest: Codable {
    let sosAlerts: Bool
    let checkinReminder: Bool
    let checkinOverdue: Bool
    let familyFeed: Bool
}

// MARK: - Home Timer

struct HomeTimerRequest: Codable {
    let deadline: Date
    let label: String?
    let latitude: Double?
    let longitude: Double?
}

struct HomeTimerResponse: Codable {
    let userId: String
    let deadline: Date
    let label: String
    let status: String
    let createdAt: Date
}

struct HomeTimerDismissResponse: Codable {
    let success: Bool
}

struct GuardianTimerResponse: Codable {
    let userId: String
    let displayName: String
    let deadline: Date
    let label: String
    let status: String
}

// MARK: - Arrival Report

struct ArrivalReportRequest: Codable {
    let latitude: Double?
    let longitude: Double?
    let placeName: String?
}

struct ArrivalReportResponse: Codable {
    let success: Bool
    let reportId: String
}

struct RecentArrivalReport: Codable, Identifiable {
    let id: String
    let userId: String
    let displayName: String
    let latitude: Double?
    let longitude: Double?
    let placeName: String?
    let timestamp: Date
}

// MARK: - Shared Itinerary

struct ItineraryCreateRequest: Codable {
    let type: String
    let carrierCode: String?
    let flightNumber: String?
    let departureCity: String
    let arrivalCity: String
    let departureTime: Date
    let arrivalTime: Date?
    let note: String?
}

struct ItineraryCreateResponse: Codable {
    let id: String
    let success: Bool
}

struct ItineraryItem: Codable, Identifiable {
    let id: String
    let userId: String
    let displayName: String
    let type: String
    let carrierCode: String?
    let flightNumber: String?
    let departureCity: String
    let arrivalCity: String
    let departureTime: Date
    let arrivalTime: Date?
    let note: String?
    let status: String
}

// MARK: - Medical Card

struct MedicalCardData: Codable {
    var bloodType: String?
    var allergies: [String]
    var medications: [String]
    var conditions: [String]
    var insuranceProvider: String?
    var insurancePolicyNumber: String?
    var emergencyNote: String?
    var organDonor: Bool
    var weight: Double?
    var height: Double?

    init(
        bloodType: String? = nil, allergies: [String] = [], medications: [String] = [],
        conditions: [String] = [], insuranceProvider: String? = nil,
        insurancePolicyNumber: String? = nil, emergencyNote: String? = nil,
        organDonor: Bool = false, weight: Double? = nil, height: Double? = nil
    ) {
        self.bloodType = bloodType
        self.allergies = allergies
        self.medications = medications
        self.conditions = conditions
        self.insuranceProvider = insuranceProvider
        self.insurancePolicyNumber = insurancePolicyNumber
        self.emergencyNote = emergencyNote
        self.organDonor = organDonor
        self.weight = weight
        self.height = height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bloodType = try container.decodeIfPresent(String.self, forKey: .bloodType)
        allergies = (try? container.decodeIfPresent([String].self, forKey: .allergies)) ?? []
        medications = (try? container.decodeIfPresent([String].self, forKey: .medications)) ?? []
        conditions = (try? container.decodeIfPresent([String].self, forKey: .conditions)) ?? []
        insuranceProvider = try container.decodeIfPresent(String.self, forKey: .insuranceProvider)
        insurancePolicyNumber = try container.decodeIfPresent(String.self, forKey: .insurancePolicyNumber)
        emergencyNote = try container.decodeIfPresent(String.self, forKey: .emergencyNote)
        organDonor = (try? container.decodeIfPresent(Bool.self, forKey: .organDonor)) ?? false
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        height = try container.decodeIfPresent(Double.self, forKey: .height)
    }

    static let empty = MedicalCardData()
}

// MARK: - Emergency Text

struct EmergencyPhrase: Codable {
    let helpText: String
    let emergencyNumber: String
    let language: String
}

// MARK: - Consulate

struct ConsulateInfo: Codable {
    let countryName: String
    let emergencyNumber: String
    let policeNumber: String
    let ambulanceNumber: String
    let chineseEmbassy: String?
    let chineseConsulate: [String]?
}

struct ConsulateListItem: Codable {
    let countryCode: String
    let countryName: String
    let emergencyNumber: String
}

// MARK: - Organization

struct OrgCreateRequest: Codable {
    let name: String
    let type: String
    let contactEmail: String?
    let contactPhone: String?
}

struct OrgCreateResponse: Codable {
    let orgId: String
    let success: Bool
}

struct OrgDashboard: Codable {
    let orgId: String
    let orgName: String
    let orgType: String
    let summary: OrgDashboardSummary
    let members: [OrgMemberStatus]
}

struct OrgDashboardSummary: Codable {
    let totalMembers: Int
    let activated: Int
    let permissionsAbnormal: Int
    let notInstalled: Int
    let recentCheckIns: Int
    let overdueCheckIns: Int
}

struct OrgMemberStatus: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    let displayName: String
    let status: String
    let lastCheckIn: Date?
    let cityName: String?
    let countryCode: String?
}

struct OrgAlertRequest: Codable {
    let orgId: String
    let title: String
    let body: String
    let countryCode: String?
    let severity: String?
}

struct OrgAlertResponse: Codable {
    let success: Bool
    let alertId: String
    let sentCount: Int
}

struct OrgRollCallStatus: Codable {
    let alertId: String
    let title: String
    let totalMembers: Int
    let confirmed: Int
    let noResponse: Int
    let entries: [RollCallEntry]
}

struct RollCallEntry: Codable, Identifiable {
    var id: String { userId }
    let userId: String
    let displayName: String
    let status: String
    let respondedAt: Date?
}

struct OrgReport: Codable {
    let orgId: String
    let orgName: String
    let reportPeriod: ReportPeriod
    let summary: OrgReportSummary
    let generatedAt: Date
}

struct ReportPeriod: Codable {
    let start: Date
    let end: Date
}

struct OrgReportSummary: Codable {
    let totalMembers: Int
    let totalCheckIns: Int
    let totalAlerts: Int
    let totalSOSEvents: Int
    let avgCheckInsPerMember: Int
}

// MARK: - Insurance (legacy — kept for InsuranceReportView compatibility)

struct InsuranceClaimRequest: Codable {
    let incidentDate: Date
    let description: String?
    let protectedPersonId: String?
}

struct InsuranceClaimReport: Codable {
    let reportId: String
    let personName: String
    let incidentDate: Date
    let generatedAt: Date
}

// New claim material models are in ClaimMaterialModels.swift

// MARK: - Selected Hotline

struct SelectedHotline: Codable {
    let countryCode: String
    let countryName: String
    let flag: String
    let emergency: String
    let embassy: String
    var selectedPhone: String?
    var selectedLabel: String?
}

struct SelectedHotlineRequest: Codable {
    let countryCode: String
    let countryName: String
    let flag: String
    let emergency: String
    let embassy: String
    let selectedPhone: String?
    let selectedLabel: String?
}

// MARK: - Empty Body (for POST with no payload)

struct EmptyBody: Codable {}
