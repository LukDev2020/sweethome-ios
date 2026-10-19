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
    var emergencyMedications: [WidgetMedication]
    var emergencyPhone: String?
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
        emergencyMedications: [],
        emergencyPhone: nil,
        updatedAt: Date()
    )

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isLoggedIn = (try? container.decode(Bool.self, forKey: .isLoggedIn)) ?? false
        userRole = try? container.decode(String.self, forKey: .userRole)
        userName = try? container.decode(String.self, forKey: .userName)
        guardianCount = (try? container.decode(Int.self, forKey: .guardianCount)) ?? 0
        lastCheckInDate = try? container.decode(Date.self, forKey: .lastCheckInDate)
        sosActive = (try? container.decode(Bool.self, forKey: .sosActive)) ?? false
        sosTriggeredAt = try? container.decode(Date.self, forKey: .sosTriggeredAt)
        homeTimerActive = (try? container.decode(Bool.self, forKey: .homeTimerActive)) ?? false
        homeTimerDeadline = try? container.decode(Date.self, forKey: .homeTimerDeadline)
        homeTimerLabel = try? container.decode(String.self, forKey: .homeTimerLabel)
        protectedPersons = (try? container.decode([WidgetProtectedPerson].self, forKey: .protectedPersons)) ?? []
        emergencyMedications = (try? container.decode([WidgetMedication].self, forKey: .emergencyMedications)) ?? []
        emergencyPhone = try? container.decode(String.self, forKey: .emergencyPhone)
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? Date()
    }

    init(isLoggedIn: Bool, userRole: String?, userName: String?, guardianCount: Int,
         lastCheckInDate: Date?, sosActive: Bool, sosTriggeredAt: Date?,
         homeTimerActive: Bool, homeTimerDeadline: Date?, homeTimerLabel: String?,
         protectedPersons: [WidgetProtectedPerson], emergencyMedications: [WidgetMedication] = [],
         emergencyPhone: String? = nil, updatedAt: Date) {
        self.isLoggedIn = isLoggedIn
        self.userRole = userRole
        self.userName = userName
        self.guardianCount = guardianCount
        self.lastCheckInDate = lastCheckInDate
        self.sosActive = sosActive
        self.sosTriggeredAt = sosTriggeredAt
        self.homeTimerActive = homeTimerActive
        self.homeTimerDeadline = homeTimerDeadline
        self.homeTimerLabel = homeTimerLabel
        self.protectedPersons = protectedPersons
        self.emergencyMedications = emergencyMedications
        self.emergencyPhone = emergencyPhone
        self.updatedAt = updatedAt
    }
}

struct WidgetMedication: Codable, Identifiable {
    var id: String
    var name: String
    var location: String   // 放置位置
    var dosage: String     // 服用方法
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
