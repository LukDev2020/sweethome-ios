import Foundation

// MARK: - SOS Event

struct SOSEvent: Codable, Identifiable {
    var id: String
    let protectedPersonId: String
    let triggeredAt: Date
    let triggerMethod: SOSTriggerMethod
    let location: Location?
    let batteryLevel: Double?
    var escalationState: EscalationState
    var resolvedAt: Date?
    var resolvedBy: String?          // Guardian ID who clicked "I've taken over"
    var resolution: SOSResolution?
    /// Device-local id sent with the trigger; the server maps it to the real event.
    var clientSOSId: String? = nil

    var isActive: Bool { resolvedAt == nil }

    var elapsedSeconds: TimeInterval {
        let end = resolvedAt ?? Date()
        return end.timeIntervalSince(triggeredAt)
    }
}

enum SOSTriggerMethod: String, Codable {
    case longPress           // In-app 3-second hold
    case watchQuickAction    // Apple Watch complication/shortcut
    case bluetoothButton     // External BT panic button
    case duressPassword      // Entered duress PIN — looks normal, silently alerts
    case fallDetection       // Automatic from fall algorithm
    case voiceWakeWord       // "Help me" / custom phrase (V3)
    case audioDistress       // On-device scream/distress sound detection
    case voiceCommand        // On-device speech recognition ("救命", "help")
    case widgetTap           // One-tap SOS from home screen widget (SafeTap)
    case deadManSwitch       // Countdown timer expired without user dismissal

    /// Must not make sound or show anything on this phone (attacker may be watching).
    var isSilent: Bool { self == .duressPassword }
}

enum SOSResolution: String, Codable {
    case guardianConfirmedSafe
    case protectedCancelled
    case responderHandled
    case falseAlarm
    case timeout
}

// MARK: - Escalation

enum EscalationState: String, Codable {
    case initiated           // SOS just fired
    case hop1_notified       // On-duty guardian notified, waiting response
    case hop1_acknowledged   // Guardian saw it
    case hop2_allNotified    // All guardians + backup contacts notified (push + SMS)
    case hop3_voiceCalling   // Auto voice call loop in progress
    case hop3_exhausted      // All voice call attempts exhausted, no pickup
    case frozen              // Someone clicked "I've taken over"
    case resolved
    case hop4_shareSent      // Emergency link texted to guardians
    case exhausted           // All voice rounds done without a response
    case no_guardians        // Nobody to escalate to — emergency contacts texted
    case unknown             // Newer server state this build doesn't know

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EscalationState(rawValue: raw) ?? .unknown
    }
}

// MARK: - Check-In

struct CheckInEvent: Codable, Identifiable {
    let id: String
    let userId: String
    let timestamp: Date
    let location: Location?
    let note: String?            // Optional "I'm at school" etc.

    static func create(userId: String, location: Location?) -> CheckInEvent {
        CheckInEvent(
            id: UUID().uuidString,
            userId: userId,
            timestamp: Date(),
            location: location,
            note: nil
        )
    }
}

// MARK: - Timeline Entry

struct TimelineEntry: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let type: TimelineEntryType
    let description: String
    let detail: String?
}

enum TimelineEntryType: String, Codable {
    case checkIn
    case sosTriggered
    case sosResolved
    case enteredSafeZone
    case leftSafeZone
    case missedCheckIn
    case guardianAlert
    case batteryLow
    case phoneInactive
    case fallDetected
    case locationUpdate
    case homeTimerSet
    case homeTimerDismissed
    case homeTimerExpired
    case arrivalReport
    case itineraryAdded
    case trackingPaused
    case trackingResumed
    // Written by the backend (device.ts, silentAlarm*.ts, voiceNote.ts)
    case bleSeparation = "ble_separation"
    case silentAlarmConfirmed = "silent_alarm_confirmed"
    case silentAlarmMissed = "silent_alarm_missed"
    case silentAlarmEscalated = "silent_alarm_escalated"
    case voiceNote
    /// Any type this build doesn't know yet — shown generically instead of
    /// failing the whole timeline decode.
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TimelineEntryType(rawValue: raw) ?? .other
    }
}

// MARK: - Safe Zone

struct SafeZone: Codable, Identifiable {
    let id: String
    var name: String                 // "Home", "School", "Work"
    var latitude: Double
    var longitude: Double
    var radius: Double               // meters
    var isAutoSuggested: Bool        // true if from dwell-point clustering
    var visitFrequency: Int          // Times visited in last 30 days
    var typicalHours: ClosedRange<Int>?  // e.g. 22...7 for home

    var coordinate: (Double, Double) { (latitude, longitude) }
}

// MARK: - Alert

struct Alert: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let level: AlertLevel
    let title: String
    let body: String
    let reasons: [String]            // Explainable reasons for the alert
    let protectedPersonId: String
    var acknowledged: Bool
    var acknowledgedBy: String?
    var acknowledgedAt: Date?
}

enum AlertLevel: String, Codable {
    case info       // Blue — informational
    case reminder   // Yellow — gentle nudge
    case warning    // Orange — needs attention
    case critical   // Red — SOS or severe anomaly
}

// MARK: - Family Feed

struct FamilyPost: Codable, Identifiable {
    let id: String
    let authorId: String
    let authorName: String
    let authorInitial: String
    var authorAvatarPath: String?
    var text: String
    var mediaURLs: [String]
    let createdAt: Date
    var comments: [FamilyComment]
    var commentCount: Int
    var latitude: Double?
    var longitude: Double?
    var locationName: String?
}

struct FamilyComment: Codable, Identifiable {
    let id: String
    let authorId: String
    let authorName: String
    let authorInitial: String
    var authorAvatarPath: String?
    let text: String
    let createdAt: Date
}

// MARK: - Heartbeat Signal

struct HeartbeatSignal: Codable {
    let userId: String
    let timestamp: Date
    let source: HeartbeatSource
    let batteryLevel: Double?
    let batteryState: BatteryState?
    let location: Location?
}

enum HeartbeatSource: String, Codable {
    case appForeground          // App became active
    case significantLocation    // CLSignificantLocationChange fired
    case silentPush             // Background push wake-up
    case pushReceipt            // User interacted with a notification
    case regionEvent            // Entered/exited geofence
    case watchSync              // Watch sent data via WatchConnectivity
}
