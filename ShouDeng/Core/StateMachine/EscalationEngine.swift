import Foundation

// MARK: - Escalation Engine: Multi-Hop State Machine with Dynamic Timing
//
// When an SOS fires or a red-level anomaly is detected, the escalation engine
// walks through a chain of notification hops. Each hop has a dynamic wait time
// that adjusts based on:
//   - Time of day in the guardian's time zone (night = shorter wait)
//   - Regional risk level (high risk = shorter wait)
//   - Guardian's historical response speed (fast responders get more time)
//
// The critical UX detail: "I've taken over" IMMEDIATELY freezes the entire chain.
// Nothing is worse than a guardian who's already on the phone hearing the system
// blast alerts to everyone else.

final class EscalationEngine {

    // MARK: - Configuration

    struct Config {
        // Hop 1: On-duty guardian
        var hop1BaseWaitSec: TimeInterval = 180      // 3 minutes
        var hop1NightWaitSec: TimeInterval = 90      // 1.5 minutes (they might be asleep)
        var hop1FastResponderBonusSec: TimeInterval = 60  // +1 min if avg response < 60s

        // Hop 2: All guardians + backup contacts
        var hop2WaitSec: TimeInterval = 300           // 5 minutes — all notified simultaneously

        // Hop 3: Response center (paid)
        var hop3WaitSec: TimeInterval = 0             // Immediate once queued

        // Timing adjustments
        var nightHoursStart: Int = 23                 // 11 PM
        var nightHoursEnd: Int = 7                    // 7 AM
        var highRiskRegionMultiplier: Double = 0.6    // Shorten all waits by 40%

        // Retry
        var maxRetryAttempts: Int = 3
        var retryIntervalSec: TimeInterval = 60
    }

    // MARK: - Hop Definition

    struct Hop {
        let level: Int                    // 1, 2, 3, 4
        let type: HopType
        let notifyTargets: [String]       // Guardian IDs or "response_center"
        let waitDuration: TimeInterval    // Dynamic, computed at runtime
        let startedAt: Date
        var acknowledgedBy: String?
        var acknowledgedAt: Date?

        var isAcknowledged: Bool { acknowledgedBy != nil }

        var timeRemaining: TimeInterval {
            max(0, waitDuration - Date().timeIntervalSince(startedAt))
        }

        var isExpired: Bool { timeRemaining <= 0 }
    }

    enum HopType: String {
        case onDutyGuardian
        case allGuardians
        case responseCenter
        case localRescue
    }

    // MARK: - Escalation Session

    struct Session {
        let id: String
        let sosEvent: SOSEvent
        let startedAt: Date
        var currentHop: Int = 1
        var hops: [Hop] = []
        var isFrozen: Bool = false         // "I've taken over" was pressed
        var frozenBy: String?
        var frozenAt: Date?
        var isResolved: Bool = false
        var resolvedAt: Date?

        var elapsedSec: TimeInterval {
            Date().timeIntervalSince(startedAt)
        }

        var activeHop: Hop? {
            hops.last { !$0.isAcknowledged && !$0.isExpired }
        }
    }

    // MARK: - Properties

    private let config: Config
    private(set) var activeSession: Session?

    // Callbacks
    var onHopStarted: ((Hop) -> Void)?
    var onHopAcknowledged: ((Hop, String) -> Void)?
    var onEscalationFrozen: ((Session, String) -> Void)?
    var onEscalationResolved: ((Session) -> Void)?
    var onSendNotification: ((NotificationRequest) -> Void)?

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Start Escalation

    func startEscalation(
        sosEvent: SOSEvent,
        protectedPerson: ProtectedPerson,
        allGuardians: [Guardian]
    ) -> Session {

        let session = Session(
            id: UUID().uuidString,
            sosEvent: sosEvent,
            startedAt: Date()
        )
        activeSession = session

        // Start hop 1: notify on-duty guardian
        let onDutyGuardian = allGuardians.first { $0.isOnDuty }
            ?? allGuardians.first  // Fallback to first guardian if no one on duty

        if let guardian = onDutyGuardian {
            startHop1(session: session, guardian: guardian, protectedPerson: protectedPerson)
        } else {
            // No guardians at all — skip to hop 3 (response center)
            startHop3(protectedPerson: protectedPerson)
        }

        return session
    }

    // MARK: - Hop 1: On-Duty Guardian

