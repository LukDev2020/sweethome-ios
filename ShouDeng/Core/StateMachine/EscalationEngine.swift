import Foundation

// MARK: - Escalation Engine: Multi-Hop State Machine with Dynamic Timing
//
// From PDF section 11: 升级状态机与自动外呼
//
// State machine:
//   IDLE → TRIGGERED → NOTIFYING_PRIMARY → NOTIFYING_ALL
//       → VOICE_CALLING → ACKNOWLEDGED / EXHAUSTED
//
// Each hop has dynamic wait time based on:
//   - Time of day in the guardian's time zone (night = shorter wait)
//   - Guardian's historical response speed (fast responders get more time)
//
// "I've taken over" IMMEDIATELY freezes the entire chain.
// 冻结必须是即时的：守护者最担心的情形是自己已在接打电话，
// 系统仍在向外发送警报，把全家惊动一遍。

final class EscalationEngine {

    // MARK: - Configuration

    struct Config {
        // Hop 1: On-duty guardian (push notification)
        var hop1BaseWaitSec: TimeInterval = 180      // 3 minutes
        var hop1NightWaitSec: TimeInterval = 90      // 1.5 minutes (they might be asleep)
        var hop1FastResponderBonusSec: TimeInterval = 60  // +1 min if avg response < 60s

        // Hop 2: All guardians (push + SMS, simultaneous)
        var hop2WaitSec: TimeInterval = 120           // 2 minutes — PDF: 同时发送，不再逐个等待

        // Hop 3: Auto voice call (循环直拨)
        var hop3MaxCallAttempts: Int = 3              // Max 3 attempts per person
        var hop3CallIntervalSec: TimeInterval = 30    // Between call attempts

        // Timing adjustments
        var nightHoursStart: Int = 23                 // 11 PM
        var nightHoursEnd: Int = 7                    // 7 AM

        // Retry
        var maxRetryAttempts: Int = 3
        var retryIntervalSec: TimeInterval = 60
    }

    // MARK: - Hop Definition

    struct Hop {
        let level: Int                    // 1, 2, 3
        let type: HopType
        let notifyTargets: [String]       // Guardian IDs
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
        case onDutyGuardian      // Hop 1: push to on-duty guardian
        case allGuardians        // Hop 2: push + SMS to all
        case voiceCall           // Hop 3: auto voice call loop
    }

    // MARK: - State Machine

    enum EngineState: String {
        case idle
        case triggered
        case notifyingPrimary       // Hop 1
        case notifyingAll           // Hop 2
        case voiceCalling           // Hop 3
        case acknowledged           // Someone confirmed
        case exhausted              // All attempts failed
    }

    // MARK: - Escalation Session

    struct Session {
        let id: String
        let sosEvent: SOSEvent
        let startedAt: Date
        var currentHop: Int = 1
        var hops: [Hop] = []
        var isFrozen: Bool = false
        var frozenBy: String?
        var frozenAt: Date?
        var isResolved: Bool = false
        var resolvedAt: Date?
        var state: EngineState = .triggered

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
    var onInitiateVoiceCall: ((String, String) -> Void)?  // (guardianId, sosEventId)

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
            ?? allGuardians.first

        if let guardian = onDutyGuardian {
            startHop1(session: session, guardian: guardian, protectedPerson: protectedPerson, allGuardians: allGuardians)
        } else {
            // No guardians — skip to voice call
            startHop3(protectedPerson: protectedPerson, allGuardians: allGuardians)
        }

        return session
    }

    // MARK: - Hop 1: On-Duty Guardian (Push)

    private func startHop1(session: Session, guardian: Guardian, protectedPerson: ProtectedPerson, allGuardians: [Guardian]) {
        let waitDuration = computeHop1Wait(guardian: guardian)

        let hop = Hop(
            level: 1,
            type: .onDutyGuardian,
            notifyTargets: [guardian.id],
            waitDuration: waitDuration,
            startedAt: Date()
        )

        activeSession?.hops.append(hop)
        activeSession?.state = .notifyingPrimary
        onHopStarted?(hop)

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

        scheduleNextHop(after: waitDuration) { [weak self] in
            guard let self, let session = self.activeSession,
                  !session.isFrozen, !session.isResolved else { return }

            if let lastHop = session.hops.last, !lastHop.isAcknowledged {
                self.startHop2(protectedPerson: protectedPerson, allGuardians: allGuardians)
            }
        }
    }

