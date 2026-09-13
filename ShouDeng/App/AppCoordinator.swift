import UIKit
import Combine

// MARK: - App Coordinator
//
// Central nervous system of the app. Wires together all services
// and algorithms, manages state, and routes events between layers.

final class AppCoordinator: ObservableObject {

    // TEMP: Set to true to bypass login during development
    let devBypassLogin = true

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
    @Published var familyPosts: [FamilyPost] = []

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

        // Wire 401 auto-refresh: when server returns 401, attempt token refresh.
        // In dev bypass mode, suppress logout to avoid wiping local state.
        apiClient.onUnauthorized = { [weak self] in
            guard let self else { return false }
            #if DEBUG
            if self.devBypassLogin { return false }
            #endif
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
        #if DEBUG
        // In dev bypass mode, ensure a default user exists so profile/settings work
        if devBypassLogin && currentUser == nil {
            let devUser = User(
                id: "dev_local_user",
                displayName: "",
                role: .protected_,
                avatarInitial: "?",
                timeZone: .current,
                countryCode: "CN",
                cityName: "",
                createdAt: Date()
            )
            currentUser = devUser
            print("[AppCoordinator] Created dev seed user (empty profile)")
        } else if let u = currentUser {
            print("[AppCoordinator] Restored user: '\(u.displayName)' city='\(u.cityName)'")
        }
        #endif
        if let role = localStore.loadUserRole() {
            userRole = role
        }
        myGuardians = localStore.loadGuardians()
        protectedPersons = localStore.loadProtectedPersons()
        activeSOSEvent = localStore.loadActiveSOSEvent()
        timeline = localStore.loadTimeline()
        familyPosts = localStore.loadFamilyPosts()

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

        // Sync local notification preferences to server
        syncNotificationPrefs()
    }