    private func startHop1(session: Session, guardian: Guardian, protectedPerson: ProtectedPerson) {
        let waitDuration = computeHop1Wait(
            guardian: guardian,
            protectedPerson: protectedPerson
        )

        let hop = Hop(
            level: 1,
            type: .onDutyGuardian,
            notifyTargets: [guardian.id],
            waitDuration: waitDuration,
            startedAt: Date()
        )

        activeSession?.hops.append(hop)
        onHopStarted?(hop)

        // Send push notification
        onSendNotification?(NotificationRequest(
            targetUserIds: [guardian.id],
            title: "\(protectedPerson.user.displayName)正在求助",
            body: formatSOSBody(sosEvent: session.sosEvent, protectedPerson: protectedPerson),
            priority: .critical,
            category: .sosAlert,
            data: [
                "sos_id": session.sosEvent.id,
                "escalation_hop": "1",
                "protected_person_id": protectedPerson.id
            ]
        ))

        // Schedule hop 2 after wait expires
        scheduleNextHop(after: waitDuration) { [weak self] in
            guard let self, let session = self.activeSession,
                  !session.isFrozen, !session.isResolved else { return }

            // Check if hop 1 was acknowledged
            if let lastHop = session.hops.last, !lastHop.isAcknowledged {
                self.startHop2(protectedPerson: protectedPerson)
            }
        }
    }

    // MARK: - Hop 2: All Guardians + Backup Contacts

    private func startHop2(protectedPerson: ProtectedPerson) {
        guard let session = activeSession, !session.isFrozen else { return }

        let allTargets = protectedPerson.guardians.map { $0.id }

        let hop = Hop(
            level: 2,
            type: .allGuardians,
            notifyTargets: allTargets,
            waitDuration: config.hop2WaitSec,
            startedAt: Date()
        )

        activeSession?.hops.append(hop)
        activeSession?.currentHop = 2
        onHopStarted?(hop)

        // Notify ALL guardians simultaneously
        onSendNotification?(NotificationRequest(
            targetUserIds: allTargets,
            title: "紧急：\(protectedPerson.user.displayName)需要帮助",
            body: "值班守护者未响应。任何人点击「我已接手」即可接管。",
            priority: .critical,
            category: .sosAlert,
            data: [
                "sos_id": session.sosEvent.id,
                "escalation_hop": "2",
                "protected_person_id": protectedPerson.id
            ]
        ))

        // Schedule hop 3 (response center)
        scheduleNextHop(after: config.hop2WaitSec) { [weak self] in
            guard let self, let session = self.activeSession,
                  !session.isFrozen, !session.isResolved else { return }

            if let lastHop = session.hops.last, !lastHop.isAcknowledged {
                self.startHop3(protectedPerson: protectedPerson)
            }
        }
    }

    // MARK: - Hop 3: Response Center (Paid Tier)

    private func startHop3(protectedPerson: ProtectedPerson) {
        guard let session = activeSession, !session.isFrozen else { return }

        let hop = Hop(
            level: 3,
            type: .responseCenter,
            notifyTargets: ["response_center"],
            waitDuration: config.hop3WaitSec,
            startedAt: Date()
        )

        activeSession?.hops.append(hop)
        activeSession?.currentHop = 3
        onHopStarted?(hop)

        // Queue to response center
        onSendNotification?(NotificationRequest(
            targetUserIds: ["response_center"],
            title: "新工单：\(protectedPerson.user.displayName)",
            body: "所有家人未响应，需专员介入。位置：\(protectedPerson.lastKnownLocation?.address ?? "未知")",
            priority: .critical,
            category: .responderDispatch,
            data: [
                "sos_id": session.sosEvent.id,
                "escalation_hop": "3",
                "protected_person_id": protectedPerson.id,
                "location_lat": String(protectedPerson.lastKnownLocation?.latitude ?? 0),
                "location_lng": String(protectedPerson.lastKnownLocation?.longitude ?? 0)
            ]
        ))
    }

    // MARK: - Freeze ("I've Taken Over")

    /// Immediately stops the entire escalation chain.
    /// This is the most important UX action in the product.
    func freeze(by guardianId: String) {
        guard var session = activeSession, !session.isFrozen else { return }

        session.isFrozen = true
        session.frozenBy = guardianId
        session.frozenAt = Date()
        activeSession = session

        // Cancel all pending timers
        cancelScheduledHops()

        onEscalationFrozen?(session, guardianId)

        // Notify all other guardians that someone has taken over
        let otherGuardians = session.hops
            .flatMap { $0.notifyTargets }
            .filter { $0 != guardianId && $0 != "response_center" }

        if !otherGuardians.isEmpty {
            onSendNotification?(NotificationRequest(
                targetUserIds: Array(Set(otherGuardians)),
                title: "已有人接手",
                body: "守护者已接手处理，无需进一步行动。",
                priority: .high,
                category: .escalationUpdate,
                data: ["sos_id": session.sosEvent.id, "action": "frozen"]
            ))
        }
    }

