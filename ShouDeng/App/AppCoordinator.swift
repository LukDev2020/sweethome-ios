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
    @Published var showSignup = false
    @Published var signupPhone: String?
    @Published var signupCountry: CountryCode?
    @Published var timeline: [TimelineEntry] = []

    // MARK: - Infrastructure

    let offlineQueue = OfflineQueue()
    let apiClient: APIClient
    let authManager: AuthManager
    let localStore = LocalStore.shared

    // MARK: - Services

    let locationManager = AdaptiveLocationManager()
    let motionService = MotionService()
    let heartbeatService = HeartbeatService()
    let pushService = PushService()
    let escalationEngine = EscalationEngine()
    let baselineScorer = BaselineScorer()
    let dutyScheduler = DutyScheduler()
    let deviceHealthMonitor = DeviceHealthMonitor()
    let crashReporter = CrashReporter.shared
    let storeKitManager: StoreKitManager

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        let config = APIClient.Config(
            baseURL: Self.resolveBaseURL()
        )
        apiClient = APIClient(config: config, offlineQueue: offlineQueue)
        #if DEBUG
        print("[AppCoordinator] API base URL: \(config.baseURL)")
        #endif
        authManager = AuthManager(api: apiClient)
        storeKitManager = StoreKitManager(apiClient: apiClient)

        // Wire 401 auto-refresh: when server returns 401, attempt token refresh
        apiClient.onUnauthorized = { [weak self] in
            guard let self else { return false }
            do {
                try await self.authManager.refreshToken()
                return true
            } catch {
                await MainActor.run { self.authManager.logout() }
                return false
            }
        }

        wireServices()
        restoreLocalState()
        observeAuthState()
    }

    // MARK: - Base URL

    private static func resolveBaseURL() -> String {
        if let override = Bundle.main.infoDictionary?["API_BASE_URL"] as? String, !override.isEmpty {
            return override
        }
        #if DEBUG
        return "http://127.0.0.1:5001/sweethome-d1edd/us-central1/api"
        #else
        return "https://api.shoudeng.app"
        #endif
    }

    // MARK: - Restore Local State

    private func restoreLocalState() {
        if let user = localStore.loadCurrentUser() {
            currentUser = user
        }
        if let role = localStore.loadUserRole() {
            userRole = role
        }
        myGuardians = localStore.loadGuardians()
        protectedPersons = localStore.loadProtectedPersons()
        activeSOSEvent = localStore.loadActiveSOSEvent()
        timeline = localStore.loadTimeline()

        // Load safe zones into location manager
        let zones = localStore.loadSafeZones()
        if !zones.isEmpty {
            locationManager.updateSafeZones(zones)
        }
    }

    // MARK: - Auth State Observer

    private func observeAuthState() {
        authManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .loggedIn(let userId):
                    UserDefaults.standard.set(userId, forKey: "currentUserId")
                    // Set role from login/signup response immediately
                    if let roleStr = self.authManager.lastLoginRole,
                       let role = UserRole(rawValue: roleStr) {
                        self.userRole = role
                        self.localStore.saveUserRole(role)
                    }
                    self.onLoginComplete()
                case .loggedOut:
                    self.onLogout()
                case .unknown:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func onLoginComplete() {
        // Flush any queued offline requests
        Task { await apiClient.flushOfflineQueue() }

        // Fetch fresh data from server
        Task { await fetchUserProfile() }
    }

    private func onLogout() {
        currentUser = nil
        protectedPersons = []
        myGuardians = []
        activeSOSEvent = nil
        timeline = []
        showSignup = false
        signupPhone = nil
        signupCountry = nil
        localStore.clearAll()
        UserDefaults.standard.set(false, forKey: "onboardingComplete")
    }

    // MARK: - Fetch User Profile

    func fetchUserProfile() async {
        do {
            let profile: UserProfileResponse = try await apiClient.get("/v1/user/me")
            let user = User(
                id: profile.id,
                displayName: profile.displayName,
                role: UserRole(rawValue: profile.role) ?? .protected_,
                avatarInitial: profile.avatarInitial,
                timeZone: TimeZone(identifier: profile.timeZone) ?? .current,
                countryCode: profile.countryCode,
                cityName: profile.cityName,
                createdAt: profile.createdAt
            )
            await MainActor.run {
                self.currentUser = user
                self.userRole = user.role
                self.localStore.saveCurrentUser(user)
                self.localStore.saveUserRole(user.role)
            }
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to fetch profile: \(error)")
            #endif
        }
    }

    // MARK: - Fetch Data

    func fetchProtectedPersons() async {
        do {
            let persons: [ProtectedPersonStatusResponse] = try await apiClient.get("/v1/guardian/protected-persons")
            let mapped = persons.map { p in
                ProtectedPerson(
                    id: p.personId,
                    user: User(
                        id: p.personId,
                        displayName: p.displayName,
                        role: .protected_,
                        avatarInitial: String(p.displayName.prefix(1)),
                        timeZone: .current,
                        countryCode: "",
                        cityName: p.locationAddress ?? "",
                        createdAt: Date()
                    ),
                    guardians: [],
                    protectionLayers: p.protectionLayers,
                    lastCheckIn: p.lastCheckIn,
                    lastKnownLocation: p.latitude.flatMap { lat in
                        p.longitude.map { lng in
                            Location(
                                latitude: lat, longitude: lng,
                                accuracy: 0, altitude: nil, speed: nil,
                                timestamp: p.locationTimestamp ?? Date(),
                                address: p.locationAddress
                            )
                        }
                    },
                    batteryLevel: p.batteryLevel,
                    batteryState: p.batteryState,
                    lastPhoneActivity: p.lastPhoneActivity,
                    status: p.status
                )
            }
            await MainActor.run {
                self.protectedPersons = mapped
                self.localStore.saveProtectedPersons(mapped)
            }
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to fetch protected persons: \(error)")
            #endif
        }
    }

    func fetchGuardians() async {
        do {
            let guardians: [Guardian] = try await apiClient.get("/v1/protected/guardians")
            await MainActor.run {
                self.myGuardians = guardians
                self.localStore.saveGuardians(guardians)
            }
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to fetch guardians: \(error)")
            #endif
        }
    }

    // MARK: - Service Wiring

    private func wireServices() {

        // Location → Heartbeat + Server
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
        locationManager.onDwellPointDiscovered = { dwellPoint in
            #if DEBUG
            print("[Coordinator] Discovered dwell point: \(dwellPoint.suggestedName ?? "常去地点") at (\(dwellPoint.latitude), \(dwellPoint.longitude))")
            #endif
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
            _ = session
            _ = guardianId
        }

        // Voice call → server API
        escalationEngine.onInitiateVoiceCall = { [weak self] guardianId, sosEventId in
            self?.initiateVoiceCall(guardianId: guardianId, sosEventId: sosEventId)
        }
    }

    // MARK: - SOS Trigger

    func triggerSOS(method: SOSTriggerMethod = .longPress) {
        let sosEvent = SOSEvent(
            id: UUID().uuidString,
            protectedPersonId: currentUser?.id ?? "",
            triggeredAt: Date(),
            triggerMethod: method,
            location: nil,
            batteryLevel: Double(UIDevice.current.batteryLevel),
            escalationState: .initiated,
            resolvedAt: nil,
            resolvedBy: nil,
            resolution: nil
        )

        activeSOSEvent = sosEvent
        localStore.saveActiveSOSEvent(sosEvent)

        // Switch location to SOS mode
        locationManager.enterSOSMode()

        addTimelineEntry(type: .sosTriggered, description: "触发紧急求助（\(method.rawValue)）")

        // Report to server
        apiClient.postQueued("/v1/sos/trigger", body: SOSTriggerRequest(
            protectedPersonId: currentUser?.id ?? "",
            triggerMethod: method,
            latitude: nil,
            longitude: nil,
            batteryLevel: Double(UIDevice.current.batteryLevel)
        ))
    }

    func cancelSOS() {
        guard let sos = activeSOSEvent else { return }

        escalationEngine.resolve(by: currentUser?.id ?? "", resolution: .protectedCancelled)
        activeSOSEvent = nil
        localStore.saveActiveSOSEvent(nil)
        locationManager.exitSOSMode()

        addTimelineEntry(type: .sosResolved, description: "取消了紧急求助")

        apiClient.postQueued("/v1/sos/resolve", body: SOSResolveRequest(
            sosEventId: sos.id,
            resolvedBy: currentUser?.id ?? "",
            resolution: .protectedCancelled
        ))
    }

    // MARK: - Check-In

    func performCheckIn(note: String? = nil) {
        guard let userId = currentUser?.id else { return }

        let checkIn = CheckInEvent.create(userId: userId, location: nil)

        addTimelineEntry(type: .checkIn, description: note ?? "报平安")

        apiClient.postQueued("/v1/checkin", body: CheckInRequest(
            userId: userId,
            latitude: nil,
            longitude: nil,
            note: note
        ))
        _ = checkIn
    }

    // MARK: - Event Handlers

    private func handleLocationUpdate(_ location: Location) {
        apiClient.postQueued("/v1/location/report", body: LocationReportRequest(
            userId: currentUser?.id ?? "",
            latitude: location.latitude,
            longitude: location.longitude,
            accuracy: location.accuracy,
            altitude: location.altitude,
            speed: location.speed,
            timestamp: location.timestamp,
            isInSafeZone: location.isInSafeZone,
            safeZoneName: location.safeZoneName
        ))
    }

    private func handleFallCandidate() {
        #if DEBUG
        print("[Coordinator] Fall candidate detected — showing confirmation dialog")
        #endif
    }

    private func handleFallConfirmed() {
        triggerSOS(method: .fallDetection)
    }

    private func handleSOSTakenOver(sosId: String) {
        escalationEngine.freeze(by: "guardian")
    }

    private func reportHeartbeatToServer(_ signal: HeartbeatSignal) {
        apiClient.postQueued("/v1/heartbeat", body: HeartbeatRequest(
            userId: signal.userId,
            timestamp: signal.timestamp,
            source: signal.source,
            batteryLevel: signal.batteryLevel,
            batteryState: signal.batteryState,
            latitude: signal.location?.latitude,
            longitude: signal.location?.longitude,
            accuracy: signal.location?.accuracy
        ))
    }

    private func initiateVoiceCall(guardianId: String, sosEventId: String) {
        apiClient.postQueued("/v1/voice-call", body: VoiceCallRequest(
            guardianId: guardianId,
            sosEventId: sosEventId,
            protectedPersonName: currentUser?.displayName ?? "被守护者",
            locationDescription: nil
        ))
    }

    private func sendNotification(_ request: NotificationRequest) {
        if request.priority == .critical {
            pushService.fireCriticalSOSAlert(
                protectedPersonName: currentUser?.displayName ?? "被守护者",
                locationDescription: request.body,
                sosEventId: request.data["sos_id"] ?? ""
            )
        }
    }

    // MARK: - Device Token

    func registerDeviceToken(_ token: Data) {
        pushService.didRegisterForRemoteNotifications(withDeviceToken: token)

        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        apiClient.postQueued("/v1/device/token", body: DeviceTokenRequest(
            token: tokenString,
            platform: "ios",
            environment: {
                #if DEBUG
                return "development"
                #else
                return "production"
                #endif
            }()
        ))
    }

    // MARK: - Timeline

    func addTimelineEntry(type: TimelineEntryType, description: String) {
        let entry = TimelineEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            type: type,
            description: description,
            detail: nil
        )
        timeline.insert(entry, at: 0)

        // Keep last 200 entries in memory
        if timeline.count > 200 {
            timeline = Array(timeline.prefix(200))
        }
        localStore.saveTimeline(timeline)
    }

    // MARK: - Subscription

    func fetchSubscription() async {
        await storeKitManager.refreshSubscriptionStatus()
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
                regionRiskLevel: 0.3,
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
}
