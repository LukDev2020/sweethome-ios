import UIKit
import Combine
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

// MARK: - App Coordinator
//
// Central nervous system of the app. Wires together all services
// and algorithms, manages state, and routes events between layers.

final class AppCoordinator: ObservableObject {

    // Set to true to bypass login during development
    let devBypassLogin = false

    // MARK: - Published State

    @Published var currentUser: User?
    @Published var userRole: UserRole = .guardian
    @Published var protectedPersons: [ProtectedPerson] = []  // Guardian sees these
    @Published var myGuardians: [Guardian] = []               // Protected person sees these
    @Published var activeSOSEvent: SOSEvent?
    @Published var sosDeliveryFailed = false
    @Published var currentRiskScores: [String: BaselineScorer.RiskScore] = [:]
    @Published var currentCoverage: DutyScheduler.DayCoverage?
    @Published var authState: AuthManager.AuthState = .unknown
    @Published var showSignup = false
    @Published var signupPhone: String?
    @Published var signupCountry: CountryCode?
    @Published var timeline: [TimelineEntry] = []
    @Published var familyPosts: [FamilyPost] = []
    @Published var selectedHotline: SelectedHotline?
    @Published var pendingDeepLink: DeepLinkDestination?
    @Published var showInviteAccept = false
    @Published var pendingInviteCode: String?

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
    let liveActivityManager = GuardianActivityManager()
    let storeKitManager: StoreKitManager
    let paymentMethodManager: PaymentMethodManager

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
        paymentMethodManager = PaymentMethodManager(apiClient: apiClient)

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

        // Sync initial auth state before Combine subscription delivers asynchronously
        authState = authManager.state