    // MARK: - Resolve

    func resolve(by userId: String, resolution: SOSResolution) {
        guard var session = activeSession else { return }

        session.isResolved = true
        session.resolvedAt = Date()
        activeSession = session

        cancelScheduledHops()
        onEscalationResolved?(session)
    }

    // MARK: - Acknowledge Hop

    func acknowledgeHop(guardianId: String) {
        guard var session = activeSession else { return }

        if var lastHop = session.hops.last {
            lastHop.acknowledgedBy = guardianId
            lastHop.acknowledgedAt = Date()
            session.hops[session.hops.count - 1] = lastHop
            activeSession = session
            onHopAcknowledged?(lastHop, guardianId)
        }
    }

    // MARK: - Dynamic Wait Time Computation

    /// Hop 1 wait time adjusts based on context
    private func computeHop1Wait(guardian: Guardian, protectedPerson: ProtectedPerson) -> TimeInterval {
        var wait = config.hop1BaseWaitSec

        // Night adjustment: if guardian's local time is nighttime, shorten wait
        let guardianHour = currentHour(in: guardian.user.timeZone)
        if isNightHour(guardianHour) {
            wait = config.hop1NightWaitSec
        }

        // Fast responder bonus: if this guardian historically responds in < 60s, give more time
        if guardian.averageResponseTime < 60 && guardian.averageResponseTime > 0 {
            wait += config.hop1FastResponderBonusSec
        }

        // High-risk region: shorten all waits
        // (regionRiskLevel would come from server, simplified here)
        // wait *= config.highRiskRegionMultiplier  // Uncomment when regional risk is available

        return max(wait, 30)  // Minimum 30 seconds
    }

    private func currentHour(in timeZone: TimeZone) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: timeZone, from: Date())
        return components.hour ?? 12
    }

    private func isNightHour(_ hour: Int) -> Bool {
        if config.nightHoursStart > config.nightHoursEnd {
            // Wraps midnight: e.g., 23-7
            return hour >= config.nightHoursStart || hour < config.nightHoursEnd
        } else {
            return hour >= config.nightHoursStart && hour < config.nightHoursEnd
        }
    }

    // MARK: - Notification Formatting

    private func formatSOSBody(sosEvent: SOSEvent, protectedPerson: ProtectedPerson) -> String {
        var parts: [String] = []

        if let loc = sosEvent.location {
            parts.append(loc.address ?? String(format: "%.4f, %.4f", loc.latitude, loc.longitude))
        }

        if let battery = protectedPerson.batteryLevel {
            parts.append(String(format: "电量%.0f%%", battery * 100))
        }

        let methodDesc: String
        switch sosEvent.triggerMethod {
        case .longPress: methodDesc = "手动触发"
        case .watchQuickAction: methodDesc = "手表触发"
        case .bluetoothButton: methodDesc = "按钮触发"
        case .duressPassword: methodDesc = "胁迫密码触发"
        case .fallDetection: methodDesc = "跌倒检测触发"
        case .voiceWakeWord: methodDesc = "语音触发"
        }
        parts.append(methodDesc)

        return parts.joined(separator: " · ")
    }

    // MARK: - Timer Management

    private var scheduledTimers: [Timer] = []

    private func scheduleNextHop(after interval: TimeInterval, action: @escaping () -> Void) {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            action()
        }
        scheduledTimers.append(timer)
    }

    private func cancelScheduledHops() {
        scheduledTimers.forEach { $0.invalidate() }
        scheduledTimers.removeAll()
    }
}

// MARK: - Notification Request

struct NotificationRequest {
    let targetUserIds: [String]
    let title: String
    let body: String
    let priority: NotificationPriority
    let category: NotificationCategory
    let data: [String: String]

    enum NotificationPriority {
        case normal
        case high
        case critical    // iOS Critical Alert — bypasses DND
    }

    enum NotificationCategory: String {
        case sosAlert
        case escalationUpdate
        case checkInReminder
        case anomalyWarning
        case responderDispatch
    }
}
