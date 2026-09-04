import UIKit
import Combine

// MARK: - App Coordinator
//
// Central nervous system of the app. Wires together all services
// and algorithms, manages state, and routes events between layers.

final class AppCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var currentUser: User?
    @Published var userRole: UserRole = .protected_
    @Published var protectedPersons: [ProtectedPerson] = []  // Guardian sees these
    @Published var myGuardians: [Guardian] = []               // Protected person sees these
    @Published var activeSOSEvent: SOSEvent?
    @Published var currentRiskScores: [String: BaselineScorer.RiskScore] = [:]
    @Published var currentCoverage: DutyScheduler.DayCoverage?

    // MARK: - Services

    let locationManager = AdaptiveLocationManager()
    let motionService = MotionService()
    let heartbeatService = HeartbeatService()
    let pushService = PushService()
    let escalationEngine = EscalationEngine()
    let baselineScorer = BaselineScorer()
    let dutyScheduler = DutyScheduler()
    let deviceHealthMonitor = DeviceHealthMonitor()

    // MARK: - Init

    init() {
        wireServices()
    }

    // MARK: - Service Wiring

    private func wireServices() {

        // Location → Heartbeat
        locationManager.onLocationReport = { [weak self] location in
            self?.heartbeatService.recordBeat(source: .significantLocation, location: location)
            self?.handleLocationUpdate(location)
        }

        // Location → Safe zone events
        locationManager.onSafeZoneEnter = { [weak self] zone in
            self?.addTimelineEntry(type: .enteredSafeZone, description: "进入安全区「\(zone.name)」")
        }

        locationManager.onSafeZoneExit = { [weak self] zone in
            self?.addTimelineEntry(type: .leftSafeZone, description: "离开安全区「\(zone.name)」")
        }

        // Location → Auto-discover safe zones
        locationManager.onDwellPointDiscovered = { [weak self] dwellPoint in
            guard let self else { return }
            let suggestedZone = SafeZone(
                id: UUID().uuidString,
                name: dwellPoint.suggestedName ?? "常去地点",
                latitude: dwellPoint.latitude,
                longitude: dwellPoint.longitude,
                radius: 200,
                isAutoSuggested: true,
                visitFrequency: dwellPoint.totalVisits,
                typicalHours: nil
            )
            // In production, surface this to UI for user confirmation
            print("[Coordinator] Discovered dwell point: \(suggestedZone.name) at (\(suggestedZone.latitude), \(suggestedZone.longitude))")
        }

        // Motion → Fall detection
        motionService.onFallCandidate = { [weak self] in
            self?.handleFallCandidate()
        }

        motionService.onFallConfirmed = { [weak self] in
            self?.handleFallConfirmed()
        }

        // Heartbeat → Server reporting
        heartbeatService.onHeartbeat = { [weak self] signal in
            self?.reportHeartbeatToServer(signal)
        }

        // Push → SOS handling
        pushService.onSOSTakenOver = { [weak self] sosId in
            self?.handleSOSTakenOver(sosId: sosId)
        }

        pushService.onCheckInFromNotification = { [weak self] in
            self?.performCheckIn()
        }

        // Escalation → Notifications
        escalationEngine.onSendNotification = { [weak self] request in
            self?.sendNotification(request)
        }

        escalationEngine.onEscalationFrozen = { [weak self] session, guardianId in
            self?.addTimelineEntry(
                type: .sosResolved,
                description: "守护者已接手处理"
            )
            _ = self  // Silence unused warning
        }
    }

    // MARK: - SOS Trigger

    func triggerSOS(method: SOSTriggerMethod = .longPress) {
        let sosEvent = SOSEvent(
            id: UUID().uuidString,
            protectedPersonId: currentUser?.id ?? "",
            triggeredAt: Date(),
            triggerMethod: method,
            location: nil,  // Will be filled by location manager
            batteryLevel: Double(UIDevice.current.batteryLevel),
            escalationState: .initiated,
            resolvedAt: nil,
            resolvedBy: nil,
            resolution: nil
        )

        activeSOSEvent = sosEvent

        // Switch location to SOS mode (max accuracy, max frequency)
        locationManager.enterSOSMode()

        // Add to timeline
        addTimelineEntry(type: .sosTriggered, description: "触发紧急求助（\(method.rawValue)）")

        // Start escalation chain
        // In production, this would go through the server
        // For now, handle locally for the on-device demo
        print("[Coordinator] SOS triggered via \(method.rawValue)")
    }

    func cancelSOS() {
        guard let sos = activeSOSEvent else { return }

        escalationEngine.resolve(by: currentUser?.id ?? "", resolution: .protectedCancelled)
        activeSOSEvent = nil
        locationManager.exitSOSMode()

        addTimelineEntry(type: .sosResolved, description: "取消了紧急求助")
        _ = sos  // Used for any cleanup
    }

    // MARK: - Check-In

    func performCheckIn(note: String? = nil) {
        guard let userId = currentUser?.id else { return }

        let checkIn = CheckInEvent.create(userId: userId, location: nil)

        addTimelineEntry(type: .checkIn, description: note ?? "报平安")

        // Report to server
        print("[Coordinator] Check-in recorded: \(checkIn.id)")
    }

    // MARK: - Event Handlers

    private func handleLocationUpdate(_ location: Location) {
        // In production, report to server for guardian visibility
    }

    private func handleFallCandidate() {
        // Show 60-second confirmation dialog
        // If user doesn't respond → handleFallConfirmed()
        print("[Coordinator] Fall candidate detected — showing confirmation dialog")
    }

    private func handleFallConfirmed() {
        // User didn't respond to fall confirmation → trigger SOS
        triggerSOS(method: .fallDetection)
    }

    private func handleSOSTakenOver(sosId: String) {
        // Guardian pressed "I've taken over"
        escalationEngine.freeze(by: "guardian")  // Would use real guardian ID
    }

    private func reportHeartbeatToServer(_ signal: HeartbeatSignal) {
        // In production, POST to /v1/heartbeat
        #if DEBUG
        print("[Coordinator] Heartbeat: \(signal.source.rawValue) at \(signal.timestamp)")
        #endif
    }

    private func sendNotification(_ request: NotificationRequest) {
        // In production, POST to server which sends via APNs/FCM
        // For local demo, fire a local notification
        if request.priority == .critical {
            pushService.fireCriticalSOSAlert(
                protectedPersonName: "被守护者",
                locationDescription: request.body,
                sosEventId: request.data["sos_id"] ?? ""
            )
        }
    }

    // MARK: - Timeline

    private var timeline: [TimelineEntry] = []

    private func addTimelineEntry(type: TimelineEntryType, description: String) {
        let entry = TimelineEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            type: type,
            description: description,
            detail: nil
        )
        timeline.insert(entry, at: 0)
    }

    // MARK: - Risk Score Refresh

    func refreshRiskScores() {
        for person in protectedPersons {
            let score = baselineScorer.computeRiskScore(
                personId: person.id,
                lastCheckIn: person.lastCheckIn,
                lastHeartbeat: person.lastPhoneActivity,
                currentLocation: person.lastKnownLocation,
                batteryLevel: person.batteryLevel,
                batteryState: person.batteryState,
                regionRiskLevel: 0.3,  // Would come from server
                timeZone: person.user.timeZone
            )
            currentRiskScores[person.id] = score
        }
    }

    // MARK: - Duty Coverage Refresh

    func refreshDutyCoverage() {
        guard let firstPerson = protectedPersons.first else { return }
        currentCoverage = dutyScheduler.buildDayCoverage(
            protectedPerson: firstPerson,
            guardians: firstPerson.guardians
        )
    }

    // MARK: - Import

    func importDeviceToken(_ token: Data) {
        pushService.didRegisterForRemoteNotifications(withDeviceToken: token)
    }
}