        wireServices()
        restoreLocalState()
        observeAuthState()
        startLiveActivityIfNeeded()
    }

    // MARK: - Base URL

    private static func resolveBaseURL() -> String {
        if let override = Bundle.main.infoDictionary?["API_BASE_URL"] as? String, !override.isEmpty {
            return override
        }
        #if DEBUG
        return "http://127.0.0.1:5001/sweethome-b4e82/us-central1/api"
        #else
        return "https://us-central1-sweethome-b4e82.cloudfunctions.net/api"
        #endif
    }

    // MARK: - Restore Local State

    private func restoreLocalState() {
        if let user = localStore.loadCurrentUser() {
            currentUser = user
        }
        #if DEBUG
        if !devBypassLogin {
            if let role = localStore.loadUserRole() {
                userRole = role
            }
        }
        #else
        if let role = localStore.loadUserRole() {
            userRole = role
        }
        #endif
        myGuardians = localStore.loadGuardians()
        protectedPersons = localStore.loadProtectedPersons()
        activeSOSEvent = localStore.loadActiveSOSEvent()
        timeline = localStore.loadTimeline()
        familyPosts = localStore.loadFamilyPosts()

        #if DEBUG
        // In dev bypass mode, ensure a default user exists and seed mock data
        if devBypassLogin && currentUser == nil {
            let devUser = User(
                id: "dev_local_user",
                displayName: "陈明远",
                role: userRole,
                avatarInitial: "陈",
                timeZone: TimeZone(identifier: "America/Toronto") ?? .current,
                countryCode: "CA",
                cityName: "多伦多",
                createdAt: Date()
            )
            currentUser = devUser
            print("[AppCoordinator] Created dev seed user: \(devUser.displayName) role=\(userRole.rawValue)")
        } else if let u = currentUser {
            print("[AppCoordinator] Restored user: '\(u.displayName)' city='\(u.cityName)'")
        }
        // Seed mock data AFTER local store loading, so empty stores get filled
        if devBypassLogin {
            if userRole == .guardian && protectedPersons.isEmpty {
                protectedPersons = Self.devMockProtectedPersons
                print("[AppCoordinator] Seeded \(protectedPersons.count) mock protected persons")
            }
            if userRole == .protected_ && myGuardians.isEmpty {
                myGuardians = Self.devMockGuardians
                print("[AppCoordinator] Seeded \(myGuardians.count) mock guardians")
            }
            // Seed default hotline based on user's country
            if selectedHotline == nil {
                selectedHotline = SelectedHotline(
                    countryCode: "CA", countryName: "加拿大", flag: "🇨🇦",
                    emergency: "911", embassy: "+1-613-562-1616",
                    selectedPhone: "+1-416-594-2308", selectedLabel: "多伦多"
                )
            }
        }
        #endif

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
                // Mirror auth state as a @Published property on the coordinator,
                // since nested ObservableObject changes don't auto-propagate
                // to views that observe the coordinator via @EnvironmentObject.
                self.authState = state
                switch state {
                case .loggedIn(let userId):
                    UserDefaults.standard.set(userId, forKey: "currentUserId")
                    self.heartbeatService.userId = userId
                    #if canImport(FirebaseCrashlytics)
                    Crashlytics.crashlytics().setUserID(userId)
                    #endif
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
        #if DEBUG
        if devBypassLogin { return }
        #endif
        liveActivityManager.endAllActivities()
        currentUser = nil
        protectedPersons = []
        myGuardians = []
        activeSOSEvent = nil
        timeline = []
        familyPosts = []
        selectedHotline = nil
        showSignup = false
        signupPhone = nil
        signupCountry = nil
        localStore.clearAll()
        offlineQueue.clearAll()

        // Clear all user-specific UserDefaults
        let userKeys = [
            "onboardingComplete",
            "selected_hotline",
            "medical_card_cache",
            "custom_emergency_contacts",
            "local_emergency_contacts_v2",
            "notif_sos_alerts",
            "notif_checkin_reminder",
            "notif_checkin_overdue",
            "notif_family_feed",
            "login_failed_attempts",
            "login_lockout_until",
            "signup_failed_attempts",
            "signup_lockout_until",
        ]
        for key in userKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Deep Link Handling

    func handleDeepLink(_ url: URL) {
        guard let destination = DeepLinkRouter.parse(url: url) else { return }
        handleDeepLinkDestination(destination)
    }

    func handleUserActivity(_ activity: NSUserActivity) {
        guard let destination = DeepLinkRouter.parse(userActivity: activity) else { return }
        handleDeepLinkDestination(destination)
    }

    private func handleDeepLinkDestination(_ destination: DeepLinkDestination) {
        switch authManager.state {
        case .loggedIn:
            applyDeepLink(destination)
        default:
            // Store for after login
            pendingDeepLink = destination
        }
    }

    private func applyDeepLink(_ destination: DeepLinkDestination) {
        switch destination {
        case .invite(let code):
            pendingInviteCode = code
            showInviteAccept = true
        case .evidence:
            // Evidence links are handled by the web view; no in-app routing needed
            break
        case .sosEvent:
            // Navigate to SOS detail — triggers on guardian tab
            break
        }
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
        #if DEBUG
        if devBypassLogin && !protectedPersons.isEmpty { return }
        #endif
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
                        p.longitude.flatMap { lng in
                            p.locationTimestamp.map { ts in
                                Location(
                                    latitude: lat, longitude: lng,
                                    accuracy: p.locationAccuracy ?? 0,
                                    altitude: nil, speed: nil,
                                    timestamp: ts,
                                    address: p.locationAddress
                                )
                            }
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
        #if DEBUG
        if devBypassLogin && !myGuardians.isEmpty { return }
        #endif
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

    // MARK: - Selected Hotline

    func loadSelectedHotline() {
        // Try local cache first
        if let data = UserDefaults.standard.data(forKey: "selected_hotline"),
           let hotline = try? JSONDecoder().decode(SelectedHotline.self, from: data) {
            selectedHotline = hotline
        }
        // Then try server
        Task {
            do {
                let hotline: SelectedHotline? = try await apiClient.get("/v1/consulate/selected/me")
                if let hotline {
                    await MainActor.run {
                        self.selectedHotline = hotline
                        self.cacheSelectedHotline(hotline)
                    }
                }
            } catch {
                #if DEBUG
                print("[Coordinator] Failed to fetch selected hotline: \(error)")
                #endif
            }
        }
    }

    func saveSelectedHotline(_ hotline: SelectedHotline) {
        selectedHotline = hotline
        cacheSelectedHotline(hotline)
        Task {
            do {
                let _: SuccessResponse = try await apiClient.put(
                    "/v1/consulate/selected",
                    body: SelectedHotlineRequest(
                        countryCode: hotline.countryCode,
                        countryName: hotline.countryName,
                        flag: hotline.flag,
                        emergency: hotline.emergency,
                        embassy: hotline.embassy,
                        selectedPhone: hotline.selectedPhone,
                        selectedLabel: hotline.selectedLabel
                    )
                )
            } catch {
                #if DEBUG
                print("[Coordinator] Failed to save selected hotline to server: \(error)")
                #endif
            }
        }
    }

    func removeSelectedHotline() {
        selectedHotline = nil
        UserDefaults.standard.removeObject(forKey: "selected_hotline")
        Task {
            do {
                let _: SuccessResponse = try await apiClient.delete("/v1/consulate/selected")
            } catch {
                #if DEBUG
                print("[Coordinator] Failed to delete selected hotline from server: \(error)")
                #endif
            }
        }
    }

    private func cacheSelectedHotline(_ hotline: SelectedHotline) {
        if let data = try? JSONEncoder().encode(hotline) {
            UserDefaults.standard.set(data, forKey: "selected_hotline")
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

    // MARK: - Live Activity

    private func startLiveActivityIfNeeded() {
        let guardianName: String
        let guardianPhone: String
        let layers: Int

        if userRole == .protected_ {
            guardianName = myGuardians.first?.user.displayName ?? "守护者"
            guardianPhone = selectedHotline?.emergency ?? "911"
            layers = myGuardians.count
        } else {
            // Guardian role — show protected persons count
            guardianName = currentUser?.displayName ?? "守护者"
            guardianPhone = selectedHotline?.emergency ?? "911"
            layers = protectedPersons.count
        }

        liveActivityManager.startGuardianActivity(
            userName: currentUser?.displayName ?? "",
            guardianName: guardianName,
            guardianPhone: guardianPhone,
            protectionLayers: max(layers, 1)
        )
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

        // Update lock screen to SOS mode
        liveActivityManager.triggerSOS(
            localEmergencyNumber: selectedHotline?.emergency ?? "911"
        )

        addTimelineEntry(type: .sosTriggered, description: "触发紧急求助（\(method.rawValue)）")

        #if BETA
        // Beta: simulate escalation — skip real API call and immediately acknowledge
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.activeSOSEvent?.escalationState = .acknowledged
            self?.addTimelineEntry(type: .sosResolved, description: "[Beta 模拟] SOS 自动确认，未发送真实通知")
        }
        #else
        // Report to server (with delivery feedback)
        sosDeliveryFailed = false
        let sosLocation = locationManager.lastReportedLocation
        apiClient.postQueued("/v1/sos/trigger", body: SOSTriggerRequest(
            protectedPersonId: currentUser?.id ?? "",
            triggerMethod: method,
            latitude: sosLocation?.coordinate.latitude,
            longitude: sosLocation?.coordinate.longitude,
            batteryLevel: Double(UIDevice.current.batteryLevel)
        )) { [weak self] success in
            if !success {
                self?.sosDeliveryFailed = true
            }
        }
        #endif
    }

    func cancelSOS() {
        guard let sos = activeSOSEvent else { return }

        escalationEngine.resolve(by: currentUser?.id ?? "", resolution: .protectedCancelled)
        activeSOSEvent = nil
        localStore.saveActiveSOSEvent(nil)
        locationManager.exitSOSMode()

        // Restore lock screen to normal
        let guardianName = myGuardians.first?.user.displayName ?? "守护者"
        let guardianPhone = selectedHotline?.emergency ?? "911"
        liveActivityManager.cancelSOS(guardianName: guardianName, guardianPhone: guardianPhone)

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

        let checkinLocation = locationManager.lastReportedLocation
        apiClient.postQueued("/v1/checkin", body: CheckInRequest(
            userId: userId,
            latitude: checkinLocation?.coordinate.latitude,
            longitude: checkinLocation?.coordinate.longitude,
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

        // Keep lock screen card in sync
        liveActivityManager.updateLocation(
            accuracy: Int(location.accuracy),
            timestamp: location.timestamp
        )
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

    // MARK: - Emergency Contacts

    func fetchEmergencyContacts() async -> [LocalEmergencyContact] {
        do {
            let contacts: [LocalEmergencyContact] = try await apiClient.get("/v1/emergency-contacts")
            return contacts
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to fetch emergency contacts: \(error)")
            #endif
            return []
        }
    }

    func saveEmergencyContacts(_ contacts: [LocalEmergencyContact]) async {
        do {
            let _: SuccessResponse = try await apiClient.put(
                "/v1/emergency-contacts",
                body: contacts
            )
        } catch {
            #if DEBUG
            print("[Coordinator] Failed to save emergency contacts: \(error)")
            #endif
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

    // MARK: - Dev Mock Data

    #if DEBUG
    static let devMockProtectedPersons: [ProtectedPerson] = [
        ProtectedPerson(
            id: "pp-1",
            user: User(
                id: "pp-1", displayName: "陈小雨", role: .protected_,
                avatarInitial: "雨",
                timeZone: TimeZone(identifier: "Europe/Kiev")!,
                countryCode: "UA", cityName: "基辅",
                createdAt: Date().addingTimeInterval(-86400 * 180)
            ),
            guardians: [],
            protectionLayers: 3,
            lastCheckIn: Date().addingTimeInterval(-1800),
            lastKnownLocation: Location(
                latitude: 50.45, longitude: 30.52,
                accuracy: 15, altitude: nil, speed: nil,
                timestamp: Date().addingTimeInterval(-600)
            ),
            batteryLevel: 0.72,
            batteryState: .unplugged,
            lastPhoneActivity: Date().addingTimeInterval(-300),
            status: .normal
        ),
        ProtectedPerson(
            id: "pp-2",
            user: User(
                id: "pp-2", displayName: "陈小晴", role: .protected_,
                avatarInitial: "晴",
                timeZone: TimeZone(identifier: "Australia/Sydney")!,
                countryCode: "AU", cityName: "悉尼",
                createdAt: Date().addingTimeInterval(-86400 * 90)
            ),
            guardians: [],
            protectionLayers: 2,
            lastCheckIn: Date().addingTimeInterval(-86400 * 2),
            lastKnownLocation: Location(
                latitude: -33.87, longitude: 151.21,
                accuracy: 20, altitude: nil, speed: nil,
                timestamp: Date().addingTimeInterval(-7200)
            ),
            batteryLevel: 0.15,
            batteryState: .unplugged,
            lastPhoneActivity: Date().addingTimeInterval(-86400),
            status: .overdue
        ),
    ]

    static let devMockGuardians: [Guardian] = [
        Guardian(
            id: "g-1",
            user: User(
                id: "g-1", displayName: "妈妈", role: .guardian,
                avatarInitial: "妈",
                timeZone: TimeZone(identifier: "Asia/Shanghai")!,
                countryCode: "CN", cityName: "上海",
                createdAt: Date().addingTimeInterval(-86400 * 365)
            ),
            permissions: .defaultPermissions,
            isOnDuty: true,
            dutySchedule: nil,
            averageResponseTime: 45,
            linkedSince: Date().addingTimeInterval(-86400 * 180)
        ),
        Guardian(
            id: "g-2",
            user: User(
                id: "g-2", displayName: "姑姑", role: .guardian,
                avatarInitial: "姑",
                timeZone: TimeZone(identifier: "America/Toronto")!,
                countryCode: "CA", cityName: "多伦多",
                createdAt: Date().addingTimeInterval(-86400 * 200)
            ),
            permissions: GuardianPermissions(
                canSeeLocation: true, canSeeBattery: true,
                canSeeHealth: false, canSeePhoneActivity: false,
                canHearEmergencyAudio: false
            ),
            isOnDuty: false,
            dutySchedule: nil,
            averageResponseTime: 120,
            linkedSince: Date().addingTimeInterval(-86400 * 90)
        ),
    ]
    #endif
}
