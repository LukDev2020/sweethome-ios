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
    var activityType: String?
    var encryptedPayload: E2ELocationEncryption.EncryptedPayload?
}

// MARK: - SOS

struct SOSTriggerRequest: Codable {
    let protectedPersonId: String
    let triggerMethod: SOSTriggerMethod
    let latitude: Double?
    let longitude: Double?
    let batteryLevel: Double?
    /// Device-local SOS id. Lets a resolve queued while offline map to exactly
    /// this SOS on the server (never to a newer one).
    var clientSOSId: String? = nil
    var clientTriggeredAt: Date? = nil
}

/// Server read model of an SOS (GET /v1/sos/active, /v1/guardian/sos/active,
/// activeSOS on the guardian dashboard). See ContractFixtures/guardian_sos_active.json.
struct SOSStatus: Codable, Equatable {
    let sosEventId: String
    let protectedPersonId: String
    let personName: String
    let triggeredAt: Date?
    let triggerMethod: String?
    let latitude: Double?
    let longitude: Double?
    let batteryLevel: Double?
    let escalationState: EscalationState
    let nextStep: String?
    let nextStepAt: Date?
    let guardiansNotified: Int
    let callsPlaced: Int
    let shareLinkSent: Bool
    let noGuardians: Bool
    let emergencyContactsNotified: Int
    let acknowledgedBy: String?
    let acknowledgedByName: String?
    let acknowledgedAt: Date?
    let elapsedSeconds: Int
    /// Live position during the SOS (absent from older servers)
    var locationUpdatedAt: Date? = nil
    /// Thinned path since the SOS started
    var trail: [SOSTrailPoint]? = nil
    /// Where the person said they are heading
    var route: SOSSharedRoute? = nil
    /// Rider crews: crew mates alerted, and who answered ("I'm going")
    var crewNotified: Int? = nil
    var crewResponses: [CrewResponseEntry]? = nil
}

struct SOSTrailPoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    var at: String? = nil
}

struct SOSSharedRoute: Codable, Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
    let mode: String
    var sharedAt: String? = nil
}

struct SOSRouteRequest: Codable {
    let name: String
    let latitude: Double
    let longitude: Double
    let mode: String
}

struct ActiveSOSResponse: Decodable {
    let active: Bool
    let sos: SOSStatus?
}

struct SOSAcknowledgeRequest: Codable {
    let sosEventId: String
}

struct SOSAcknowledgeResponse: Codable {
    let success: Bool
    let acknowledgedBy: String
    let alreadyAcknowledged: Bool
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
    /// What the inviter becomes once the invite is accepted: "protected" (the
    /// acceptor will guard them) or "guardian" (they will guard the acceptor).
    let inviterRole: String

    init(inviterRole: UserRole) {
        self.inviterRole = inviterRole.rawValue
    }
}

struct CreateInviteResponse: Codable {
    let inviteId: String
    let code: String
    let expiresAt: String
    let status: String
}

/// GET /v1/invite/preview — shown on the confirmation screen before accepting.
struct InvitePreviewResponse: Codable, Equatable {
    let code: String
    /// nil unless the invite can still be accepted
    let inviterName: String?
    let avatarInitial: String?
    let inviterRole: String
    let expiresAt: String?
    /// "pending" | "accepted" | "expired"
    let status: String
    let isOwnInvite: Bool?

    /// The side the person accepting ends up on.
    var acceptorRole: UserRole {
        inviterRole == UserRole.protected_.rawValue ? .guardian : .protected_
    }
}

struct AcceptInviteRequest: Codable {
    let code: String
    /// Guardian's opt-in to receive SOS alerts as iOS Critical Alerts.
    var criticalAlertConsent: Bool? = nil
}

struct AcceptInviteResponse: Codable {
    let success: Bool
    let guardianId: String
    let protectedPersonId: String
    let linkId: String
    /// "guardian" | "protected" (older servers don't send it)
    var acceptorRole: String? = nil
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
    var email: String? = nil
    let timeZone: String?
    let cityName: String?
    let countryCode: String?
}

struct UserProfileResponse: Codable {
    let id: String
    let displayName: String
    let role: String
    let avatarInitial: String
    let email: String?
    let timeZone: String
    let countryCode: String
    let cityName: String
    let createdAt: Date
    var dataTransferConsentVersion: String? = nil
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
    var activeSOS: SOSStatus?
    /// For "Call now" (was missing: the button could never dial)
    var phone: String?

    private enum CodingKeys: String, CodingKey {
        case personId, displayName, status, latitude, longitude, locationTimestamp, locationAddress
        case locationAccuracy, batteryLevel, batteryState, lastCheckIn, lastPhoneActivity
        case protectionLayers, timeZoneId, countryCode, cityName, activeSOS, phone
    }

    /// Only `personId` is required. A malformed optional field (e.g. a timestamp the
    /// server failed to normalise) becomes nil instead of failing the whole person.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        personId = try c.decode(String.self, forKey: .personId)
        displayName = c.lossy(String.self, .displayName) ?? ""
        status = c.lossy(SafetyStatus.self, .status) ?? .unreachable
        latitude = c.lossy(Double.self, .latitude)
        longitude = c.lossy(Double.self, .longitude)
        locationTimestamp = c.lossy(Date.self, .locationTimestamp)
        locationAddress = c.lossy(String.self, .locationAddress)
        locationAccuracy = c.lossy(Double.self, .locationAccuracy)
        batteryLevel = c.lossy(Double.self, .batteryLevel)
        batteryState = c.lossy(BatteryState.self, .batteryState) ?? .unknown
        lastCheckIn = c.lossy(Date.self, .lastCheckIn)
        lastPhoneActivity = c.lossy(Date.self, .lastPhoneActivity)
        protectionLayers = c.lossy(Int.self, .protectionLayers) ?? 0
        timeZoneId = c.lossy(String.self, .timeZoneId)
        countryCode = c.lossy(String.self, .countryCode)
        cityName = c.lossy(String.self, .cityName)
        activeSOS = c.lossy(SOSStatus.self, .activeSOS)
        phone = c.lossy(String.self, .phone)
    }
}