    private func onLogout() {
        currentUser = nil
        protectedPersons = []
        myGuardians = []
        activeSOSEvent = nil
        timeline = []
        familyPosts = []
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
                        timeZone: p.timeZoneId.flatMap { TimeZone(identifier: $0) } ?? .current,
                        countryCode: p.countryCode ?? "",
                        cityName: p.cityName ?? p.locationAddress ?? "",
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

    func fetchTimeline() async {
        do {
            let response: TimelineResponse = try await apiClient.get("/v1/timeline")
            await MainActor.run {
                // Merge server entries with local-only entries
                let serverIds = Set(response.entries.map(\.id))
                let localOnly = timeline.filter { !serverIds.contains($0.id) }
                var merged = response.entries
                merged.append(contentsOf: localOnly)
                merged.sort { $0.timestamp > $1.timestamp }
                self.timeline = Array(merged.prefix(200))
                localStore.saveTimeline(self.timeline)
            }
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to fetch timeline: \(error)")
            #endif
            // Keep local timeline on failure
        }
    }

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

    // MARK: - Family Feed

    func fetchFamilyPosts() async {
        do {
            let serverPosts: [FamilyPost] = try await apiClient.get("/v1/family/posts")
            await MainActor.run {
                // Merge: keep local-only posts, add/update server posts
                let serverIds = Set(serverPosts.map(\.id))
                let localOnly = familyPosts.filter { !serverIds.contains($0.id) }
                var merged = serverPosts
                merged.append(contentsOf: localOnly)
                merged.sort { $0.createdAt > $1.createdAt }
                self.familyPosts = merged
                persistFamilyPosts()
            }
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to fetch family posts: \(error)")
            #endif
            // On failure, keep existing local posts — do NOT clear
        }
    }

    func createFamilyPost(text: String, mediaURLs: [String]) async throws {
        let response: CreatePostResponse = try await apiClient.post(
            "/v1/family/posts",
            body: CreatePostRequest(text: text, mediaURLs: mediaURLs)
        )
        // Add to local state immediately
        let post = FamilyPost(
            id: response.postId,
            authorId: currentUser?.id ?? "",
            authorName: currentUser?.displayName ?? "",
            authorInitial: currentUser?.avatarInitial ?? "?",
            authorAvatarPath: currentUser?.avatarLocalPath,
            text: text,
            mediaURLs: mediaURLs,
            createdAt: Date(),
            comments: [],
            commentCount: 0
        )
        await MainActor.run {
            familyPosts.insert(post, at: 0)
            persistFamilyPosts()
        }
    }

    func addComment(postId: String, text: String) async {
        do {
            let _: AddCommentResponse = try await apiClient.post(
                "/v1/family/posts/\(postId)/comments",
                body: AddCommentRequest(text: text)
            )
            // Add comment locally
            let comment = FamilyComment(
                id: UUID().uuidString,
                authorId: currentUser?.id ?? "",
                authorName: currentUser?.displayName ?? "",
                authorInitial: currentUser?.avatarInitial ?? "?",
                authorAvatarPath: currentUser?.avatarLocalPath,
                text: text,
                createdAt: Date()
            )
            await MainActor.run {
                if let idx = familyPosts.firstIndex(where: { $0.id == postId }) {
                    familyPosts[idx].comments.append(comment)
                    familyPosts[idx].commentCount += 1
                }
                persistFamilyPosts()
            }
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to add comment: \(error)")
            #endif
        }
    }

    func persistFamilyPosts() {
        localStore.saveFamilyPosts(familyPosts)
    }

    func uploadMedia(data: Data, mimeType: String) async throws -> String {
        // For now, use a simple base64 upload endpoint.
        // In production, this would upload to Firebase Storage directly.
        let base64 = data.base64EncodedString()
        let response: MediaUploadResponse = try await apiClient.post(
            "/v1/family/upload",
            body: ["data": base64, "mimeType": mimeType]
        )
        return response.url
    }

    // MARK: - Notification Preferences

    func syncNotificationPrefs() {
        let prefs = NotificationPrefsRequest(
            sosAlerts: UserDefaults.standard.object(forKey: "notif_sos_alerts") as? Bool ?? true,
            checkinReminder: UserDefaults.standard.object(forKey: "notif_checkin_reminder") as? Bool ?? true,
            checkinOverdue: UserDefaults.standard.object(forKey: "notif_checkin_overdue") as? Bool ?? true,
            familyFeed: UserDefaults.standard.object(forKey: "notif_family_feed") as? Bool ?? true
        )
        Task {
            do {
                let _: SuccessResponse = try await apiClient.put(
                    "/v1/user/notification-preferences",
                    body: prefs
                )
            } catch {
                #if DEBUG
                print("[Coordinator] Failed to sync notification prefs: \(error)")
                #endif
            }
        }
    }

    // MARK: - Guardian Management

    func createInviteCode() async throws -> CreateInviteResponse {
        #if DEBUG
        if devBypassLogin {
            // Generate a fake invite code for dev testing
            try await Task.sleep(nanoseconds: 500_000_000) // simulate network
            let code = String(format: "%06d", Int.random(in: 100000...999999))
            let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400))
            return CreateInviteResponse(
                inviteId: UUID().uuidString,
                code: code,
                expiresAt: expiry,
                status: "active"
            )
        }
        #endif
        let response: CreateInviteResponse = try await apiClient.post(
            "/v1/invite/create",
            body: CreateInviteRequest(role: userRole.rawValue)
        )
        return response
    }

    func updateGuardianPermissions(guardianId: String, permissions: GuardianPermissions) async throws {
        let _: SuccessResponse = try await apiClient.put(
            "/v1/protected/guardians/\(guardianId)/permissions",
            body: UpdatePermissionsRequest(
                canSeeLocation: permissions.canSeeLocation,
                canSeeBattery: permissions.canSeeBattery,
                canSeeHealth: permissions.canSeeHealth,
                canSeePhoneActivity: permissions.canSeePhoneActivity,
                canHearEmergencyAudio: permissions.canHearEmergencyAudio
            )
        )
    }

    func removeGuardian(guardianId: String) async throws {
        let _: SuccessResponse = try await apiClient.delete("/v1/protected/guardians/\(guardianId)")
        await MainActor.run {
            myGuardians.removeAll { $0.id == guardianId }
            localStore.saveGuardians(myGuardians)
        }
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
