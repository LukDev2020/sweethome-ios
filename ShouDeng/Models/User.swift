import Foundation

// MARK: - User Roles

enum UserRole: String, Codable {
    case protected_ = "protected"  // 被守护者 (e.g. 小雨 in Kyiv)
    case guardian = "guardian"      // 守护者 (e.g. 妈妈 in Toronto)
}

// MARK: - User

struct User: Codable, Identifiable {
    let id: String
    var displayName: String
    var role: UserRole
    var avatarInitial: String        // Single character for avatar circle
    var avatarLocalPath: String?     // Local file path for custom avatar photo
    var phone: String?               // E.164 format, e.g. "+8613800138000"
    var email: String?               // For account recovery
    var timeZone: TimeZone
    var countryCode: String          // ISO 3166-1 alpha-2
    var cityName: String
    var createdAt: Date

    var localTime: Date {
        Date()  // Displayed in user's own time zone via formatting
    }
}

// MARK: - Protected Person (extended)

struct ProtectedPerson: Codable, Identifiable {
    let id: String
    var user: User
    var guardians: [Guardian]
    var protectionLayers: Int          // 1-3 based on guardian count + response center
    var lastCheckIn: Date?
    var lastKnownLocation: Location?
    var batteryLevel: Double?          // 0.0-1.0
    var batteryState: BatteryState
    var lastPhoneActivity: Date?       // Inferred from app launches / push receipts
    var status: SafetyStatus

    var isOverdue: Bool {
        guard let lastCheckIn else { return true }
        return Date().timeIntervalSince(lastCheckIn) > overdueThresholdSeconds
    }

    var overdueThresholdSeconds: TimeInterval {
        4 * 3600  // Default 4 hours, configurable per person
    }
}

// MARK: - Guardian

struct Guardian: Codable, Identifiable {
    let id: String
    var user: User
    var permissions: GuardianPermissions
    var isOnDuty: Bool
    var dutySchedule: DutySchedule?
    var averageResponseTime: TimeInterval  // Historical, for escalation timing
    var linkedSince: Date
}

struct GuardianPermissions: Codable {
    var canSeeLocation: Bool
    var canSeeBattery: Bool
    var canSeeHealth: Bool
    var canSeePhoneActivity: Bool
    var canHearEmergencyAudio: Bool

    static let defaultPermissions = GuardianPermissions(
        canSeeLocation: true,
        canSeeBattery: true,
        canSeeHealth: false,
        canSeePhoneActivity: false,
        canHearEmergencyAudio: true
    )
}

// MARK: - Enums

enum BatteryState: String, Codable {
    case charging
    case full
    case unplugged
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = BatteryState(rawValue: raw) ?? .unknown
    }
}

enum SafetyStatus: String, Codable {
    case normal             // Green — all good
    case pendingCheckIn     // Yellow — approaching check-in deadline
    case overdue            // Orange — missed check-in, not yet escalated
    case alert              // Red — SOS triggered or escalation in progress
    case unreachable        // Grey — phone off / no signal
}

// MARK: - Location

struct Location: Codable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double           // meters
    let altitude: Double?
    let speed: Double?             // m/s
    let timestamp: Date
    var address: String?           // Reverse geocoded
    var isInSafeZone: Bool?
    var safeZoneName: String?
    var activityType: ActivityType?

    enum ActivityType: String, Codable {
        case stationary
        case walking
        case running
        case driving
        case cycling
        case unknown
    }
}

// MARK: - E2E Encryption

extension User {
    /// Base64-encoded X25519 public key for E2E location encryption
    var publicKey: String? {
        get { UserDefaults.standard.string(forKey: "e2e_publicKey_\(id)") }
        set { UserDefaults.standard.set(newValue, forKey: "e2e_publicKey_\(id)") }
    }
}

// MARK: - Duty Schedule

struct DutySchedule: Codable {
    let guardianId: String
    var slots: [DutySlot]
}

struct DutySlot: Codable {
    var startHour: Int          // 0-23 in protected person's time zone
    var endHour: Int
    var dayOfWeek: Set<Int>     // 1=Sunday...7=Saturday, empty = every day
    var isConfirmed: Bool
}