    // MARK: - Hop 2: All Guardians (Push + SMS, simultaneous)

    private func startHop2(protectedPerson: ProtectedPerson, allGuardians: [Guardian]) {
        guard let session = activeSession, !session.isFrozen else { return }

        let allTargets = allGuardians.map { $0.id }

        let hop = Hop(
            level: 2,
            type: .allGuardians,
            notifyTargets: allTargets,
            waitDuration: config.hop2WaitSec,
            startedAt: Date()
        )

        activeSession?.hops.append(hop)
        activeSession?.currentHop = 2
        activeSession?.state = .notifyingAll
        onHopStarted?(hop)

        // Notify ALL guardians simultaneously (push + SMS per PDF)
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

        // Schedule hop 3 (auto voice call)
        scheduleNextHop(after: config.hop2WaitSec) { [weak self] in
            guard let self, let session = self.activeSession,
                  !session.isFrozen, !session.isResolved else { return }

            if let lastHop = session.hops.last, !lastHop.isAcknowledged {
                self.startHop3(protectedPerson: protectedPerson, allGuardians: allGuardians)
            }
        }
    }

    // MARK: - Hop 3: Auto Voice Call (循环直拨)
    //
    // From PDF: 依次拨打，每人最多3次，接听后按键确认
    // Uses Twilio or similar CPaaS — client initiates via server API

    private func startHop3(protectedPerson: ProtectedPerson, allGuardians: [Guardian]) {
        guard let session = activeSession, !session.isFrozen else { return }

        let allTargets = allGuardians.map { $0.id }

        let hop = Hop(
            level: 3,
            type: .voiceCall,
            notifyTargets: allTargets,
            waitDuration: TimeInterval(config.hop3MaxCallAttempts) * config.hop3CallIntervalSec * Double(allTargets.count),
            startedAt: Date()
        )

        activeSession?.hops.append(hop)
        activeSession?.currentHop = 3
        activeSession?.state = .voiceCalling
        onHopStarted?(hop)

        // Initiate voice call loop via server
        for guardianId in allTargets {
            onInitiateVoiceCall?(guardianId, session.sosEvent.id)
        }

        // If nobody picks up after all attempts, mark exhausted
        let totalWait = hop.waitDuration
        scheduleNextHop(after: totalWait) { [weak self] in
            guard let self, let session = self.activeSession,
                  !session.isFrozen, !session.isResolved else { return }

            if let lastHop = session.hops.last, !lastHop.isAcknowledged {
                self.activeSession?.state = .exhausted
                print("[EscalationEngine] All voice call attempts exhausted")
            }
        }
    }

    // MARK: - Freeze ("I've Taken Over")
    //
    // 任一联系人执行「我已接手」或外呼按键确认：
    //   → 立即冻结整条链，停止全部后续动作
    //   → 状态转 ACKNOWLEDGED，记录接手人与时间

    func freeze(by guardianId: String) {
        guard var session = activeSession, !session.isFrozen else { return }

        session.isFrozen = true
        session.frozenBy = guardianId
        session.frozenAt = Date()
        session.state = .acknowledged
        activeSession = session

        cancelScheduledHops()

        onEscalationFrozen?(session, guardianId)

        // Notify all other guardians that someone has taken over
        let otherGuardians = session.hops
            .flatMap { $0.notifyTargets }
            .filter { $0 != guardianId }

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

    private func computeHop1Wait(guardian: Guardian) -> TimeInterval {
        var wait = config.hop1BaseWaitSec

        let guardianHour = currentHour(in: guardian.user.timeZone)
        if isNightHour(guardianHour) {
            wait = config.hop1NightWaitSec
        }

        // Fast responder bonus: historically responds in < 60s → give more time
        if guardian.averageResponseTime < 60 && guardian.averageResponseTime > 0 {
            wait += config.hop1FastResponderBonusSec
        }

        return max(wait, 30)  // Minimum 30 seconds
    }

    private func currentHour(in timeZone: TimeZone) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: timeZone, from: Date())
        return components.hour ?? 12
    }

    private func isNightHour(_ hour: Int) -> Bool {
        if config.nightHoursStart > config.nightHoursEnd {
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