// MARK: - Lossy decoding helpers

extension KeyedDecodingContainer {
    /// Decodes an optional value, returning nil when it is missing, null or malformed.
    func lossy<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

/// Decodes a JSON array element by element, dropping elements that fail to decode
/// so one bad row can't blank a whole list.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]
    private(set) var droppedCount = 0

    private struct AnyDecodable: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [Element] = []
        while !container.isAtEnd {
            if let item = try? container.decode(Element.self) {
                items.append(item)
            } else {
                _ = try? container.decode(AnyDecodable.self)
                droppedCount += 1
            }
        }
        elements = items
    }
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

struct TimelineResponse: Decodable {
    let entries: [TimelineEntry]
    let hasMore: Bool?
    let nextBefore: Date?

    private enum CodingKeys: String, CodingKey { case entries, hasMore, nextBefore }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decode(LossyArray<TimelineEntry>.self, forKey: .entries).elements
        hasMore = c.lossy(Bool.self, .hasMore)
        nextBefore = c.lossy(Date.self, .nextBefore)
    }
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
    /// https links only (see FamilyFeedSync.remoteMediaURLs).
    let mediaURLs: [String]
    var latitude: Double? = nil
    var longitude: Double? = nil
    var locationName: String? = nil
    /// The post's id on this phone; a retried send lands on the same server post.
    var clientPostId: String? = nil
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
    /// Guardian receives SOS as a Critical Alert (sounds even when muted).
    let sosCriticalAlerts: Bool
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
    let destination: String?
    let routeNotes: String?
}

struct HomeTimerExpireRequest: Codable {
    let destination: String?
    let routeNotes: String?
}

// MARK: - BLE Tracker

struct BLESeparationRequest: Codable {
    let tagName: String
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

// MARK: - Medication Item

struct MedicationItem: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var storageLocation: String   // 放置位置 (e.g. "床头柜第二层")
    var dosage: String            // 服用方法 (e.g. "舌下含服1片")
    var isEmergency: Bool         // 急救药品 — shows on lock screen

    init(id: String = UUID().uuidString, name: String = "", storageLocation: String = "", dosage: String = "", isEmergency: Bool = false) {
        self.id = id
        self.name = name
        self.storageLocation = storageLocation
        self.dosage = dosage
        self.isEmergency = isEmergency
    }
}

// MARK: - Medical Card

struct MedicalCardData: Codable {
    var bloodType: String?
    var allergies: [String]
    var medications: [String]           // Legacy flat list (backward compat)
    var medicationItems: [MedicationItem]  // Structured items with location/dosage
    var conditions: [String]
    var insuranceProvider: String?
    var insurancePolicyNumber: String?
    var emergencyNote: String?
    var organDonor: Bool
    var weight: Double?
    var height: Double?

    init(
        bloodType: String? = nil, allergies: [String] = [], medications: [String] = [],
        medicationItems: [MedicationItem] = [],
        conditions: [String] = [], insuranceProvider: String? = nil,
        insurancePolicyNumber: String? = nil, emergencyNote: String? = nil,
        organDonor: Bool = false, weight: Double? = nil, height: Double? = nil
    ) {
        self.bloodType = bloodType
        self.allergies = allergies
        self.medications = medications
        self.medicationItems = medicationItems
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
        medicationItems = (try? container.decodeIfPresent([MedicationItem].self, forKey: .medicationItems)) ?? []
        conditions = (try? container.decodeIfPresent([String].self, forKey: .conditions)) ?? []
        insuranceProvider = try container.decodeIfPresent(String.self, forKey: .insuranceProvider)
        insurancePolicyNumber = try container.decodeIfPresent(String.self, forKey: .insurancePolicyNumber)
        emergencyNote = try container.decodeIfPresent(String.self, forKey: .emergencyNote)
        organDonor = (try? container.decodeIfPresent(Bool.self, forKey: .organDonor)) ?? false
        weight = try container.decodeIfPresent(Double.self, forKey: .weight)
        height = try container.decodeIfPresent(Double.self, forKey: .height)
    }

    /// Emergency medications only (for lock screen display)
    var emergencyMedications: [MedicationItem] {
        medicationItems.filter { $0.isEmergency }
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

// MARK: - Insurance

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

// MARK: - Location Batch

struct LocationBatchRequest: Codable {
    let reports: [LocationReportRequest]
}

struct LocationBatchResponse: Codable {
    let success: Bool
    let processed: Int
    let errors: Int
}

// MARK: - Voice Note

struct VoiceNoteRequest: Codable {
    let transcript: String
    let duration: Double
    let keywords: [String]
    let senderRole: String
}

struct VoiceNoteResponse: Codable {
    let noteId: String
    let createdAt: Date
}

struct VoiceNoteItem: Codable, Identifiable {
    let id: String
    let senderId: String
    let senderRole: String
    let transcript: String
    let duration: Double
    let keywords: [String]
    let createdAt: Date
}

struct VoiceNotesListResponse: Codable {
    let notes: [VoiceNoteItem]
}

// MARK: - Empty Body (for POST with no payload)

struct EmptyBody: Codable {}
